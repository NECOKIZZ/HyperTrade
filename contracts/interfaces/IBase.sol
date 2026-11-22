// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice The real exposure behind every ticket (the "base"), and Hearth's hedge.
/// One unit = one unit of the asset (e.g. one S&P 500 index point contract on Hyperliquid).
/// The market owns all units; the base contract only buys and sells them at the live price.
interface IBase {
    /// Spend `usdc` (pulled from the caller) on units at the live price, less the mint fee.
    function buy(uint256 usdc) external returns (uint256 unitsWad);

    /// Sell `unitsWad` units owned by the caller at the live price, less the exit fee. USDC goes to the caller.
    function sell(uint256 unitsWad) external returns (uint256 usdc);

    /// Units owned by `who`.
    function unitsOf(address who) external view returns (uint256);

    /// Fees charged by the base on buys and sells, 18 decimals (0.001e18 = 0.1%).
    function mintFeeWad() external view returns (uint256);
    function exitFeeWad() external view returns (uint256);
}
