// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {HyperCorePerpFeed} from "../contracts/hypercore/HyperCorePerpFeed.sol";
import {MarketCalendar} from "../contracts/MarketCalendar.sol";
import {MockPrecompile} from "../contracts/mocks/MockPrecompile.sol";

contract HyperCoreAndCalendarTest is Test {
    address constant MARK = 0x0000000000000000000000000000000000000806;
    address constant ORACLE = 0x0000000000000000000000000000000000000807;
    uint32 constant SP500 = 110052; // xyz:SP500 (xyz = dex 1, index 52), szDecimals 3

    function etch() internal {
        MockPrecompile impl = new MockPrecompile();
        vm.etch(MARK, address(impl).code);
        vm.etch(ORACLE, address(impl).code);
    }

    function test_reads_hip3_price_in_18_decimals() public {
        etch();
        // xyz:SP500 on 2026-11-21: oracle 7018.7, mark 7017.5; szDecimals 3 -> 3 price decimals
        MockPrecompile(ORACLE).set(SP500, 7018700);
        MockPrecompile(MARK).set(SP500, 7017500);
        HyperCorePerpFeed f = new HyperCorePerpFeed(SP500, 3, 0.02e18);
        (uint256 p, bool ok) = f.read();
        assertEq(p, 7018.7e18);
        assertTrue(ok);
    }

    function test_refuses_when_mark_drifts_from_oracle() public {
        etch();
        MockPrecompile(ORACLE).set(SP500, 7000000);
        MockPrecompile(MARK).set(SP500, 7300000); // book pushed 4.3% away
        HyperCorePerpFeed f = new HyperCorePerpFeed(SP500, 3, 0.02e18);
        (, bool ok) = f.read();
        assertFalse(ok);
    }

    function test_calendar_week() public {
        MarketCalendar c = new MarketCalendar(address(this));
        assertTrue(c.isOpen(1795014000)); //  Wed 15:00 UTC
        assertTrue(c.isOpen(1795204740)); //  Fri 19:59 UTC
        assertFalse(c.isOpen(1795204800)); // Fri 20:00 UTC
        assertFalse(c.isOpen(1795262400)); // Sat
        assertFalse(c.isOpen(1795444140)); // Mon 14:29 UTC
        assertTrue(c.isOpen(1795444200)); //  Mon 14:30 UTC
    }

    function test_calendar_holiday() public {
        MarketCalendar c = new MarketCalendar(address(this));
        uint64 thanksgiving = 1795651200; // Thu 2026-11-26 00:00 UTC
        c.addClosure(thanksgiving, thanksgiving + 1 days);
        assertFalse(c.isOpen(1795705200)); // Thu 15:00 UTC
        vm.prank(address(0xBAD));
        vm.expectRevert();
        c.addClosure(1, 2);
    }
}
