// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice A LiquidV trader vault on HyperEVM. Its share token IS the trader token (`$vTRADER`):
/// an ERC-20 (18 decimals) minted by depositing USDC at NAV (1% fee) and redeemed at NAV (0.3% exit fee).
///
/// Read from the live vault for trader 0x0149…abdb (vault 0x7952e97de05cb8be5657f4a0096f360e6cb39af8,
/// beacon implementation 0xac21136171932299828130c699e88e7159be8849) on 2026-11-22:
///   asset() = USDC 0xb88339CB7199b77E23DB6E890353E22632Ba630f; totalAssets() = availableIdle() + coreAssets(),
///   and coreAssets() equalled the vault's live HyperCore account value to the cent, so NAV is read live.
///   previewDeposit / convertToShares = 0.990 (1% mint fee); previewRedeem / convertToAssets = 0.997 (0.3% exit fee).
///   Instant redeems only go up to availableIdle(); bigger exits use requestRedeem (a queue).
/// Function names come from the implementation's selectors; argument meanings of the 4-argument
/// deposit/redeem (a minimum out) are inferred and must be confirmed with LiquidV.
interface ILiquidVVault {
    // ERC-20 (the trader token)
    function balanceOf(address who) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);

    // ERC-4626
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function maxDeposit(address receiver) external view returns (uint256);

    /// deposit with a minimum number of shares out (selector 0xbc157ac1)
    function deposit(uint256 assets, address receiver, uint256 minShares) external returns (uint256 shares);

    /// instant redeem with a minimum of assets out (selector 0x9f40a7b3); reverts InsufficientIdle
    function redeem(uint256 shares, address receiver, address owner, uint256 minAssets) external returns (uint256 assets);

    // LiquidV extras
    function availableIdle() external view returns (uint256);
    function stale() external view returns (bool);
    function paused() external view returns (bool);
    function activated() external view returns (bool);
    function exitFeeBps() external view returns (uint256);
    function traderWallet() external view returns (address);
}
