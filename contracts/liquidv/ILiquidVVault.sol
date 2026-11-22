// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice A LiquidV trader vault on HyperEVM. Its share token IS the trader token (`$vTRADER`):
/// an ERC-20 (18 decimals) minted by depositing USDC at NAV (1% fee) and redeemed at NAV (0.3% exit fee).
///
/// Checked against the deployed code (beacon implementation 0xac21136171932299828130c699e88e7159be8849)
/// on a fork of HyperEVM, 2026-11-22, with vANSEM's vault 0xC7F1330ffa5644ED14FBD0ff0efa793669bCCe91
/// (test/fork/LiquidVVault.fork.t.sol):
///   - totalAssets() = availableIdle() (USDC on HyperEVM) + coreAssets() (its HyperCore account, read
///     live through the precompiles; matched Hyperliquid's live account value to the cent).
///   - deposit(assets, receiver, minShares): 3rd argument is a minimum of shares (preview + 1 reverts).
///     $10 in -> shares worth $9.90 (1% fee).
///   - redeem(shares, receiver, owner, minAssets): 4th argument is a minimum of assets. Instant, and
///     only up to availableIdle(); more reverts.
///   - requestRedeem(shares, receiver, owner, minAssets) -> (id, quotedAssets): the shares move into the
///     vault and wait in a queue. processRedemptions(n) can be called by anyone; it pays requests in
///     order once the vault has the cash on HyperEVM, straight to the receiver, at the price when
///     processed (a $490 quote paid $444.81 after a 10% fall: no price protection). queueHead() moves
///     past a request's id once it is paid.
///   - stale(): set by anyone (markStale) once the keeper misses its heartbeat for staleAfter (1 hour).
///     paused(): set by the guardian. Both block deposits only: redeems still work and NAV is still live.
///   - Deposits are capped by maxDeposit(): maxTotalAssets ($5,000) and the trader's own account size.
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

    /// queued redeem for more than idle cash (selector 0x8181e161); returns the request id and a quote
    function requestRedeem(uint256 shares, address receiver, address owner, uint256 minAssets)
        external
        returns (uint256 id, uint256 assets);

    /// pay up to n queued requests that the vault has cash for (anyone can call; selector 0xb4dc8294)
    function processRedemptions(uint256 n) external returns (uint256 processed);

    function queueHead() external view returns (uint256);

    // LiquidV extras
    function availableIdle() external view returns (uint256);
    function stale() external view returns (bool);
    function paused() external view returns (bool);
    function activated() external view returns (bool);
    function exitFeeBps() external view returns (uint256);
    function traderWallet() external view returns (address);
}
