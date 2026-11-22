// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import {HyperCore} from "./HyperCore.sol";

/// @notice Price of one Hyperliquid perp (e.g. a HIP-3 stock market such as xyz:SP500), read live
/// from HyperCore. Uses the oracle price; refuses it when the mark price has drifted too far from it
/// (a thin or pushed book).
///
/// HIP-3 asset ids are 100000 + dexIndex * 10000 + indexInDex (xyz is dex 1: xyz:SP500 = 110052,
/// xyz:XYZ100 = 110000, xyz:NVDA = 110002, from Hyperliquid's API on 2026-11-21).
/// TO VERIFY ON TESTNET: that the price precompiles take that id for HIP-3 markets.
contract HyperCorePerpFeed is IPriceFeed {
    uint32 public immutable perpIndex;
    uint8 public immutable szDecimals;
    uint256 public immutable maxMarkDeviationWad; // e.g. 0.02e18 = 2%
    uint256 private immutable scale;              // raw price -> 18 decimals

    error BadDecimals();

    constructor(uint32 perpIndex_, uint8 szDecimals_, uint256 maxMarkDeviationWad_) {
        if (szDecimals_ > 6) revert BadDecimals();
        perpIndex = perpIndex_;
        szDecimals = szDecimals_;
        maxMarkDeviationWad = maxMarkDeviationWad_;
        // raw has (6 - szDecimals) decimals; WAD has 18.
        scale = 10 ** (12 + uint256(szDecimals_));
    }

    function read() external view returns (uint256 priceWad, bool ok) {
        uint256 oracle = uint256(HyperCore.oraclePx(perpIndex)) * scale;
        uint256 mark = uint256(HyperCore.markPx(perpIndex)) * scale;
        if (oracle == 0 || mark == 0) return (oracle, false);
        uint256 diff = mark > oracle ? mark - oracle : oracle - mark;
        ok = diff * 1e18 <= maxMarkDeviationWad * oracle;
        priceWad = oracle;
    }
}
