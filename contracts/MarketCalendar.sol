// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarketCalendar} from "./interfaces/IMarketCalendar.sol";

/// @notice US stock market calendar for Asphodel's stock tokens.
///
/// Weekly closure, in UTC, wide enough for both winter and summer time:
///   from Friday 20:00 UTC (4pm New York in summer) to Monday 14:30 UTC (9:30am New York in winter).
/// Holidays and other closures (half days, halts) are added by the owner as [start, end) windows.
///
/// While closed: no new tickets, stops and maxes don't fire, and the boost part of a sale uses the
/// 1-hour average price (spec: Stocks section §5).
contract MarketCalendar is IMarketCalendar, Ownable {
    uint256 internal constant DAY = 1 days;
    uint256 internal constant FRIDAY_CLOSE = 20 hours;
    uint256 internal constant MONDAY_OPEN = 14 hours + 30 minutes;

    struct Window {
        uint64 start;
        uint64 end;
    }

    Window[] public closures;

    event ClosureAdded(uint64 start, uint64 end);
    event ClosureRemoved(uint256 index);

    error BadWindow();

    constructor(address owner_) Ownable(owner_) {}

    function addClosure(uint64 start, uint64 end) external onlyOwner {
        if (end <= start) revert BadWindow();
        closures.push(Window(start, end));
        emit ClosureAdded(start, end);
    }

    function removeClosure(uint256 index) external onlyOwner {
        closures[index] = closures[closures.length - 1];
        closures.pop();
        emit ClosureRemoved(index);
    }

    function closureCount() external view returns (uint256) {
        return closures.length;
    }

    function isOpen(uint256 t) public view returns (bool) {
        if (isWeekend(t)) return false;
        uint256 n = closures.length;
        for (uint256 i = 0; i < n; i++) {
            if (t >= closures[i].start && t < closures[i].end) return false;
        }
        return true;
    }

    /// 0 = Sunday ... 6 = Saturday (1970-01-01 was a Thursday).
    function dayOfWeek(uint256 t) public pure returns (uint256) {
        return (t / DAY + 4) % 7;
    }

    function isWeekend(uint256 t) public pure returns (bool) {
        uint256 dow = dayOfWeek(t);
        uint256 sec = t % DAY;
        if (dow == 6 || dow == 0) return true;
        if (dow == 5 && sec >= FRIDAY_CLOSE) return true;
        if (dow == 1 && sec < MONDAY_OPEN) return true;
        return false;
    }
}
