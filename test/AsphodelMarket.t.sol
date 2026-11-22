// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AsphodelMarket} from "../contracts/AsphodelMarket.sol";
import {MarketCalendar} from "../contracts/MarketCalendar.sol";
import {IBase} from "../contracts/interfaces/IBase.sol";
import {IPriceFeed} from "../contracts/interfaces/IPriceFeed.sol";
import {IMarketCalendar} from "../contracts/interfaces/IMarketCalendar.sol";
import {MockUSDC} from "../contracts/mocks/MockUSDC.sol";
import {MockFeed} from "../contracts/mocks/MockFeed.sol";
import {MockBase} from "../contracts/mocks/MockBase.sol";

/// Asphodel on a Hyperliquid stock market (think xyz:SP500 at 7,000). Numbers follow the spec's
/// worked example: $100 in, 2x, max $3, stop $0.25.
contract AsphodelMarketTest is Test {
    uint256 constant WED = 1795014000; // Wednesday 2026-11-18 15:00 UTC (market open)
    uint256 constant SAT = 1795262400; // Saturday 2026-11-21 12:00 UTC
    uint256 constant MON_OPEN = 1795444200; // Monday 2026-11-23 14:30 UTC
    uint256 constant P0 = 7000e18;

    MockUSDC usdc;
    MockFeed feed;
    MockBase base;
    MarketCalendar cal;
    AsphodelMarket m;

    address alice = address(0xA11CE);
    address bob = address(0xB0B); //   Hearth LP
    address carol = address(0xCA201); // Ember LP

    function cfg(uint256 fee) internal pure returns (AsphodelMarket.Config memory c) {
        c = AsphodelMarket.Config({
            B: 2e18,
            C: 3e18,
            stopPrice: 0.25e18,
            hearthShare: 0.5e18,
            buyFee: fee,
            sellFee: fee,
            lpFeeShare: 0.6e18,
            mintBoostLimit: 4e18,
            gapGuardK: 0,
            hedgeHaircut: 0.2e18,
            carryPerSecond: 0,
            confirmUpdates: 2,
            confirmSeconds: 60,
            gapWindow: 32,
            maxBatch: 50,
            maxOrderAge: 100
        });
    }

    function deploy(AsphodelMarket.Config memory c, uint256 baseFee) internal {
        vm.warp(WED);
        usdc = new MockUSDC();
        feed = new MockFeed(P0);
        base = new MockBase(IERC20(address(usdc)), IPriceFeed(address(feed)), baseFee, baseFee);
        cal = new MarketCalendar(address(this));
        m = new AsphodelMarket(
            "S&P 500 2x", "SPX2X", IERC20(address(usdc)), IBase(address(base)), IPriceFeed(address(feed)),
            IMarketCalendar(address(cal)), c, address(this)
        );
        usdc.mint(address(base), 10_000_000e6); // the base's market maker
        for (uint256 i = 0; i < 3; i++) {
            address who = [alice, bob, carol][i];
            usdc.mint(who, 1_000_000e6);
            vm.prank(who);
            usdc.approve(address(m), type(uint256).max);
        }
    }

    function setUp() public {
        deploy(cfg(0), 0);
        lp(1000e6, 1000e6);
    }

    // ---------------------------------------------------------------- helpers
    function update() internal {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 61);
        m.poke();
    }

    function updateAt(uint256 xWad) internal {
        feed.set(P0 * xWad / 1e18);
        update();
    }

    function lp(uint256 hearth, uint256 ember) internal {
        if (hearth > 0) {
            vm.prank(bob);
            m.requestDeposit(true, hearth);
        }
        if (ember > 0) {
            vm.prank(carol);
            m.requestDeposit(false, ember);
        }
        update();
    }

    function buy(address who, uint256 usdcIn) internal returns (uint256 tickets) {
        uint256 before = m.balanceOf(who);
        vm.prank(who);
        m.requestBuy(usdcIn, 0);
        update();
        tickets = m.balanceOf(who) - before;
    }

    function sellAll(address who) internal returns (uint256 usd) {
        uint256 before = m.claimable(who);
        uint256 q = m.balanceOf(who);
        vm.prank(who);
        m.requestSell(q, 0);
        update();
        usd = m.claimable(who) - before;
    }

    function assertSolvent() internal view {
        uint256 owed = m.cashH() + m.cashE() + m.protocolFees() + m.endReserve() + m.escrowUsd() + m.claimableTotal();
        assertGe(usdc.balanceOf(address(m)) * 1e12 + 1e13, owed, "market owes more USDC than it holds");
        if (m.status() == AsphodelMarket.Status.LIVE) {
            assertGe(int256(m.cashE()) + 1e9, int256(m.emberNeed(m.totalSupply())), "Ember coverage");
            assertGe(int256(m.cashH()) + 1e9, int256(m.hearthNeed(m.totalSupply(), m.hedgeUnits())), "Hearth coverage");
        }
    }

    // ---------------------------------------------------------------- the spec's worked example
    function test_starts_at_one_dollar_and_pays_two_gains() public {
        uint256 q = buy(alice, 100e6);
        assertApproxEqAbs(q, 100e18, 1e9, "100 tickets at $1");
        assertEq(m.price(), 1e18);
        updateAt(1.1e18); // the stock +10%
        assertApproxEqAbs(m.price(), 1.2e18, 1e9, "ticket $1.20");
        uint256 got = sellAll(alice);
        assertApproxEqAbs(got, 120e18, 1e13, "Alice gets $120");
        // Hearth hedged: its hedge made what it paid. Ember paid its half of the boost.
        assertApproxEqAbs(m.cashH(), 1000e18, 1e13, "Hearth flat");
        assertApproxEqAbs(m.cashE(), 995e18, 1e13, "Ember -$5");
        assertSolvent();
    }

    function test_loss_side() public {
        buy(alice, 100e6);
        updateAt(0.8e18); // -20%
        assertApproxEqAbs(m.price(), 0.6e18, 1e9);
        assertApproxEqAbs(sellAll(alice), 60e18, 1e13, "Alice $60");
        assertApproxEqAbs(m.cashE(), 1010e18, 1e13, "Ember +$10");
        assertApproxEqAbs(m.cashH(), 1000e18, 1e13, "Hearth flat");
        assertSolvent();
    }

    // ---------------------------------------------------------------- fills
    function test_order_fills_at_next_update_not_the_price_it_saw() public {
        vm.roll(block.number + 1);
        vm.prank(alice);
        m.requestBuy(100e6, 0);
        m.poke(); // an update in the same block as the order: too early, nothing fills
        assertEq(m.balanceOf(alice), 0);
        feed.set(P0 * 11 / 10); // the price moves before the next update
        update();
        // filled at $1.20, not the $1.00 Alice saw
        assertApproxEqAbs(m.balanceOf(alice), uint256(100e18) * 1e18 / 1.2e18, 1e9);
    }

    function test_cancel_only_after_max_age() public {
        vm.prank(alice);
        uint256 id = m.requestBuy(100e6, 0);
        vm.roll(block.number + 5);
        vm.prank(alice);
        vm.expectRevert(AsphodelMarket.TooYoung.selector);
        m.cancel(id);
        vm.roll(block.number + 200);
        vm.prank(alice);
        m.cancel(id);
        assertEq(m.claimable(alice), 100e18);
    }

    function test_stale_feed_fills_nothing() public {
        vm.prank(alice);
        m.requestBuy(100e6, 0);
        feed.setOk(false);
        update();
        assertEq(m.balanceOf(alice), 0);
        feed.setOk(true);
        update();
        assertGt(m.balanceOf(alice), 0);
    }

    // ---------------------------------------------------------------- Crown
    function test_crown_needs_two_updates_and_pays_base_plus_max_boost() public {
        buy(alice, 100e6);
        updateAt(2.2e18); // +120%: above the max (+100%), first update
        assertEq(uint256(m.status()), uint256(AsphodelMarket.Status.LIVE));
        assertApproxEqAbs(m.price(), 3.2e18, 1e9, "real token $2.20 + max boost $1");
        update(); // second update, 61 s later
        assertEq(uint256(m.status()), uint256(AsphodelMarket.Status.CROWNED));
        assertApproxEqAbs(m.claimPerTicket(), 3.2e18, 1e11);
        uint256 q = m.balanceOf(alice);
        vm.prank(alice);
        m.redeem(q);
        assertApproxEqAbs(m.claimable(alice), 320e18, 1e13, "Alice $320");
        assertApproxEqAbs(m.cashE(), 950e18, 1e13, "Ember paid its $50 of the $100 max");
        assertApproxEqAbs(m.cashH(), 1010e18, 1e13, "Hearth +$10: its hedge overshot the max");
        assertSolvent();
    }

    function test_one_spike_above_max_does_not_crown() public {
        buy(alice, 100e6);
        updateAt(2.2e18);
        updateAt(1.5e18);
        assertEq(uint256(m.status()), uint256(AsphodelMarket.Status.LIVE));
        assertEq(m.aboveCount(), 0);
    }

    // ---------------------------------------------------------------- stop
    function test_stop_after_two_updates_holder_keeps_quarter() public {
        buy(alice, 100e6);
        updateAt(0.625e18); // -37.5%: ticket $0.25
        assertEq(uint256(m.status()), uint256(AsphodelMarket.Status.LIVE));
        update();
        assertEq(uint256(m.status()), uint256(AsphodelMarket.Status.KNOCKED_OUT));
        assertApproxEqAbs(m.claimPerTicket(), 0.25e18, 1e11, "Alice keeps $25");
        assertApproxEqAbs(m.cashE(), 1018.75e18, 1e13, "Ember +$18.75");
        assertApproxEqAbs(m.cashH(), 1000e18, 1e13, "Hearth flat");
        assertSolvent();
    }

    function test_stop_gap_holder_gets_what_is_left() public {
        buy(alice, 100e6);
        updateAt(0.625e18);
        updateAt(0.55e18); // jumps further before the second update
        assertApproxEqAbs(m.claimPerTicket(), 0.10e18, 1e11, "Alice keeps $10");
        assertApproxEqAbs(m.cashE(), 1022.5e18, 1e13, "Ember +$22.50 (half of $45)");
        assertSolvent();
    }

    function test_one_dip_does_not_stop() public {
        buy(alice, 100e6);
        updateAt(0.6e18);
        updateAt(0.9e18);
        assertEq(uint256(m.status()), uint256(AsphodelMarket.Status.LIVE));
        assertApproxEqAbs(m.price(), 0.8e18, 1e9);
    }

    // ---------------------------------------------------------------- market hours
    function test_weekend_no_new_tickets_no_stop() public {
        buy(alice, 100e6);
        vm.warp(SAT);
        vm.prank(alice);
        m.requestBuy(100e6, 0);
        updateAt(0.6e18); // the weekend perp dumps
        updateAt(0.6e18);
        assertEq(uint256(m.status()), uint256(AsphodelMarket.Status.LIVE), "no stop on a weekend price");
        assertApproxEqAbs(m.claimable(alice), 100e18, 1e13, "weekend buy refunded");
        vm.warp(MON_OPEN);
        updateAt(0.6e18);
        updateAt(0.6e18);
        assertEq(uint256(m.status()), uint256(AsphodelMarket.Status.KNOCKED_OUT), "stop fires on Monday's real prices");
    }

    function test_weekend_sale_uses_hour_average_for_the_boost() public {
        buy(alice, 100e6);
        vm.warp(SAT);
        updateAt(1.0e18);
        updateAt(1.0e18);
        updateAt(1.0e18);
        feed.set(P0 * 13 / 10); // someone pushes the thin weekend perp +30%
        uint256 q = m.balanceOf(alice);
        vm.prank(alice);
        m.requestSell(q, 0);
        update();
        // base sells at the real (pushed) price: $130; the boost uses the hour's average (1.075)
        uint256 got = m.claimable(alice);
        assertLt(got, 160e18, "boost not paid on the pushed price");
        assertApproxEqAbs(got, 137.5e18, 1e13);
        assertSolvent();
    }

    // ---------------------------------------------------------------- LPs
    function test_coverage_full_refuses_buy() public {
        deploy(cfg(0), 0);
        lp(1000e6, 20e6); // Ember can back only 40 tickets ($0.50 each)
        vm.prank(alice);
        m.requestBuy(100e6, 0);
        update();
        assertEq(m.balanceOf(alice), 0);
        assertEq(m.claimable(alice), 100e18);
    }

    function test_hearth_hedge_counts_as_collateral() public {
        AsphodelMarket.Config memory c = cfg(0);
        c.hearthShare = 1e18; // Hearth only
        deploy(c, 0);
        lp(110e6, 0); // $110 backs $100 of 2x tickets: $100 hedge + nothing else
        uint256 q = buy(alice, 100e6);
        assertApproxEqAbs(q, 100e18, 1e9);
        updateAt(2.0e18);
        update();
        assertEq(uint256(m.status()), uint256(AsphodelMarket.Status.CROWNED));
        assertApproxEqAbs(m.claimPerTicket(), 3e18, 1e11);
        assertApproxEqAbs(m.cashH(), 110e18, 1e13, "hedge sold $200, paid $100");
        assertSolvent();
    }

    function test_lp_can_only_take_free_money() public {
        buy(alice, 100e6); // Ember must keep $50 locked
        uint256 sh = m.shares(1, carol);
        vm.prank(carol);
        m.requestWithdraw(false, sh);
        update();
        assertApproxEqAbs(m.claimable(carol), 950e18, 1e13, "only the free $950");
        assertEq(m.pendingOrders(), 1, "the rest waits");
        sellAll(alice); // tickets gone: the rest is free
        update();
        assertApproxEqAbs(m.claimable(carol), 1000e18, 1e13);
        assertSolvent();
    }

    // ---------------------------------------------------------------- fees
    function test_fees_never_make_a_sale_negative() public {
        AsphodelMarket.Config memory c = cfg(0.003e18);
        c.stopPrice = 0; // no cushion, to reach a ticket worth almost nothing
        deploy(c, 0.001e18);
        lp(1000e6, 1000e6);
        buy(alice, 100e6);
        updateAt(0.5001e18); // ticket ~ $0.0002, but the real token inside is ~ $50
        uint256 got = sellAll(alice);
        assertLt(got, 1e17);
        assertSolvent();
    }

    function test_mint_limit_after_big_fall() public {
        buy(alice, 100e6);
        updateAt(0.7e18); // ticket $0.40, live boost 2*0.7/0.4 = 3.5x: allowed
        assertGt(buy(alice, 10e6), 0);
        updateAt(0.66e18); // ticket $0.32, live boost 4.1x: refused
        assertEq(buy(alice, 10e6), 0);
    }

    // ---------------------------------------------------------------- a rough random walk
    function test_random_walk_stays_solvent() public {
        deploy(cfg(0.003e18), 0.001e18);
        lp(20_000e6, 20_000e6);
        uint256 xw = 1e18;
        for (uint256 i = 0; i < 120 && m.status() == AsphodelMarket.Status.LIVE; i++) {
            uint256 r = uint256(keccak256(abi.encode(i)));
            // moves of up to +-6%, with an occasional +-20% jump
            int256 mv = int256(r % 1201) - 600;
            if (r % 17 == 0) mv *= 3;
            xw = uint256(int256(xw) + int256(xw) * mv / 10_000);
            feed.set(P0 * xw / 1e18);
            if (r % 3 == 0) {
                vm.prank(alice);
                m.requestBuy(50e6 + (r % 500e6), 0);
            }
            if (r % 5 == 0 && m.balanceOf(alice) > 0) {
                uint256 q = m.balanceOf(alice) / 3;
                vm.prank(alice);
                m.requestSell(q, 0);
            }
            if (r % 11 == 0) {
                uint256 sh = m.shares(1, carol) / 4;
                if (sh > 0) {
                    vm.prank(carol);
                    m.requestWithdraw(false, sh);
                }
            }
            update();
            assertSolvent();
        }
    }
}
