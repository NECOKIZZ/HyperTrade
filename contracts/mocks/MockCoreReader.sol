// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IHyperCoreReader} from "../elysium/IHyperCoreReader.sol";

/// @notice Stands in for a HyperCore reader (HyperEVM L1Read today, Elysium's precompile later).
contract MockCoreReader is IHyperCoreReader {
    int256 public value6;
    uint64 public at;

    function set(int256 value6_, uint64 at_) external {
        value6 = value6_;
        at = at_;
    }

    function accountValue(address, uint32[] calldata) external view returns (int256, uint64) {
        return (value6, at);
    }
}

/// @notice Stands in for HyperEVM's accountMarginSummary precompile (etched at 0x...080F).
contract MockMarginSummary {
    mapping(bytes32 => int64) public av;

    function set(uint32 dex, address user, int64 value6) external {
        av[keccak256(abi.encode(dex, user))] = value6;
    }

    fallback(bytes calldata data) external returns (bytes memory) {
        return abi.encode(av[keccak256(data)], uint64(0), uint64(0), int64(0));
    }
}
