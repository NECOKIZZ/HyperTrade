// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import {IHyperCoreReader} from "./IHyperCoreReader.sol";

/// @notice NAV per share of a LiquidV vault, computed with LiquidV's own formula
///   NAV per share = (idle cash + HyperCore account value) / shares
/// where the HyperCore account value (the part that moves with every price tick) is read live through
/// a HyperCore read precompile, and idle cash and share supply (which only change when people mint or
/// redeem) come from a relay of the vault's HyperEVM state.
///
/// This is the precompile slot: on Elysium, deploy it with Elysium's reader adapter and a Series gets a
/// NAV that is ~150-350 ms fresh instead of waiting on a relay. Until then the market uses
/// LiquidVNavFeed on the MirrorVault (testnet) or on the real vault (HyperEVM).
contract HyperCoreNavFeed is IPriceFeed {
    IHyperCoreReader public immutable reader;
    address public immutable vaultAccount; //   the vault's HyperCore account (= its HyperEVM address)
    uint256 public immutable maxCoreAge; //     seconds: the core read must be at least this fresh
    uint256 public immutable maxBookAge; //     seconds: the relayed idle/supply must be at least this fresh
    uint32[] internal dexes;

    address public keeper;
    address public admin;
    uint256 public idle6; //        the vault's idle USDC on HyperEVM, 6 decimals
    uint256 public supply; //       the vault's share supply, 18 decimals
    uint256 public bookAt; //       when idle/supply were relayed

    event Book(uint256 idle6, uint256 supply);

    error NotKeeper();
    error NotAdmin();

    constructor(
        IHyperCoreReader reader_,
        address vaultAccount_,
        uint32[] memory dexes_,
        uint256 maxCoreAge_,
        uint256 maxBookAge_,
        address keeper_
    ) {
        reader = reader_;
        vaultAccount = vaultAccount_;
        dexes = dexes_;
        maxCoreAge = maxCoreAge_;
        maxBookAge = maxBookAge_;
        keeper = keeper_;
        admin = msg.sender;
    }

    function setBook(uint256 idle6_, uint256 supply_) external {
        if (msg.sender != keeper) revert NotKeeper();
        idle6 = idle6_;
        supply = supply_;
        bookAt = block.timestamp;
        emit Book(idle6_, supply_);
    }

    function setKeeper(address k) external {
        if (msg.sender != admin) revert NotAdmin();
        keeper = k;
    }

    function perpDexes() external view returns (uint32[] memory) {
        return dexes;
    }

    function read() external view returns (uint256 priceWad, bool ok) {
        if (supply == 0 || block.timestamp - bookAt > maxBookAge) return (0, false);
        (int256 core6, uint64 coreTime) = reader.accountValue(vaultAccount, dexes);
        if (coreTime + maxCoreAge < block.timestamp) return (0, false); // the read is old: fail visibly
        int256 total6 = int256(idle6) + core6;
        if (total6 <= 0) return (0, false);
        // USD (6 dp) per share (18 dp) -> USD per share, 18 decimals
        priceWad = uint256(total6) * 1e30 / supply;
        ok = true;
    }
}
