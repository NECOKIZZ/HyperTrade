// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IBase} from "../interfaces/IBase.sol";
import {IPriceFeed} from "../interfaces/IPriceFeed.sol";

/// @notice Test base: buys/sells units at the feed price with fixed fees, settled instantly.
/// Needs a USDC reserve to pay out gains (funded by the test).
contract MockBase is IBase {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    IPriceFeed public immutable feed;
    uint256 public immutable mintFeeWad;
    uint256 public immutable exitFeeWad;
    mapping(address => uint256) public unitsOf;

    constructor(IERC20 usdc_, IPriceFeed feed_, uint256 mintFee_, uint256 exitFee_) {
        usdc = usdc_;
        feed = feed_;
        mintFeeWad = mintFee_;
        exitFeeWad = exitFee_;
    }

    function _price() internal view returns (uint256 p) {
        (p,) = feed.read();
    }

    function buy(uint256 amount) external returns (uint256 units) {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        // amount (6 dp) -> USD WAD, less the fee, at the price
        units = Math.mulDiv(amount * 1e12, 1e18, Math.mulDiv(_price(), 1e18 + mintFeeWad, 1e18));
        unitsOf[msg.sender] += units;
    }

    function sell(uint256 units) external returns (uint256 amount) {
        unitsOf[msg.sender] -= units;
        uint256 usd = Math.mulDiv(Math.mulDiv(units, _price(), 1e18), 1e18 - exitFeeWad, 1e18);
        amount = usd / 1e12;
        usdc.safeTransfer(msg.sender, amount);
    }
}
