// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal HyperCore read precompiles (HyperEVM). Addresses and encodings follow
/// hyperliquid-dev/hyper-evm-lib (src/common/HLConstants.sol, src/PrecompileLib.sol).
library HyperCore {
    address internal constant MARK_PX = 0x0000000000000000000000000000000000000806;
    address internal constant ORACLE_PX = 0x0000000000000000000000000000000000000807;

    error PrecompileFailed(address precompile);

    /// Raw perp mark price. Perp prices have (6 - szDecimals) decimals.
    function markPx(uint32 perpIndex) internal view returns (uint64) {
        return _px(MARK_PX, perpIndex);
    }

    /// Raw perp oracle price. Perp prices have (6 - szDecimals) decimals.
    function oraclePx(uint32 perpIndex) internal view returns (uint64) {
        return _px(ORACLE_PX, perpIndex);
    }

    function _px(address precompile, uint32 perpIndex) private view returns (uint64) {
        (bool ok, bytes memory out) = precompile.staticcall(abi.encode(perpIndex));
        if (!ok || out.length < 32) revert PrecompileFailed(precompile);
        return abi.decode(out, (uint64));
    }
}
