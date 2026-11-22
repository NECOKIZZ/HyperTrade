// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPriceFeed} from "../interfaces/IPriceFeed.sol";

contract MockFeed is IPriceFeed {
    uint256 public priceWad;
    bool public ok = true;

    constructor(uint256 p) {
        priceWad = p;
    }

    function set(uint256 p) external {
        priceWad = p;
    }

    function setOk(bool v) external {
        ok = v;
    }

    function read() external view returns (uint256, bool) {
        return (priceWad, ok);
    }
}
