// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AsphodelLiquidVMarket} from "../../contracts/liquidv/AsphodelLiquidVMarket.sol";
import {LiquidVNavFeed} from "../../contracts/liquidv/LiquidVNavFeed.sol";
import {ILiquidVVault} from "../../contracts/liquidv/ILiquidVVault.sol";
import {IPriceFeed} from "../../contracts/interfaces/IPriceFeed.sol";
import {KeyedPrecompile} from "./LiquidVVault.fork.t.sol";

/// Asphodel v0.5 against the real vANSEM vault code, on a fork of HyperEVM (HyperCore reads stood in
/// for, at their live values). Run: LIQUIDV_FORK=true LIQUIDV_CORE_USD6=<coreAssets now> npx hardhat test solidity test/fork
contract AsphodelOnRealLiquidVForkTest is Test {
    address constant VAULT = 0xC7F1330ffa5644ED14FBD0ff0efa793669bCCe91; // vANSEM
    address constant USDC = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;
    address constant TRADER = 0xB2b7E6563c2EBa9113979AA04aD1b77313701a8c;
    address constant SPOT_BALANCE = 0x0000000000000000000000000000000000000801;
    address constant MARGIN_SUMMARY = 0x000000000000000000000000000000000000080F;
    address constant BL_RESERVE = 0x0000000000000000000000000000000000000812;

    ILiquidVVault v = ILiquidVVault(VAULT);
    AsphodelLiquidVMarket m;
    uint256 core;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA201);

    function setUp() public {
        if (!vm.envOr("LIQUIDV_FORK", false)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("hyperevm");
        core = vm.envUint("LIQUIDV_CORE_USD6");
        KeyedPrecompile impl = new KeyedPrecompile();
        vm.etch(SPOT_BALANCE, address(impl).code);
        vm.etch(MARGIN_SUMMARY, address(impl).code);
        vm.etch(BL_RESERVE, address(impl).code);
        KeyedPrecompile(SPOT_BALANCE).setDefault(abi.encode(uint64(0), uint64(0), uint64(0)));
        KeyedPrecompile(BL_RESERVE).setDefault(abi.encode(uint64(0), uint64(0), uint64(0), uint64(0), uint64(0), uint64(0), uint64(0), uint64(0)));
        KeyedPrecompile(MARGIN_SUMMARY).setDefault(abi.encode(int64(0), uint64(0), uint64(0), int64(0)));
        KeyedPrecompile(MARGIN_SUMMARY).setResp(
            abi.encode(uint32(0), TRADER), abi.encode(int64(235_585_828_844), uint64(0), uint64(0), int64(235_585_828_844))
        );
        setCore(core);

        AsphodelLiquidVMarket.Config memory c = AsphodelLiquidVMarket.Config({
            B: 2e18, C: 3e18, stopPrice: 0.25e18, hearthShare: 0.5e18, buyFee: 0.003e18, sellFee: 0.003e18,
            lpFeeShare: 0.6e18, lvMintFee: 0.01e18, mintBoostLimit: 4e18, gapGuardK: 0, carryPerSecond: 0,
            confirmUpdates: 2, gapWindow: 32, maxBatch: 20, maxOrderAge: 100
        });
        LiquidVNavFeed feed = new LiquidVNavFeed(v);
        m = new AsphodelLiquidVMarket("vANSEM 2x", "vANSEM2X", v, IPriceFeed(address(feed)), c, address(this));
        address[3] memory who = [alice, bob, carol];
        for (uint256 i = 0; i < 3; i++) {
            deal(USDC, who[i], 10_000e6);
            vm.prank(who[i]);
            IERC20(USDC).approve(address(m), type(uint256).max);
        }
        vm.prank(bob);
        m.requestDeposit(true, 1000e6);
        vm.prank(carol);
        m.requestDeposit(false, 1000e6);
        update();
    }

    function setCore(uint256 usd6) internal {
        KeyedPrecompile(MARGIN_SUMMARY).setResp(
            abi.encode(uint32(0), VAULT), abi.encode(int64(int256(usd6)), uint64(0), uint64(0), int64(int256(usd6)))
        );
    }

    function update() internal {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 2);
        m.poke();
    }

    /// Ansem's vault moves by `bps` of its value (on HyperCore).
    function moveVault(int256 bps) internal {
        int256 total = int256(v.totalAssets());
        core = uint256(int256(core) + total * bps / 10_000);
        setCore(core);
    }

    function test_real_vault_buy_rise_sell() public {
        vm.prank(alice);
        m.requestBuy(100e6, 0);
        update();
        uint256 q = m.balanceOf(alice);
        console2.log("tickets for $100 (1% LiquidV fee + hedge fee + 0.3% fee)", q);
        assertGt(m.baseUnits(), 0, "holds real vANSEM");
        assertEq(v.balanceOf(address(m)), m.baseUnits() + m.hedgeUnits(), "the market holds the real shares");
        moveVault(1000); // Ansem +10%
        update();
        console2.log("ticket price after +10% (x1e18)", m.price());
        vm.prank(alice);
        m.requestSell(q, 0);
        update();
        console2.log("Alice gets (USD x1e18)", m.claimable(alice));
        assertGt(m.claimable(alice), 115e18);
        assertLt(m.claimable(alice), 120e18);
        vm.prank(alice);
        m.claim();
        console2.log("USDC in Alice's wallet", IERC20(USDC).balanceOf(alice));
    }

    function test_real_vault_stop_through_liquidv_queue() public {
        vm.prank(alice);
        m.requestBuy(100e6, 0);
        update();
        // LiquidV's keeper moves its idle cash to HyperCore (keeps $2 on HyperEVM)
        uint256 idle = IERC20(USDC).balanceOf(VAULT);
        vm.prank(VAULT);
        IERC20(USDC).transfer(address(0xdead), idle - 2e6);
        setCore(core + idle - 2e6);
        core = core + idle - 2e6;
        moveVault(-3800); // Ansem -38%: ticket below $0.25
        update();
        update();
        console2.log("status (1 = ENDING)", uint256(m.status()), "queued at LiquidV", m.queued());
        assertTrue(m.queued(), "rest of the base queued at the real vault");
        // the keeper brings cash back to HyperEVM
        deal(USDC, VAULT, IERC20(USDC).balanceOf(VAULT) + 150e6);
        core = core - 150e6;
        setCore(core);
        update();
        console2.log("status (3 = KNOCKED_OUT)", uint256(m.status()), "claim per ticket", m.claimPerTicket());
        assertEq(uint256(m.status()), uint256(AsphodelLiquidVMarket.Status.KNOCKED_OUT));
        assertEq(v.balanceOf(address(m)), 0, "all real shares redeemed");
    }
}
