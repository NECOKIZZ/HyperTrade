// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Test stand-in for a LiquidV trader vault: its share is the trader token. NAV per share is set
/// by the test (the trader's PnL). 1% mint fee, 0.3% exit fee by default; instant redeems capped at idle.
/// Needs a USDC reserve to pay gains (funded by the test).
contract MockLiquidVVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdcToken;
    uint256 public pps; //            USD per share, 18 decimals
    uint256 public mintFeeWad;
    uint256 public exitFeeBps;
    uint256 public idle = type(uint256).max;
    uint256 public cap = type(uint256).max;
    bool public stale;
    bool public paused;
    bool public activated = true;
    address public traderWallet = address(0x0149804A7c4c0d4D08F4C86d37C2FA1D3CaDaBdb);

    error InsufficientIdle(uint256 need, uint256 idle);

    struct Request {
        address owner;
        address receiver;
        uint256 shares;
    }

    Request[] public requests;
    uint256 public queueHead;

    constructor(IERC20 usdc_, uint256 pps_, uint256 mintFeeWad_, uint256 exitFeeBps_) ERC20("LiquidV v014980", "v014980") {
        usdcToken = usdc_;
        pps = pps_;
        mintFeeWad = mintFeeWad_;
        exitFeeBps = exitFeeBps_;
    }

    // test controls
    function setPps(uint256 p) external { pps = p; }
    function setIdle(uint256 v) external { idle = v; }
    function setCap(uint256 v) external { cap = v; }
    function setStale(bool v) external { stale = v; }
    function setPaused(bool v) external { paused = v; }

    function asset() external view returns (address) { return address(usdcToken); }
    function totalAssets() external view returns (uint256) { return convertToAssets(totalSupply()); }
    function availableIdle() external view returns (uint256) { return idle; }
    function maxDeposit(address) external view returns (uint256) { return cap; }

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
        require(!paused && assets <= cap, "vault: deposit refused");
        shares = previewDeposit(assets);
        require(shares >= minShares, "vault: min shares");
        usdcToken.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    /// Like the real vault: shares wait inside the vault; paid in order, at the price when processed,
    /// straight to the receiver, once idle cash covers them. minAssets is not enforced at processing.
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
            if (assets > idle) break;
            if (idle != type(uint256).max) idle -= assets;
            _burn(address(this), r.shares);
            usdcToken.safeTransfer(r.receiver, assets);
            queueHead++;
            processed++;
        }
    }

    function redeem(uint256 shares, address receiver, address owner, uint256 minAssets) external returns (uint256 assets) {
        require(owner == msg.sender, "vault: owner");
        assets = previewRedeem(shares);
        if (assets > idle) revert InsufficientIdle(assets, idle);
        require(assets >= minAssets, "vault: min assets");
        if (idle != type(uint256).max) idle -= assets;
        _burn(owner, shares);
        usdcToken.safeTransfer(receiver, assets);
    }
}
