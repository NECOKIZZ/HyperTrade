// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// Answers precompile calls keyed by their exact input (HyperCore isn't there on a fork).
contract KeyedPrecompile {
    mapping(bytes32 => bytes) internal resp;
    bytes internal dflt;

    function setResp(bytes calldata input, bytes calldata out) external {
        resp[keccak256(input)] = out;
    }

    function setDefault(bytes calldata out) external {
        dflt = out;
    }

    fallback(bytes calldata input) external returns (bytes memory) {
        bytes memory r = resp[keccak256(input)];
        return r.length == 0 ? dflt : r;
    }
}

interface IVault {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function coreAssets() external view returns (uint256);
    function availableIdle() external view returns (uint256);
    function totalQueued() external view returns (uint256);
    function totalReserved() external view returns (uint256);
    function queueLength() external view returns (uint256);
    function queueHead() external view returns (uint256);
    function owedTo(address) external view returns (uint256);
    function stale() external view returns (bool);
    function paused() external view returns (bool);
    function staleAfter() external view returns (uint256);
    function lastHeartbeat() external view returns (uint256);
    function convertToAssets(uint256) external view returns (uint256);
    function previewDeposit(uint256) external view returns (uint256);
    function previewRedeem(uint256) external view returns (uint256);
    function maxDeposit(address) external view returns (uint256);
    function perpDexes() external view returns (uint32[] memory);
    function OPS() external view returns (address);
    function isAgent(address) external view returns (bool);
    function deposit(uint256, address, uint256) external returns (uint256);
    function redeem(uint256, address, address, uint256) external returns (uint256);
}

/// Checks the LiquidV vault interface against the real deployed code (vANSEM's vault), on a fork of
/// HyperEVM. Run: LIQUIDV_FORK=true LIQUIDV_CORE_USD6=<coreAssets now> npx hardhat test solidity test/fork
contract LiquidVVaultForkTest is Test {
    address constant VAULT = 0xC7F1330ffa5644ED14FBD0ff0efa793669bCCe91; // vANSEM
    address constant USDC = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;
    address constant TRADER = 0xB2b7E6563c2EBa9113979AA04aD1b77313701a8c; // Ansem's wallet (traderWallet())
    address constant SPOT_BALANCE = 0x0000000000000000000000000000000000000801;
    address constant MARGIN_SUMMARY = 0x000000000000000000000000000000000000080F;
    address constant BL_RESERVE = 0x0000000000000000000000000000000000000812;

    IVault v = IVault(VAULT);
    address me = address(0xA11CE);
    uint256 core;

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
        setCore(core);
        // the vault caps itself at the trader's own account size: Ansem's main account, $235,585.83
        KeyedPrecompile(MARGIN_SUMMARY).setResp(
            abi.encode(uint32(0), TRADER), abi.encode(int64(235_585_828_844), uint64(0), uint64(0), int64(235_585_828_844))
        );
    }

    /// The vault's trading account on the main perp dex is worth `usd6`.
    function setCore(uint256 usd6) internal {
        KeyedPrecompile(MARGIN_SUMMARY).setResp(
            abi.encode(uint32(0), VAULT), abi.encode(int64(int256(usd6)), uint64(0), uint64(0), int64(int256(usd6)))
        );
    }

    function fund(uint256 amount) internal {
        deal(USDC, me, amount);
        vm.prank(me);
        IERC20(USDC).approve(VAULT, type(uint256).max);
    }

    function test_1_reads() public view {
        console2.log("name", v.name());
        console2.log("symbol", v.symbol());
        console2.log("coreAssets (mocked HyperCore)", v.coreAssets(), "expected", core);
        console2.log("availableIdle", v.availableIdle());
        console2.log("totalAssets", v.totalAssets());
        console2.log("pricePerShare via convertToAssets(1e18)", v.convertToAssets(1e18));
        console2.log("OPS", v.OPS());
        assertApproxEqAbs(v.coreAssets(), core, 1e4, "coreAssets = the HyperCore account value");
    }

    function test_2_deposit_third_argument_is_min_shares() public {
        fund(100e6);
        uint256 preview = v.previewDeposit(10e6);
        vm.prank(me);
        vm.expectRevert();
        v.deposit(10e6, me, preview + 1);
        vm.prank(me);
        uint256 got = v.deposit(10e6, me, preview);
        console2.log("deposit 10 USDC: shares", got, "previewDeposit", preview);
        assertEq(got, preview);
        assertEq(v.balanceOf(me), got);
        // fee: shares are worth this much right after
        console2.log("value of the shares right after (USDC 6dp)", v.convertToAssets(got));
    }

    function test_3_redeem_fourth_argument_is_min_assets() public {
        fund(100e6);
        vm.prank(me);
        uint256 sh = v.deposit(20e6, me, 0);
        uint256 preview = v.previewRedeem(sh);
        vm.prank(me);
        vm.expectRevert();
        v.redeem(sh, me, me, preview + 1);
        uint256 before = IERC20(USDC).balanceOf(me);
        vm.prank(me);
        uint256 got = v.redeem(sh, me, me, preview);
        console2.log("redeem: assets", got, "previewRedeem", preview);
        console2.log("convertToAssets of those shares", v.convertToAssets(sh));
        assertEq(got, preview);
        assertEq(IERC20(USDC).balanceOf(me) - before, got);
    }

    function test_4_instant_redeem_is_capped_by_idle() public {
        fund(1000e6);
        vm.prank(me);
        uint256 sh = v.deposit(500e6, me, 0);
        // the keeper bridges idle cash to HyperCore: move it out of the EVM, add it to the core account
        uint256 idle = IERC20(USDC).balanceOf(VAULT);
        vm.prank(VAULT);
        IERC20(USDC).transfer(address(0xdead), idle - 10e6);
        setCore(core + idle - 10e6);
        console2.log("idle after bridge", v.availableIdle(), "totalAssets", v.totalAssets());
        vm.prank(me);
        vm.expectRevert();
        v.redeem(sh, me, me, 0);
    }

    function test_5_request_redeem_queue() public {
        fund(1000e6);
        vm.prank(me);
        uint256 sh = v.deposit(500e6, me, 0);
        uint256 idle = IERC20(USDC).balanceOf(VAULT);
        vm.prank(VAULT);
        IERC20(USDC).transfer(address(0xdead), idle - 10e6);
        setCore(core + idle - 10e6);
        uint256 qBefore = v.queueLength();
        vm.prank(me);
        (bool ok, bytes memory ret) = VAULT.call(
            abi.encodeWithSignature("requestRedeem(uint256,address,address,uint256)", sh, me, me, 0)
        );
        console2.log("requestRedeem ok", ok);
        console2.logBytes(ret);
        console2.log("queueLength", qBefore, "->", v.queueLength());
        console2.log("my shares after request", v.balanceOf(me), "vault holds its own shares", v.balanceOf(VAULT));
        console2.log("totalQueued", v.totalQueued(), "totalReserved", v.totalReserved());
        (bool ok2, bytes memory r2) = VAULT.staticcall(abi.encodeWithSignature("redemption(uint256)", qBefore));
        console2.log("redemption(id) ok", ok2);
        console2.logBytes(r2);
        // can anyone process the queue?
        (bool ok3, bytes memory r3) = VAULT.call(abi.encodeWithSignature("processRedemptions(uint256)", 10));
        console2.log("processRedemptions by a stranger ok", ok3);
        console2.logBytes(r3);
        // put the cash back on the EVM (the keeper bridging back), then process
        deal(USDC, VAULT, 600e6);
        setCore(core);
        (bool ok4, bytes memory r4) = VAULT.call(abi.encodeWithSignature("processRedemptions(uint256)", 10));
        console2.log("processRedemptions after cash is back ok", ok4);
        console2.logBytes(r4);
        console2.log("owedTo(me)", v.owedTo(me), "queueHead", v.queueHead());
        uint256 before = IERC20(USDC).balanceOf(me);
        (bool ok5, bytes memory r5) = VAULT.call(abi.encodeWithSignature("withdrawOwed(address)", me));
        console2.log("withdrawOwed ok", ok5, "USDC received", IERC20(USDC).balanceOf(me) - before);
        console2.logBytes(r5);
    }

    /// A minimum on a queued exit: what happens if the price falls below it?
    function test_8_queue_min_assets() public {
        fund(1000e6);
        vm.prank(me);
        uint256 sh = v.deposit(500e6, me, 0);
        uint256 idle = IERC20(USDC).balanceOf(VAULT);
        vm.prank(VAULT);
        IERC20(USDC).transfer(address(0xdead), idle - 10e6);
        setCore(core + idle - 10e6);
        uint256 q = v.previewRedeem(sh);
        vm.prank(me);
        (bool ok,) = VAULT.call(abi.encodeWithSignature("requestRedeem(uint256,address,address,uint256)", sh, me, me, q));
        console2.log("request with minAssets = quote ok", ok);
        uint256 total = v.totalAssets();
        deal(USDC, VAULT, 600e6);
        setCore(core + idle - 10e6 - (600e6 - 10e6) - total / 10); // NAV -10%
        uint256 before = IERC20(USDC).balanceOf(me);
        (bool ok2, bytes memory r2) = VAULT.call(abi.encodeWithSignature("processRedemptions(uint256)", 10));
        console2.log("process ok", ok2);
        console2.logBytes(r2);
        console2.log("paid", IERC20(USDC).balanceOf(me) - before, "my shares back", v.balanceOf(me));
        console2.log("queueHead", v.queueHead(), "queueLength", v.queueLength());
    }

    function test_9_mark_stale() public {
        fund(100e6);
        vm.prank(me);
        uint256 sh = v.deposit(20e6, me, 0);
        (bool early,) = VAULT.call(abi.encodeWithSignature("markStale()"));
        console2.log("markStale before staleAfter ok", early);
        vm.warp(v.lastHeartbeat() + v.staleAfter() + 1);
        (bool ok,) = VAULT.call(abi.encodeWithSignature("markStale()"));
        console2.log("markStale after staleAfter ok", ok, "stale()", v.stale());
        console2.log("convertToAssets(1e18) while stale", v.convertToAssets(1e18));
        vm.prank(me);
        (bool okDep, bytes memory rd) = VAULT.call(abi.encodeWithSignature("deposit(uint256,address,uint256)", 10e6, me, 0));
        console2.log("deposit while stale ok", okDep);
        console2.logBytes(rd);
        vm.prank(me);
        (bool okRed, bytes memory rr) = VAULT.call(abi.encodeWithSignature("redeem(uint256,address,address,uint256)", sh, me, me, 0));
        console2.log("redeem while stale ok", okRed);
        console2.logBytes(rr);
    }

    function test_10_paused() public {
        fund(100e6);
        vm.prank(me);
        uint256 sh = v.deposit(20e6, me, 0);
        (, bytes memory g) = VAULT.staticcall(abi.encodeWithSignature("guardian()"));
        address guardian = abi.decode(g, (address));
        vm.prank(guardian);
        (bool okP, bytes memory rp) = VAULT.call(abi.encodeWithSignature("setPaused(bool)", true));
        console2.log("guardian setPaused ok", okP, "paused()", v.paused());
        console2.logBytes(rp);
        console2.log("convertToAssets(1e18) while paused", v.convertToAssets(1e18));
        vm.prank(me);
        (bool okDep,) = VAULT.call(abi.encodeWithSignature("deposit(uint256,address,uint256)", 10e6, me, 0));
        console2.log("deposit while paused ok", okDep);
        vm.prank(me);
        (bool okRed, bytes memory rr) = VAULT.call(abi.encodeWithSignature("redeem(uint256,address,address,uint256)", sh, me, me, 0));
        console2.log("redeem while paused ok", okRed);
        console2.logBytes(rr);
    }

    function test_6_stale_after_heartbeat() public {
        fund(100e6);
        console2.log("staleAfter", v.staleAfter(), "since last heartbeat", block.timestamp - v.lastHeartbeat());
        vm.warp(v.lastHeartbeat() + v.staleAfter() + 1);
        console2.log("stale() after staleAfter", v.stale());
        vm.prank(me);
        (bool okDep,) = VAULT.call(abi.encodeWithSignature("deposit(uint256,address,uint256)", 10e6, me, 0));
        console2.log("deposit while stale ok", okDep);
    }
}
