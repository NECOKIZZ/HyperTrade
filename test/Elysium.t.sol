// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AsphodelLiquidVMarket} from "../contracts/liquidv/AsphodelLiquidVMarket.sol";
import {LiquidVNavFeed} from "../contracts/liquidv/LiquidVNavFeed.sol";
import {ILiquidVVault} from "../contracts/liquidv/ILiquidVVault.sol";
import {IPriceFeed} from "../contracts/interfaces/IPriceFeed.sol";
import {MirrorVault} from "../contracts/elysium/MirrorVault.sol";
import {HyperCoreNavFeed} from "../contracts/elysium/HyperCoreNavFeed.sol";
import {HyperEvmCoreReader} from "../contracts/elysium/HyperEvmCoreReader.sol";
import {IHyperCoreReader} from "../contracts/elysium/IHyperCoreReader.sol";
import {MockUSDC} from "../contracts/mocks/MockUSDC.sol";
import {MockCoreReader, MockMarginSummary} from "../contracts/mocks/MockCoreReader.sol";

/// The Elysium build: a Series on the MirrorVault (testnet stand-in that follows a real LiquidV vault),
/// and the precompile slot (HyperCoreNavFeed) with LiquidV's NAV formula.
contract ElysiumTest is Test {
    // vANSEM on HyperEVM, read 2026-11-25: $3.838341 per share, $702.38 in the vault, 182.99 shares
    uint256 constant PPS0 = 3.838341e18;
    address constant VANSEM = 0xC7F1330ffa5644ED14FBD0ff0efa793669bCCe91;
    address constant ANSEM = 0xB2b7E6563c2EBa9113979AA04aD1b77313701a8c;

    MockUSDC usdc;
    MirrorVault vault;
    AsphodelLiquidVMarket m;
    address keeper = address(0x4EE9E4);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA201);

    function setUp() public {
        vm.warp(1_800_000_000);
        usdc = new MockUSDC();
        vault = new MirrorVault(
            IERC20(address(usdc)), "LiquidV vANSEM (testnet mirror)", "vANSEM", VANSEM, 999, ANSEM, PPS0, 0.01e18, 30, 120, keeper
        );
        usdc.mint(address(vault), 1_000_000e6); // pays the trader's gains on testnet
        LiquidVNavFeed feed = new LiquidVNavFeed(ILiquidVVault(address(vault)));
        m = new AsphodelLiquidVMarket(
            "vANSEM 2x", "vANSEM2X", ILiquidVVault(address(vault)), IPriceFeed(address(feed)), cfg(), address(this)
        );
        address[3] memory who = [alice, bob, carol];
        for (uint256 i = 0; i < 3; i++) {
            usdc.mint(who[i], 100_000e6);
            vm.prank(who[i]);
            usdc.approve(address(m), type(uint256).max);
        }
        vm.prank(bob);
        m.requestDeposit(true, 5_000e6);
        vm.prank(carol);
        m.requestDeposit(false, 5_000e6);
        relayAndUpdate(PPS0);
    }

    function cfg() internal pure returns (AsphodelLiquidVMarket.Config memory) {
        return AsphodelLiquidVMarket.Config({
            B: 2e18,
            C: 3e18,
            stopPrice: 0.25e18,
            hearthShare: 0.5e18,
            buyFee: 0.003e18,
            sellFee: 0.003e18,
            lpFeeShare: 0.6e18,
            lvMintFee: 0.01e18,
            mintBoostLimit: 4e18,
            gapGuardK: 1e18,
            carryPerSecond: 0,
            confirmUpdates: 2,
            gapWindow: 32,
            maxBatch: 50,
            maxOrderAge: 100
        });
    }

    function relayAndUpdate(uint256 pps) internal {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 2);
        vm.prank(keeper);
        vault.relay(pps, false, false, type(uint256).max);
        m.poke();
    }

    // ---------------------------------------------------------------- mirror vault
    function test_only_the_keeper_relays() public {
        vm.expectRevert(MirrorVault.NotKeeper.selector);
        vault.relay(PPS0 * 2, false, false, 0);
    }

    function test_ticket_follows_the_relayed_real_vault() public {
        vm.prank(alice);
        m.requestBuy(100e6, 0);
        relayAndUpdate(PPS0);
        uint256 t = m.balanceOf(alice);
        assertGt(t, 97e18, "about 98 tickets for $100 after LiquidV's 1% and our 0.3%");
        relayAndUpdate(PPS0 * 110 / 100); // Ansem +10%
        assertApproxEqAbs(m.price(), 1.2e18, 1e12, "ticket $1.20");
        vm.prank(alice);
        m.requestSell(t, 0);
        relayAndUpdate(PPS0 * 110 / 100);
        vm.prank(alice);
        uint256 out = m.claim();
        assertGt(out, 115e6, "about $117 after fees, like the fork test on the real vault");
    }

    function test_old_relay_means_no_price_nothing_fills() public {
        vm.prank(alice);
        m.requestBuy(100e6, 0);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 121); // the keeper stopped: the relay is older than 120 s
        assertFalse(vault.activated());
        m.poke();
        assertEq(m.balanceOf(alice), 0, "no fill on an old number");
        relayAndUpdate(PPS0); // keeper back
        assertGt(m.balanceOf(alice), 0, "fills once the relay is fresh");
    }

    function test_real_vault_stale_refuses_tickets_but_sales_work() public {
        vm.prank(alice);
        m.requestBuy(100e6, 0);
        relayAndUpdate(PPS0);
        uint256 t = m.balanceOf(alice);
        vm.prank(alice);
        m.requestBuy(100e6, 0);
        vm.prank(alice);
        m.requestSell(t, 0);
        vm.roll(block.number + 1);
        vm.prank(keeper);
        vault.relay(PPS0, true, false, type(uint256).max); // the real vANSEM went stale
        m.poke();
        assertEq(m.balanceOf(alice), 0, "the sale went through, the new buy was refused");
        assertGt(m.claimable(alice), 0);
    }

    // ---------------------------------------------------------------- the precompile slot
    function test_core_nav_feed_uses_liquidv_formula() public {
        MockCoreReader r = new MockCoreReader();
        uint32[] memory dexes = new uint32[](2);
        dexes[1] = 1; // main dex and xyz
        HyperCoreNavFeed f = new HyperCoreNavFeed(IHyperCoreReader(address(r)), VANSEM, dexes, 2, 3600, keeper);
        // vANSEM read live 2026-11-25: availableIdle $86.923504 + coreAssets $611.627798 (= Hyperliquid's
        // own account value for the vault, to the cent) = totalAssets $698.551302 over 183.0663 shares;
        // the vault's own convertToAssets(1e18) was $3.815838.
        vm.prank(keeper);
        f.setBook(86_923_504, 183066284387582647796);
        r.set(611_627_798, uint64(block.timestamp));
        (uint256 p, bool ok) = f.read();
        assertTrue(ok);
        assertApproxEqAbs(p, 3.815838e18, 1e12, "matches the vault's own convertToAssets");
    }

    function test_core_nav_feed_fails_visibly_when_old() public {
        MockCoreReader r = new MockCoreReader();
        HyperCoreNavFeed f = new HyperCoreNavFeed(IHyperCoreReader(address(r)), VANSEM, new uint32[](1), 2, 3600, keeper);
        vm.prank(keeper);
        f.setBook(100e6, 100e18);
        r.set(100e6, uint64(block.timestamp - 3)); // a core read 3 s old, limit 2 s
        (, bool ok) = f.read();
        assertFalse(ok, "old core read");
        r.set(100e6, uint64(block.timestamp));
        (, ok) = f.read();
        assertTrue(ok);
        vm.warp(block.timestamp + 3601);
        r.set(100e6, uint64(block.timestamp));
        (, ok) = f.read();
        assertFalse(ok, "old book (idle and supply)");
    }

    function test_hyperevm_reader_sums_dexes() public {
        MockMarginSummary ms = new MockMarginSummary();
        vm.etch(0x000000000000000000000000000000000000080F, address(ms).code);
        MockMarginSummary(0x000000000000000000000000000000000000080F).set(0, VANSEM, 586_200_659);
        MockMarginSummary(0x000000000000000000000000000000000000080F).set(1, VANSEM, 13_799_341);
        uint32[] memory dexes = new uint32[](2);
        dexes[1] = 1;
        (int256 v,) = new HyperEvmCoreReader().accountValue(VANSEM, dexes);
        assertEq(v, 600e6);
    }
}
