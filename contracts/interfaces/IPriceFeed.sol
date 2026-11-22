// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice A live price for one asset, as read at this block.
interface IPriceFeed {
    /// @return priceWad USD per one unit of the asset, 18 decimals
    /// @return ok false if the price must not be used (bad read, mark far from oracle, ...)
    function read() external view returns (uint256 priceWad, bool ok);
}
