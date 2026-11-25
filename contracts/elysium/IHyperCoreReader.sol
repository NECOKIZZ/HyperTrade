// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice The one thing Asphodel needs from a HyperCore read precompile: what an account is worth.
///
/// Two implementations:
///   - HyperEvmCoreReader: HyperEVM's L1Read precompile (live today, ~1 s data).
///   - Elysium's market-data precompile (~70 ms HyperCore blocks, 150-350 ms fresh in the EVM), which
///     ships in an ArbOS upgrade about four weeks after Elysium mainnet. Its address and ABI aren't
///     published yet; on the day it ships, its adapter implements this interface (see docs/ELYSIUM.md)
///     and HyperCoreNavFeed works unchanged.
interface IHyperCoreReader {
    /// @return usd6 the account's value on HyperCore across `dexes` (perp margin accounts), USD, 6 decimals
    /// @return coreTime the HyperCore timestamp (seconds) the read was taken at
    function accountValue(address user, uint32[] calldata dexes) external view returns (int256 usd6, uint64 coreTime);
}
