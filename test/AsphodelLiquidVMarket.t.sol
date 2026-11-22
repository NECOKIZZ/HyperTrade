// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AsphodelLiquidVMarket} from "../contracts/liquidv/AsphodelLiquidVMarket.sol";
import {LiquidVNavFeed} from "../contracts/liquidv/LiquidVNavFeed.sol";
import {ILiquidVVault} from "../contracts/liquidv/ILiquidVVault.sol";
import {IPriceFeed} from "../contracts/interfaces/IPriceFeed.sol";
import {MockUSDC} from "../contracts/mocks/MockUSDC.sol";
import {MockLiquidVVault} from "../contracts/mocks/MockLiquidVVault.sol";

/// Asphodel v0.5 on a LiquidV trader token ($vWHALE). The vault's NAV per share starts at $3.4245
/// (a real vault's on 2026-11-22); the ticket starts at $1.00. Numbers follow the spec's worked example.
contract AsphodelLiquidVMarketTest is Test {
    uint256 constant PPS0 = 3.4245e18;

    MockUSDC usdc;
    MockLiquidVVault vault;
    LiquidVNavFeed feed;
    AsphodelLiquidVMarket m;

    address alice = address(0xA11CE);
    address bob = address(0xB0B); //    Hearth LP
    address carol = address(0xCA201); // Ember LP
    address ben = address(0xBE7); //    second Hearth LP

    function cfg(uint256 fee, uint256 lvFee) internal pure returns (AsphodelLiquidVMarket.Config memory) {
        return AsphodelLiquidVMarket.Config({
            B: 2e18,
            C: 3e18,
            stopPrice: 0.25e18,
            hearthShare: 0.5e18,
            buyFee: fee,
            sellFee: fee,
            lpFeeShare: 0.6e18,
            lvMintFee: lvFee,
            mintBoostLimit: 4e18,
            gapGuardK: 0,
            carryPerSecond: 0,
            confirmUpdates: 2,
            gapWindow: 32,
            maxBatch: 50,
            maxOrderAge: 100
        });
    }

    function deploy(AsphodelLiquidVMarket.Config memory c, uint256 lvMint, uint256 lvExitBps) internal {
        usdc = new MockUSDC();
        vault = new MockLiquidVVault(IERC20(address(usdc)), PPS0, lvMint, lvExitBps);
        feed = new LiquidVNavFeed(ILiquidVVault(address(vault)));
        m = new AsphodelLiquidVMarket("vWHALE 2x", "vWHALE2X", ILiquidVVault(address(vault)), IPriceFeed(address(feed)), c, address(this));
        usdc.mint(address(vault), 10_000_000e6); // pays the trader's gains
        address[4] memory who = [alice, bob, carol, ben];
        for (uint256 i = 0; i < 4; i++) {
            usdc.mint(who[i], 1_000_000e6);
            vm.prank(who[i]);
            usdc.approve(address(m), type(uint256).max);
        }
    }

    function setUp() public {
        deploy(cfg(0, 0), 0, 0);
        lp(1000e6, 1000e6);
    }

    // ---------------------------------------------------------------- helpers
    function update() internal {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 20);
        m.poke();
    }

    function updateAt(uint256 xWad) internal {
        vault.setPps(PPS0 * xWad / 1e18);
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

    function live() internal view returns (bool) {
        return m.status() == AsphodelLiquidVMarket.Status.LIVE;
    }

    function assertSolvent() internal view {
        uint256 owed = m.cashH() + m.cashE() + m.protocolFees() + m.endReserve() + m.escrowUsd() + m.claimableTotal();
        assertGe(usdc.balanceOf(address(m)) * 1e12 + 1e13, owed, "market owes more USDC than it holds");
        assertGe(vault.balanceOf(address(m)), m.baseUnits() + m.hedgeUnits(), "missing $vTRADER");
        if (live()) {
            assertGe(m.cashE() + 1e9, m.emberNeed(m.totalSupply()), "Ember coverage");
            assertGe(m.cashH() + 1e9, m.hearthNeed(m.totalSupply()), "Hearth coverage");
        }
    }

    // ---------------------------------------------------------------- price feed
    function test_feed_reads_live_nav_per_share() public {
        (uint256 p, bool ok) = feed.read();
        assertApproxEqAbs(p, PPS0, 1e12);
        assertTrue(ok);
        vault.setStale(true);
        (, ok) = feed.read();
        assertTrue(ok, "stale only blocks LiquidV deposits; the NAV is still live");
    }

    // ---------------------------------------------------------------- the spec's worked example
    function test_starts_at_one_dollar_and_pays_two_gains() public {
        uint256 q = buy(alice, 100e6);
        assertApproxEqAbs(q, 100e18, 1e12, "100 tickets at $1");
        updateAt(1.1e18); // 0xWhale +10%
        assertApproxEqAbs(m.price(), 1.2e18, 1e12);
        assertApproxEqAbs(sellAll(alice), 120e18, 1e13, "Alice $120");
        assertApproxEqAbs(m.cashH(), 1000e18, 1e13, "Hearth hedged: flat");
        assertApproxEqAbs(m.cashE(), 995e18, 1e13, "Ember paid $5");
        assertSolvent();
    }

    function test_loss_side() public {
        buy(alice, 100e6);
        updateAt(0.8e18);
        assertApproxEqAbs(sellAll(alice), 60e18, 1e13, "Alice $60");
        assertApproxEqAbs(m.cashE(), 1010e18, 1e13, "Ember +$10");
        assertSolvent();
    }

    function test_liquidv_fees_on_own_share_and_hedge_fee() public {
        deploy(cfg(0, 0.01e18), 0.01e18, 30);
        lp(1000e6, 1000e6);
        // $100 buys tickets at $1 + 1% LiquidV fee on her own $1 + hedge fee 0.5 x 1 x 1% = $1.015 each
        uint256 q = buy(alice, 100e6);
        assertApproxEqAbs(q, uint256(100e18) * 1e18 / 1.015e18, 1e12);
        assertSolvent();
    }

    // ---------------------------------------------------------------- fills
    function test_fills_at_next_update_at_live_nav() public {
        vm.roll(block.number + 1);
        vm.prank(alice);
        m.requestBuy(100e6, 0);
        m.poke(); // same block: nothing fills
        assertEq(m.balanceOf(alice), 0);
        vault.setPps(PPS0 * 11 / 10);
        update();
        assertApproxEqAbs(m.balanceOf(alice), uint256(100e18) * 1e18 / 1.2e18, 1e12, "filled at $1.20");
    }

    function test_stale_liquidv_no_new_tickets_but_sales_work() public {
        buy(alice, 50e6);
        vault.setStale(true); // LiquidV's keeper missed its heartbeat: deposits closed, redeems open
        vm.prank(alice);
        m.requestBuy(100e6, 0);
        update();
        assertApproxEqAbs(m.claimable(alice), 100e18, 1e13, "buy refunded");
        assertApproxEqAbs(sellAll(alice), 50e18, 1e13, "but Alice can still sell");
        assertSolvent();
    }

    function test_no_price_nothing_fills() public {
        vm.prank(alice);
        m.requestBuy(100e6, 0);
        vault.setPps(0); // no NAV at all
        update();
        assertEq(m.balanceOf(alice), 0);
        vault.setPps(PPS0);
        update();
        assertGt(m.balanceOf(alice), 0);
    }

    function test_stop_goes_through_liquidv_queue() public {
        buy(alice, 100e6);
        vault.setIdle(5e6); // LiquidV holds only $5 on HyperEVM
        updateAt(0.625e18);
        update(); // stop confirmed: $5 redeemed now, the rest (with Hearth's hedge) queued at LiquidV
        assertEq(uint256(m.status()), uint256(AsphodelLiquidVMarket.Status.ENDING));
        assertTrue(m.queued(), "queued at LiquidV");
        vault.setPps(PPS0 * 6 / 10); // the trader keeps falling while the cash comes back
        vault.setIdle(type(uint256).max); // LiquidV's keeper brings the cash back to HyperEVM
        update(); // our update processes LiquidV's queue and settles
        assertEq(uint256(m.status()), uint256(AsphodelLiquidVMarket.Status.KNOCKED_OUT));
        // base: ~$5 at x 0.625 + the rest at x 0.6: just under $60.4 -> about $0.21 a ticket left
        assertGt(m.claimPerTicket(), 0.20e18);
        assertLt(m.claimPerTicket(), 0.25e18);
        assertEq(m.hedgeUnits(), 0, "Hearth's hedge redeemed too");
        assertSolvent();
    }

    function test_crown_goes_through_liquidv_queue() public {
        buy(alice, 100e6);
        vault.setIdle(0);
        updateAt(2.2e18);
        update();
        assertTrue(m.queued());
        vault.setIdle(type(uint256).max);
        update();
        assertEq(uint256(m.status()), uint256(AsphodelLiquidVMarket.Status.CROWNED));
        assertApproxEqAbs(m.claimPerTicket(), 3.2e18, 1e11);
        assertApproxEqAbs(m.cashH(), 1010e18, 1e13, "hedge paid to Hearth");
        assertSolvent();
    }

    // ---------------------------------------------------------------- Crown and stop
    function test_crown_pays_real_token_plus_max_boost() public {
        buy(alice, 100e6);
        updateAt(2.2e18); // +120%
        assertTrue(live(), "one update isn't enough");
        update();
        assertEq(uint256(m.status()), uint256(AsphodelLiquidVMarket.Status.CROWNED));
        assertApproxEqAbs(m.claimPerTicket(), 3.2e18, 1e11, "$2.20 real + $1 max boost");
        assertApproxEqAbs(m.cashE(), 950e18, 1e13, "Ember paid $50");
        assertApproxEqAbs(m.cashH(), 1010e18, 1e13, "Hearth +$10 (hedge overshoot)");
        uint256 q = m.balanceOf(alice);
        vm.prank(alice);
        m.redeem(q);
        assertApproxEqAbs(m.claimable(alice), 320e18, 1e13);
        assertSolvent();
    }

    function test_stop_keeps_quarter_for_holder() public {
        buy(alice, 100e6);
        updateAt(0.625e18); // -37.5%: ticket $0.25
        assertTrue(live());
        update();
        assertEq(uint256(m.status()), uint256(AsphodelLiquidVMarket.Status.KNOCKED_OUT));
        assertApproxEqAbs(m.claimPerTicket(), 0.25e18, 1e11, "Alice keeps $25");
        assertApproxEqAbs(m.cashE(), 1018.75e18, 1e13, "Ember +$18.75");
        assertApproxEqAbs(m.cashH(), 1000e18, 1e13, "Hearth flat");
        assertSolvent();
    }

    function test_one_dip_does_not_stop() public {
        buy(alice, 100e6);
        updateAt(0.6e18);
        updateAt(0.9e18);
        assertTrue(live());
    }

    function test_stop_waits_for_liquidv_idle_and_settles_on_real_redemption() public {
        buy(alice, 100e6);
        vault.setIdle(0); // LiquidV has no idle cash: nothing can be redeemed instantly
        updateAt(0.625e18);
        update();
        assertEq(uint256(m.status()), uint256(AsphodelLiquidVMarket.Status.ENDING));
        vault.setPps(PPS0 * 6 / 10); // the trader keeps falling while the base waits
        vault.setIdle(type(uint256).max);
        update();
        assertEq(uint256(m.status()), uint256(AsphodelLiquidVMarket.Status.KNOCKED_OUT));
        // base redeemed at $60: 1 + 2(0.6 - 1) = $0.20 left per ticket
        assertApproxEqAbs(m.claimPerTicket(), 0.20e18, 1e11);
        assertSolvent();
    }

    function test_sell_waits_when_liquidv_cannot_redeem() public {
        buy(alice, 100e6);
        vault.setIdle(10e6); // only $10 idle
        uint256 q = m.balanceOf(alice);
        vm.prank(alice);
        m.requestSell(q, 0);
        update();
        assertEq(m.claimable(alice), 0, "waits");
        vault.setIdle(type(uint256).max);
        update();
        assertApproxEqAbs(m.claimable(alice), 100e18, 1e13);
        assertSolvent();
    }

    // ---------------------------------------------------------------- coverage and LPs
    function test_hearth_needs_coverage_and_hedge() public {
        // $100 of 2x/$3 tickets: Hearth needs $50 coverage + $50 hedge
        deploy(cfg(0, 0), 0, 0);
        lp(99e6, 1000e6);
        assertEq(buy(alice, 100e6), 0, "Hearth $99: refused");
        deploy(cfg(0, 0), 0, 0);
        lp(101e6, 1000e6);
        assertGt(buy(alice, 100e6), 0, "Hearth $101: accepted");
        assertSolvent();
    }

    function test_ember_coverage_per_pool() public {
        deploy(cfg(0, 0), 0, 0);
        lp(10_000e6, 20e6); // lots of Hearth money cannot cover Ember's half
        assertEq(buy(alice, 100e6), 0);
    }

    function test_liquidv_full_refuses_buy() public {
        vault.setCap(50e6);
        assertEq(buy(alice, 100e6), 0);
        assertEq(m.claimable(alice), 100e18, "refunded");
    }

    function test_lp_takes_only_free_money_then_the_rest() public {
        buy(alice, 100e6); // Ember keeps $50 locked
        uint256 sh = m.shares(1, carol);
        vm.prank(carol);
        m.requestWithdraw(false, sh);
        update();
        assertApproxEqAbs(m.claimable(carol), 950e18, 1e13, "available now: $950");
        sellAll(alice);
        update();
        assertApproxEqAbs(m.claimable(carol), 1000e18, 1e13);
        assertSolvent();
    }

    function test_mint_limit_after_big_fall() public {
        buy(alice, 100e6);
        updateAt(0.7e18); // ticket $0.40: live boost 3.5x
        assertGt(buy(alice, 10e6), 0);
        updateAt(0.66e18); // ticket $0.32: live boost 4.1x
        assertEq(buy(alice, 10e6), 0);
    }

    function test_gap_guard_after_big_move() public {
        AsphodelLiquidVMarket.Config memory c = cfg(0, 0);
        c.gapGuardK = 1e18;
        deploy(c, 0, 0);
        lp(1000e6, 1000e6);
        updateAt(0.75e18); // a 25% move in one update: price $0.50, stop distance $0.25 < 1 x 2 x 0.75 x 25%
        assertEq(buy(alice, 10e6), 0, "refused by the gap guard");
    }

    // ---------------------------------------------------------------- a rough random walk
    function test_random_walk_with_fees_and_thin_idle_stays_solvent() public {
        deploy(cfg(0.003e18, 0.01e18), 0.01e18, 30);
        lp(20_000e6, 20_000e6);
        uint256 xw = 1e18;
        for (uint256 i = 0; i < 120 && m.status() != AsphodelLiquidVMarket.Status.CROWNED
            && m.status() != AsphodelLiquidVMarket.Status.KNOCKED_OUT; i++) {
            uint256 r = uint256(keccak256(abi.encode("walk", i)));
            int256 mv = int256(r % 1601) - 800; // up to +-8% an update
            if (r % 13 == 0) mv *= 3; //           sometimes +-24%
            xw = uint256(int256(xw) + int256(xw) * mv / 10_000);
            vault.setPps(PPS0 * xw / 1e18);
            vault.setIdle(r % 4 == 0 ? 50e6 : type(uint256).max); // LiquidV sometimes short of idle cash
            if (r % 3 == 0 && live()) {
                vm.prank(alice);
                m.requestBuy(20e6 + (r % 400e6), 0);
            }
            if (r % 5 == 0 && m.balanceOf(alice) > 0 && live()) {
                uint256 q = m.balanceOf(alice) / 3;
                vm.prank(alice);
                m.requestSell(q, 0);
            }
            if (r % 11 == 0 && m.shares(1, carol) > 0) {
                uint256 sh = m.shares(1, carol) / 4;
                vm.prank(carol);
                m.requestWithdraw(false, sh);
            }
            if (r % 17 == 0) {
                vm.prank(ben);
                m.requestDeposit(true, 500e6);
            }
            update();
            assertSolvent();
        }
    }
}
