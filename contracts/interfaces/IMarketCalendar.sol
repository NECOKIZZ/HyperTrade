// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Is the asset's real market open? (Stock perps trade 24/7 on Hyperliquid; the stocks don't.)
interface IMarketCalendar {
    function isOpen(uint256 timestamp) external view returns (bool);
}
