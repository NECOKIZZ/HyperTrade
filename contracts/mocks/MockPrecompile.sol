// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Stands in for a HyperCore price precompile in tests (etched at 0x...0806 / 0x...0807).
contract MockPrecompile {
    mapping(uint32 => uint64) public px;

    function set(uint32 index, uint64 value) external {
        px[index] = value;
    }

    fallback(bytes calldata data) external returns (bytes memory) {
        uint32 index = abi.decode(data, (uint32));
        return abi.encode(px[index]);
    }
}
