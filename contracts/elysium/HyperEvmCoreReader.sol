// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IHyperCoreReader} from "./IHyperCoreReader.sol";

/// @notice IHyperCoreReader on HyperEVM's L1Read precompile (accountMarginSummary, 0x...080F), the same
/// read LiquidV's own vaults use for coreAssets(). Encoding follows hyperliquid-dev/hyper-evm-lib:
/// input abi.encode(uint32 perpDexIndex, address user), output
/// (int64 accountValue, uint64 marginUsed, uint64 ntlPos, int64 rawUsd), USD with 6 decimals.
/// L1Read carries no HyperCore timestamp, so coreTime is this block's time.
contract HyperEvmCoreReader is IHyperCoreReader {
    address public constant MARGIN_SUMMARY = 0x000000000000000000000000000000000000080F;

    error PrecompileFailed();

    function accountValue(address user, uint32[] calldata dexes) external view returns (int256 usd6, uint64 coreTime) {
        for (uint256 i = 0; i < dexes.length; i++) {
            (bool ok, bytes memory out) = MARGIN_SUMMARY.staticcall(abi.encode(dexes[i], user));
            if (!ok || out.length < 128) revert PrecompileFailed();
            (int64 av,,,) = abi.decode(out, (int64, uint64, uint64, int64));
            usd6 += av;
        }
        coreTime = uint64(block.timestamp);
    }
}
