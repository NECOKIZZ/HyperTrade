// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title A LiquidV trader vault's stand-in on Elysium testnet.
/// @notice LiquidV's vaults live on HyperEVM; Elysium testnet has none. This vault has the same surface
/// the market uses (ILiquidVVault) and its NAV per share follows a REAL LiquidV vault on HyperEVM
/// (e.g. vANSEM), pushed by our keeper (services/keeper.ts). So testnet tickets move with a real trader.
///
/// Fees, idle cash and the redemption queue behave like the real vault (checked on a fork):
/// 1% mint fee, 0.3% exit fee, instant redeems only up to idle cash, bigger exits queue and are paid at
/// the price when processed.
///
/// `activated()` is false while the relay is older than `maxRelayAge`: LiquidVNavFeed then reports no
/// price, so nothing fills and no stop or Crown fires on an old number. `stale()` / `paused()` copy the
/// real vault's flags (they block new tickets only).
contract MirrorVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdcToken;
    address public immutable source; //       the real LiquidV vault on HyperEVM
    uint256 public immutable sourceChainId; // 999
    address public immutable traderWallet; // the Hyperliquid trader it mirrors
    uint256 public immutable maxRelayAge; //  seconds

    address public keeper;
    address public admin;

    uint256 public pps; //            USD per share, 18 decimals (the real vault's convertToAssets(1e18) x 1e12)
    uint256 public relayedAt; //      timestamp of the last relay
    uint256 public mintFeeWad; //     1e16 = 1%
    uint256 public exitFeeBps; //     30 = 0.3%
    uint256 public idle = type(uint256).max; // USDC (6 dp) payable instantly
    uint256 public cap = type(uint256).max; //  max deposit (LiquidV caps vaults at $5,000)
    bool public stale;
    bool public paused;

    struct Request {
        address owner;
        address receiver;
        uint256 shares;
    }

    Request[] public requests;
    uint256 public queueHead;

    event Relayed(uint256 pps, bool stale, bool paused, uint256 idle);

    error NotKeeper();
    error NotAdmin();
    error InsufficientIdle(uint256 need, uint256 idle);

    constructor(
        IERC20 usdc_,
        string memory name_,
        string memory symbol_,
        address source_,
        uint256 sourceChainId_,
        address traderWallet_,
        uint256 pps_,
        uint256 mintFeeWad_,
        uint256 exitFeeBps_,
        uint256 maxRelayAge_,
        address keeper_
    ) ERC20(name_, symbol_) {
        usdcToken = usdc_;
        source = source_;
        sourceChainId = sourceChainId_;
        traderWallet = traderWallet_;
        pps = pps_;
        relayedAt = block.timestamp;
        mintFeeWad = mintFeeWad_;
        exitFeeBps = exitFeeBps_;
        maxRelayAge = maxRelayAge_;
        keeper = keeper_;
        admin = msg.sender;
    }

    // ---------------------------------------------------------------- relay
    /// The real vault's state, as read on HyperEVM. `idle_` is in this vault's own USDC (6 dp), scaled by
    /// the keeper to this vault's size (type(uint256).max = no limit).
    function relay(uint256 pps_, bool stale_, bool paused_, uint256 idle_) external {
        if (msg.sender != keeper) revert NotKeeper();
        pps = pps_;
        stale = stale_;
        paused = paused_;
        idle = idle_;
        relayedAt = block.timestamp;
        emit Relayed(pps_, stale_, paused_, idle_);
    }

    function setKeeper(address k) external {
        if (msg.sender != admin) revert NotAdmin();
        keeper = k;
    }

    function setCap(uint256 c) external {
        if (msg.sender != admin) revert NotAdmin();
        cap = c;
    }

    // ---------------------------------------------------------------- the LiquidV surface
    function activated() public view returns (bool) {
        return block.timestamp - relayedAt <= maxRelayAge;
    }

    function asset() external view returns (address) {
        return address(usdcToken);
    }

    function totalAssets() external view returns (uint256) {
        return convertToAssets(totalSupply());
    }

    function availableIdle() external view returns (uint256) {
        uint256 bal = usdcToken.balanceOf(address(this));
        return idle < bal ? idle : bal;
    }

    function maxDeposit(address) external view returns (uint256) {
        return cap;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return Math.mulDiv(shares, pps, 1e18) / 1e12;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return Math.mulDiv(assets * 1e12, 1e18, pps);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return Math.mulDiv(assets * 1e12, 1e18, Math.mulDiv(pps, 1e18 + mintFeeWad, 1e18));
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return Math.mulDiv(convertToAssets(shares), 10_000 - exitFeeBps, 10_000);
    }

    function deposit(uint256 assets, address receiver, uint256 minShares) external returns (uint256 shares) {
        require(!paused && !stale && activated() && assets <= cap, "vault: deposit refused");
        shares = previewDeposit(assets);
        require(shares >= minShares, "vault: min shares");
        usdcToken.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function redeem(uint256 shares, address receiver, address owner, uint256 minAssets)
        external
        returns (uint256 assets)
    {
        require(owner == msg.sender, "vault: owner");
        assets = previewRedeem(shares);
        uint256 can = this.availableIdle();
        if (assets > can) revert InsufficientIdle(assets, can);
        require(assets >= minAssets, "vault: min assets");
        _useIdle(assets);
        _burn(owner, shares);
        usdcToken.safeTransfer(receiver, assets);
    }

    /// Shares wait inside the vault and are paid in order, at the price when processed.
    function requestRedeem(uint256 shares, address receiver, address owner, uint256)
        external
        returns (uint256 id, uint256 assets)
    {
        require(owner == msg.sender, "vault: owner");
        _transfer(owner, address(this), shares);
        id = requests.length;
        requests.push(Request(owner, receiver, shares));
        assets = previewRedeem(shares);
    }

    function processRedemptions(uint256 n) external returns (uint256 processed) {
        while (processed < n && queueHead < requests.length) {
            Request memory r = requests[queueHead];
            uint256 assets = previewRedeem(r.shares);
            if (assets > this.availableIdle()) break;
            _useIdle(assets);
            _burn(address(this), r.shares);
            usdcToken.safeTransfer(r.receiver, assets);
            queueHead++;
            processed++;
        }
    }

    function queueLength() external view returns (uint256) {
        return requests.length;
    }

    function _useIdle(uint256 assets) internal {
        if (idle != type(uint256).max) idle -= assets;
    }
}
