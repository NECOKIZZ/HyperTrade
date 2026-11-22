// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import {ILiquidVVault} from "./ILiquidVVault.sol";

/// @notice NAV of one `$vTRADER` share, read live from the LiquidV vault (which reads its HyperCore
/// account through the precompiles). Never LiquidV's published or indexed rate (spec v0.5 §4.3).
/// The price stays usable while the vault is stale or paused: those only stop new deposits, and the NAV
/// is still read live from HyperCore (checked on a fork). The market refuses new tickets then.
contract LiquidVNavFeed is IPriceFeed {
    ILiquidVVault public immutable vault;

    constructor(ILiquidVVault vault_) {
        vault = vault_;
    }

    function read() external view returns (uint256 priceWad, bool ok) {
        // USDC (6 decimals) per 1e18 shares -> USD per share, 18 decimals
        priceWad = vault.convertToAssets(1e18) * 1e12;
        ok = priceWad > 0 && vault.activated();
    }
}
