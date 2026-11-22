// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPriceFeed} from "../interfaces/IPriceFeed.sol";
import {ILiquidVVault} from "./ILiquidVVault.sol";

/// @notice Receives LiquidV's queued redemption payments for one market, so they can be told apart.
contract RedemptionReceiver {
    using SafeERC20 for IERC20;

    address public immutable market;
    IERC20 public immutable usdc;

    constructor(IERC20 usdc_) {
        market = msg.sender;
        usdc = usdc_;
    }

    function sweep() external returns (uint256 amount) {
        require(msg.sender == market, "only market");
        amount = usdc.balanceOf(address(this));
        usdc.safeTransfer(market, amount);
    }
}

/// @title Asphodel v0.5: a boosted LiquidV trader token (one Series).
/// @notice Spec: ASPHODEL-SPEC-v0.5.md. A buyer's money buys the real LiquidV trader token
/// (`$vTRADER`, the vault's share). The Meadow (Hearth + Ember) backs the boost: an extra (B - 1) x the
/// token's move since launch, capped at MAXB per ticket.
///
///   x      = $vTRADER NAV now / NAV at launch        (one common zero: this Series' launch)
///   boost  = (B - 1)(x - 1), capped at MAXB           MAXB = (B - 1)(C - 1) / B
///   price  = max(0, x + boost) x carry                = 1 + B(x - 1) up to the max; starts at $1.00
///
/// Stop-loss: price <= $0.25 on 2 updates in a row -> the base is redeemed; holders get what's left at
///   the real redemption price, the Meadow the rest.
/// Crown: x >= xc on 2 updates in a row -> the Meadow pays exactly MAXB; holders get the base's real
///   redemption proceeds + MAXB.
/// LiquidV only redeems instantly up to its idle cash. A stop or Crown first redeems what it can
///   instantly, then puts the rest (with Hearth's hedge) in LiquidV's redemption queue and processes the
///   queue on every update (status ENDING); it settles on what the base actually redeemed for.
/// When LiquidV is stale or paused, new tickets are refused; sales, stops and Crowns go on (LiquidV still
///   redeems then, and the NAV is still live).
/// Coverage per pool, after the hedge is paid for: Ember holds (1 - h) x supply x MAXB in cash; Hearth
///   holds h x supply x MAXB in cash AND its hedge (h x (B - 1) units of base per ticket).
/// Orders fill at the next update after the block they were placed in, at the vault's live NAV.
contract AsphodelLiquidVMarket is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant USDC_TO_WAD = 1e12;
    uint256 internal constant WINDOW = 32;

    enum Status {
        LIVE,
        ENDING,
        CROWNED,
        KNOCKED_OUT
    }

    enum Kind {
        BUY,
        SELL,
        DEPOSIT_HEARTH,
        DEPOSIT_EMBER,
        WITHDRAW_HEARTH,
        WITHDRAW_EMBER
    }

    struct Config {
        uint256 B; //               boost, WAD (2e18 = 2x)
        uint256 C; //               max ticket price, WAD (3e18)
        uint256 stopPrice; //       WAD (0.25e18)
        uint256 hearthShare; //     Hearth's fixed share of every ticket's boost, WAD
        uint256 buyFee; //          WAD (0.003e18)
        uint256 sellFee; //         WAD
        uint256 lpFeeShare; //      share of buy/sell fees to LPs, WAD (0.6e18)
        uint256 lvMintFee; //       LiquidV's mint fee, WAD (0.01e18)
        uint256 mintBoostLimit; //  refuse mints when B*x/price > this, WAD (4e18)
        uint256 gapGuardK; //       refuse mints if price - stop < k*B*x*biggest recent move, WAD (1e18; 0 = off)
        uint256 carryPerSecond; //  WAD per second (0 = off)
        uint32 confirmUpdates; //   2
        uint32 gapWindow; //        updates of history for the gap guard (<= 32)
        uint32 maxBatch; //         orders settled per update
        uint32 maxOrderAge; //      blocks before an unsettled order expires
    }

    struct Order {
        address user;
        Kind kind;
        bool done;
        uint64 placed; //  block placed (expiry counts from here)
        uint64 ready; //   first block it may settle in
        uint256 amount; // BUY/DEPOSIT: USDC (6 dp); SELL: tickets; WITHDRAW: pool shares
        uint256 minOut; // BUY: min tickets; SELL: min USDC (6 dp)
    }

    IERC20 public immutable usdc;
    ILiquidVVault public immutable vault;
    IPriceFeed public immutable feed;
    RedemptionReceiver public immutable receiver;
    uint256 public immutable nav0;
    uint256 public immutable launchTime;
    uint256 public immutable xCrown;
    uint256 public immutable maxBoost;
    Config internal cfg;

    Status public status;
    bool public endIsCrown;
    uint256 public nav;
    uint256 public lastPokeBlock;
    uint256 public baseUnits; //    holders' $vTRADER shares
    uint256 public hedgeUnits; //   Hearth's $vTRADER shares
    uint256 public cashH;
    uint256 public cashE;
    uint256 public protocolFees;
    uint256 public endProceeds; //  base redeemed so far while ENDING, USD WAD
    bool public queued; //          a LiquidV redemption request is waiting
    uint256 public queueId;
    uint256 public queuedBase; //   shares of base in that request
    uint256 public queuedHedge; //  shares of Hearth's hedge in that request
    uint256 public endReserve;
    uint256 public claimPerTicket;
    uint256 public escrowUsd;
    uint256 public claimableTotal;
    mapping(address => uint256) public claimable;

    uint32 public aboveCount;
    uint32 public belowCount;
    uint256 internal moveCount;
    uint256[WINDOW] internal moves;

    Order[] public orders;
    uint256 public head;
    mapping(uint256 => mapping(address => uint256)) public shares;
    uint256[2] public totalShares;

    event OrderPlaced(uint256 indexed id, address indexed user, Kind kind, uint256 amount);
    event OrderSettled(uint256 indexed id, address indexed user, Kind kind, uint256 amountIn, uint256 amountOut);
    event OrderRefused(uint256 indexed id, address indexed user, Kind kind, bytes32 reason);
    event Poked(uint256 nav, bool fresh);
    event Ending(bool crown, uint256 x);
    event Crowned(uint256 proceeds, uint256 claimPerTicket);
    event KnockedOut(uint256 proceeds, uint256 claimPerTicket);
    event Redeemed(address indexed user, uint256 tickets, uint256 usd);

    error BadConfig();
    error BadPrice();
    error AlreadyPoked();
    error NotLive();
    error NotEnded();
    error NotYours();
    error TooYoung();
    error Zero();

    constructor(
        string memory name_,
        string memory symbol_,
        ILiquidVVault vault_,
        IPriceFeed feed_,
        Config memory cfg_,
        address owner_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        if (
            cfg_.B <= WAD || cfg_.C <= WAD || cfg_.stopPrice >= WAD || cfg_.hearthShare > WAD
                || cfg_.lpFeeShare > WAD || cfg_.confirmUpdates == 0 || cfg_.gapWindow > WINDOW || cfg_.maxBatch == 0
                || cfg_.maxOrderAge == 0
        ) revert BadConfig();
        vault = vault_;
        usdc = IERC20(vault_.asset());
        feed = feed_;
        cfg = cfg_;
        (uint256 p, bool ok) = feed_.read();
        if (!ok || p == 0) revert BadPrice();
        nav0 = p;
        nav = p;
        launchTime = block.timestamp;
        xCrown = WAD + Math.mulDiv(cfg_.C - WAD, WAD, cfg_.B);
        maxBoost = _mul(cfg_.B - WAD, xCrown - WAD);
        usdc.forceApprove(address(vault_), type(uint256).max);
        receiver = new RedemptionReceiver(usdc);
    }

    // ================================================================ views
    function config() external view returns (Config memory) {
        return cfg;
    }

    function x() public view returns (uint256) {
        return Math.mulDiv(nav, WAD, nav0);
    }

    function priceAt(uint256 xx) public view returns (uint256) {
        int256 boost = int256(_mul(cfg.B - WAD, xx)) - int256(cfg.B - WAD);
        if (boost > int256(maxBoost)) boost = int256(maxBoost);
        int256 v = int256(xx) + boost;
        if (v <= 0) return 0;
        return _mul(uint256(v), carryFactor());
    }

    function price() public view returns (uint256) {
        if (status == Status.CROWNED || status == Status.KNOCKED_OUT) return claimPerTicket;
        return priceAt(x());
    }

    function carryFactor() public view returns (uint256) {
        uint256 lost = cfg.carryPerSecond * (block.timestamp - launchTime);
        return lost >= WAD ? 0 : WAD - lost;
    }

    function effectiveBoost() public view returns (uint256) {
        uint256 pr = priceAt(x());
        if (pr == 0) return type(uint256).max;
        return Math.mulDiv(_mul(cfg.B, x()), WAD, pr);
    }

    function liability() public view returns (int256) {
        uint256 S = totalSupply();
        if (status == Status.LIVE) {
            uint256 xx = x();
            return _smul(int256(priceAt(xx)) - int256(xx), S);
        }
        if (status == Status.ENDING) {
            return endIsCrown ? int256(_mul(_mul(S, maxBoost), carryFactor())) : int256(0);
        }
        return 0;
    }

    function coverageNeeded(uint256 supply) public view returns (uint256) {
        return (status == Status.LIVE || status == Status.ENDING) ? _mul(supply, maxBoost) : 0;
    }

    function hearthNeed(uint256 supply) public view returns (uint256) {
        return _mul(cfg.hearthShare, coverageNeeded(supply));
    }

    function emberNeed(uint256 supply) public view returns (uint256) {
        return _mul(WAD - cfg.hearthShare, coverageNeeded(supply));
    }

    function hedgeTarget(uint256 supply) public view returns (uint256) {
        if (status != Status.LIVE) return 0;
        return Math.mulDiv(_mul(_mul(cfg.hearthShare, supply), cfg.B - WAD), WAD, nav0);
    }

    function exitFee() public view returns (uint256) {
        return vault.exitFeeBps() * 1e14; // bps -> WAD
    }

    function equity(uint256 pool) public view returns (int256) {
        int256 liab = liability();
        if (pool == 0) {
            uint256 hedgeVal = _mul(_mul(hedgeUnits, nav), WAD - exitFee());
            return int256(cashH + hedgeVal) - _smul(liab, cfg.hearthShare);
        }
        return int256(cashE) - _smul(liab, WAD - cfg.hearthShare);
    }

    function free(uint256 pool) public view returns (int256) {
        if (pool == 0) return int256(cashH) - int256(hearthNeed(totalSupply()));
        return int256(cashE) - int256(emberNeed(totalSupply()));
    }

    function lpValue(uint256 pool, address who) external view returns (int256) {
        uint256 ts = totalShares[pool];
        if (ts == 0) return 0;
        return equity(pool) * int256(shares[pool][who]) / int256(ts);
    }

    function pendingOrders() external view returns (uint256) {
        return orders.length - head;
    }

    function biggestMove() public view returns (uint256 m) {
        uint256 n = moveCount < cfg.gapWindow ? moveCount : cfg.gapWindow;
        for (uint256 i = 0; i < n; i++) {
            uint256 v = moves[(moveCount - 1 - i) % WINDOW];
            if (v > m) m = v;
        }
    }

    // ================================================================ orders
    function requestBuy(uint256 usdcIn, uint256 minTickets) external nonReentrant returns (uint256) {
        if (status != Status.LIVE) revert NotLive();
        if (usdcIn == 0) revert Zero();
        usdc.safeTransferFrom(msg.sender, address(this), usdcIn);
        escrowUsd += usdcIn * USDC_TO_WAD;
        return _place(Kind.BUY, usdcIn, minTickets);
    }

    function requestSell(uint256 tickets, uint256 minUsdc) external nonReentrant returns (uint256) {
        if (tickets == 0) revert Zero();
        if (status == Status.CROWNED || status == Status.KNOCKED_OUT) revert NotLive(); // use redeem()
        _transfer(msg.sender, address(this), tickets);
        return _place(Kind.SELL, tickets, minUsdc);
    }

    function requestDeposit(bool hearth, uint256 usdcIn) external nonReentrant returns (uint256) {
        if (usdcIn == 0) revert Zero();
        usdc.safeTransferFrom(msg.sender, address(this), usdcIn);
        escrowUsd += usdcIn * USDC_TO_WAD;
        return _place(hearth ? Kind.DEPOSIT_HEARTH : Kind.DEPOSIT_EMBER, usdcIn, 0);
    }

    function requestWithdraw(bool hearth, uint256 poolShares) external nonReentrant returns (uint256) {
        uint256 pool = hearth ? 0 : 1;
        if (poolShares == 0 || poolShares > shares[pool][msg.sender]) revert Zero();
        shares[pool][msg.sender] -= poolShares;
        return _place(hearth ? Kind.WITHDRAW_HEARTH : Kind.WITHDRAW_EMBER, poolShares, 0);
    }

    function cancel(uint256 id) external nonReentrant {
        Order storage o = orders[id];
        if (o.user != msg.sender) revert NotYours();
        if (o.done) revert Zero();
        if (block.number <= o.placed + cfg.maxOrderAge) revert TooYoung();
        _refund(id, o, "cancelled");
    }

    function redeem(uint256 tickets) external nonReentrant returns (uint256 usdOut) {
        if (status != Status.CROWNED && status != Status.KNOCKED_OUT) revert NotEnded();
        _burn(msg.sender, tickets);
        usdOut = _payClaim(msg.sender, tickets);
        emit Redeemed(msg.sender, tickets, usdOut);
    }

    function claim() external nonReentrant returns (uint256 amount) {
        uint256 wad = claimable[msg.sender];
        amount = wad / USDC_TO_WAD;
        uint256 used = amount * USDC_TO_WAD;
        claimable[msg.sender] = wad - used;
        claimableTotal -= used;
        usdc.safeTransfer(msg.sender, amount);
    }

    function collectFees(address to) external onlyOwner {
        uint256 amount = protocolFees / USDC_TO_WAD;
        protocolFees -= amount * USDC_TO_WAD;
        usdc.safeTransfer(to, amount);
    }

    // ================================================================ the update
    function poke() external nonReentrant {
        if (block.number <= lastPokeBlock) revert AlreadyPoked();
        lastPokeBlock = block.number;
        (uint256 p, bool ok) = feed.read();
        emit Poked(p, ok && p > 0);
        if (!ok || p == 0) return; // stale vault: nothing fills, nothing triggers
        uint256 d = p > nav ? p - nav : nav - p;
        moves[moveCount % WINDOW] = Math.mulDiv(d, WAD, nav);
        moveCount++;
        nav = p;
        if (status == Status.LIVE) _checkTriggers();
        if (status == Status.LIVE) _trimHedge();
        if (status == Status.ENDING) _progressEnding();
        if (status == Status.CROWNED || status == Status.KNOCKED_OUT) _redeemHedge();
        _settleOrders();
    }

    function _checkTriggers() internal {
        uint256 xx = x();
        aboveCount = xx >= xCrown ? aboveCount + 1 : 0;
        belowCount = priceAt(xx) <= cfg.stopPrice ? belowCount + 1 : 0;
        if (aboveCount >= cfg.confirmUpdates) _startEnding(true);
        else if (belowCount >= cfg.confirmUpdates) _startEnding(false);
    }

    function _startEnding(bool crown) internal {
        status = Status.ENDING;
        endIsCrown = crown;
        emit Ending(crown, x());
    }

    /// Redeem what LiquidV can pay now; queue the rest (with Hearth's hedge, so both get one price).
    function _progressEnding() internal {
        if (queued) return _pollQueue();
        if (baseUnits > 0) {
            uint256 units = _redeemableUnits(baseUnits);
            if (units > 0) {
                baseUnits -= units;
                endProceeds += _redeemUnits(units);
            }
        }
        if (baseUnits == 0) return _finish();
        uint256 b = baseUnits;
        uint256 hg = hedgeUnits;
        (bool ok, bytes memory ret) = address(vault).call(
            abi.encodeCall(ILiquidVVault.requestRedeem, (b + hg, address(receiver), address(this), 0))
        );
        if (!ok || ret.length < 64) return; // try again next update
        (queueId,) = abi.decode(ret, (uint256, uint256));
        queued = true;
        queuedBase = b;
        queuedHedge = hg;
        baseUnits = 0;
        hedgeUnits = 0;
        _pollQueue();
    }

    function _pollQueue() internal {
        // anyone may process LiquidV's queue; do it on every update while we wait
        (bool ok,) = address(vault).call(abi.encodeCall(ILiquidVVault.processRedemptions, (uint256(cfg.maxBatch))));
        ok;
        if (vault.queueHead() <= queueId) return;
        uint256 paid = receiver.sweep() * USDC_TO_WAD;
        uint256 baseShare = Math.mulDiv(paid, queuedBase, queuedBase + queuedHedge);
        endProceeds += baseShare;
        cashH += paid - baseShare; // the hedge is Hearth's
        queued = false;
        queuedBase = 0;
        queuedHedge = 0;
        _finish();
    }

    function _finish() internal {
        uint256 S = totalSupply();
        uint256 P = endProceeds;
        uint256 owed;
        if (endIsCrown) {
            owed = _mul(P + _mul(S, maxBoost), carryFactor()); // the Meadow pays exactly MAXB
            status = Status.CROWNED;
        } else {
            // what's left for holders at the price the base really redeemed for
            uint256 per = S > 0 ? priceAt(Math.mulDiv(P, WAD, S)) : 0;
            owed = _mul(S, per);
            if (owed > P) owed = P;
            status = Status.KNOCKED_OUT;
        }
        _toPools(int256(P) - int256(owed));
        endReserve = owed;
        claimPerTicket = S > 0 ? Math.mulDiv(owed, WAD, S) : 0;
        if (endIsCrown) emit Crowned(P, claimPerTicket);
        else emit KnockedOut(P, claimPerTicket);
        _redeemHedge();
    }

    /// Hedge left over from sales LiquidV couldn't redeem at the time.
    function _trimHedge() internal {
        uint256 target = hedgeTarget(totalSupply());
        if (hedgeUnits <= target) return;
        uint256 u = _redeemableUnits(hedgeUnits - target);
        if (u == 0) return;
        hedgeUnits -= u;
        cashH += _redeemUnits(u);
    }

    function _redeemHedge() internal {
        if (hedgeUnits == 0) return;
        uint256 units = _redeemableUnits(hedgeUnits);
        if (units == 0) return;
        hedgeUnits -= units;
        cashH += _redeemUnits(units);
    }

    function _settleOrders() internal {
        uint256 n;
        uint256 end = orders.length; // orders re-queued during this update wait for the next
        while (head < end && n < cfg.maxBatch) {
            Order storage o = orders[head];
            if (o.ready > block.number) break;
            uint256 id = head;
            head++;
            if (o.done) continue;
            n++;
            if (block.number > o.placed + cfg.maxOrderAge) {
                _refund(id, o, "expired");
                continue;
            }
            if (o.kind == Kind.BUY) _settleBuy(id, o);
            else if (o.kind == Kind.SELL) _settleSell(id, o);
            else if (status == Status.ENDING) _requeue(o); // LP moves wait until the Series settles
            else if (o.kind == Kind.DEPOSIT_HEARTH || o.kind == Kind.DEPOSIT_EMBER) _settleDeposit(id, o);
            else _settleWithdraw(id, o);
        }
    }

    // ---------------------------------------------------------------- buy
    struct BuyCalc {
        uint256 xx;
        uint256 pr;
        uint256 q;
        uint256 hold;
        uint256 hfRate;
        int256 toPools;
        uint256 baseCost;
        uint256 hedgeAdd;
        uint256 hedgeCost;
        int256 dE;
        int256 dH;
        uint256 fee;
    }

    function _settleBuy(uint256 id, Order storage o) internal {
        if (status != Status.LIVE) return _refund(id, o, "not live");
        BuyCalc memory c;
        c.xx = x();
        c.pr = priceAt(c.xx);
        if (c.pr <= cfg.stopPrice) return _refund(id, o, "at stop");
        if (vault.stale() || vault.paused()) return _refund(id, o, "LiquidV closed");
        if (Math.mulDiv(_mul(cfg.B, c.xx), WAD, c.pr) > cfg.mintBoostLimit) return _refund(id, o, "mint limit");
        if (cfg.gapGuardK > 0 && c.pr - cfg.stopPrice < _mul(_mul(_mul(cfg.gapGuardK, cfg.B), c.xx), biggestMove())) {
            return _refund(id, o, "gap guard");
        }
        uint256 h = cfg.hearthShare;
        uint256 mf = cfg.lvMintFee;
        uint256 usd = o.amount * USDC_TO_WAD;
        c.hold = c.pr < c.xx ? c.pr : c.xx;
        c.hfRate = _mul(_mul(_mul(h, cfg.B - WAD), c.xx), mf); // the hedge fee: Hearth's LiquidV mint fee
        c.q = Math.mulDiv(usd, WAD, _mul(c.pr, WAD + cfg.buyFee) + _mul(c.hold, mf) + c.hfRate);
        if (c.q == 0 || c.q < o.minOut) return _refund(id, o, "min out");

        c.baseCost = _mul(_mul(c.q, c.xx), WAD + mf);
        c.toPools = int256(_mul(c.q, c.pr)) - int256(_mul(c.q, c.xx)) - int256(_mul(_mul(c.q, c.xx - c.hold), mf));
        c.hedgeAdd = Math.mulDiv(_mul(_mul(h, c.q), cfg.B - WAD), WAD, nav0);
        c.hedgeCost = _mul(_mul(c.hedgeAdd, nav), WAD + mf);
        uint256 S = totalSupply() + c.q;
        c.dE = _smul(c.toPools, WAD - h);
        c.dH = _smul(c.toPools, h) + int256(_mul(c.q, c.hfRate));
        if (int256(cashE) + c.dE < int256(emberNeed(S))) return _refund(id, o, "coverage full");
        // Hearth: coverage cash AND the hedge, paid for
        if (int256(cashH) + c.dH - int256(c.hedgeCost) < int256(hearthNeed(S))) return _refund(id, o, "coverage full");
        if ((c.baseCost + c.hedgeCost) / USDC_TO_WAD > vault.maxDeposit(address(this))) {
            return _refund(id, o, "LiquidV full");
        }

        o.done = true;
        escrowUsd -= usd;
        c.fee = _mul(_mul(c.q, c.pr), cfg.buyFee);
        uint256 spent = uint256(int256(c.baseCost) + c.dE + c.dH + int256(c.fee));
        cashE = uint256(int256(cashE) + c.dE);
        cashH = uint256(int256(cashH) + c.dH) - c.hedgeCost;
        _takeFee(c.fee);
        baseUnits += _deposit(c.baseCost / USDC_TO_WAD);
        if (c.hedgeCost >= USDC_TO_WAD) hedgeUnits += _deposit(c.hedgeCost / USDC_TO_WAD);
        if (spent < usd) _credit(o.user, usd - spent);
        _mint(o.user, c.q);
        emit OrderSettled(id, o.user, Kind.BUY, o.amount, c.q);
    }

    // ---------------------------------------------------------------- sell
    function _settleSell(uint256 id, Order storage o) internal {
        uint256 q = o.amount;
        if (status == Status.ENDING) return _requeue(o); // waits for the base sale; then pays the claim
        if (status != Status.LIVE) {
            o.done = true;
            _burn(address(this), q);
            uint256 out = _payClaim(o.user, q);
            emit OrderSettled(id, o.user, Kind.SELL, q, out);
            return;
        }
        uint256 xx = x();
        uint256 pr = priceAt(xx);
        uint256 xf = exitFee();
        uint256 hold = pr < xx ? pr : xx;
        uint256 value = _mul(q, pr);
        uint256 fee = _mul(value, cfg.sellFee);
        uint256 holderCost = _mul(_mul(q, hold), xf); // LiquidV exit fee on the holder's own part only
        uint256 hf = _mul(_mul(_mul(_mul(cfg.hearthShare, cfg.B - WAD), q), xx), xf);
        uint256 room = value > fee + holderCost ? value - fee - holderCost : 0;
        if (hf > room) hf = room;
        uint256 payout = value > fee + holderCost + hf ? value - fee - holderCost - hf : 0;
        if (payout / USDC_TO_WAD < o.minOut) {
            o.done = true;
            _transfer(address(this), o.user, q);
            emit OrderRefused(id, o.user, Kind.SELL, "min out");
            return;
        }
        uint256 S = totalSupply();
        uint256 units = Math.mulDiv(baseUnits, q, S);
        // LiquidV redeems instantly only up to its idle cash; otherwise the sale waits
        if (vault.previewRedeem(units) > vault.availableIdle()) return _requeue(o);
        o.done = true;
        baseUnits -= units;
        uint256 proceeds = _redeemUnits(units); // the seller's real redemption price (slippage is theirs)
        _burn(address(this), q);
        int256 poolDelta = int256(proceeds) - int256(payout) - int256(fee) - int256(hf);
        cashH += hf;
        _toPools(poolDelta);
        _takeFee(fee);
        // the sold tickets' hedge goes with them, as far as LiquidV can redeem now
        uint256 target = hedgeTarget(totalSupply());
        if (hedgeUnits > target) {
            uint256 u = _redeemableUnits(hedgeUnits - target);
            if (u > 0) {
                hedgeUnits -= u;
                cashH += _redeemUnits(u);
            }
        }
        _credit(o.user, payout);
        emit OrderSettled(id, o.user, Kind.SELL, q, payout);
    }

    // ---------------------------------------------------------------- LPs
    function _settleDeposit(uint256 id, Order storage o) internal {
        uint256 pool = o.kind == Kind.DEPOSIT_HEARTH ? 0 : 1;
        uint256 usd = o.amount * USDC_TO_WAD;
        uint256 ts = totalShares[pool];
        uint256 sh;
        if (ts == 0) {
            sh = usd;
        } else {
            int256 eq = equity(pool);
            if (eq <= 0) return _refund(id, o, "pool underwater");
            sh = Math.mulDiv(usd, ts, uint256(eq));
        }
        o.done = true;
        escrowUsd -= usd;
        if (pool == 0) cashH += usd;
        else cashE += usd;
        shares[pool][o.user] += sh;
        totalShares[pool] += sh;
        emit OrderSettled(id, o.user, o.kind, o.amount, sh);
    }

    function _settleWithdraw(uint256 id, Order storage o) internal {
        uint256 pool = o.kind == Kind.WITHDRAW_HEARTH ? 0 : 1;
        uint256 sh = o.amount;
        uint256 ts = totalShares[pool];
        int256 eq = equity(pool);
        if (eq <= 0 || ts == 0) {
            o.done = true;
            totalShares[pool] -= sh;
            emit OrderSettled(id, o.user, o.kind, sh, 0);
            return;
        }
        uint256 want = Math.mulDiv(sh, uint256(eq), ts);
        int256 fr = free(pool);
        uint256 avail = fr > 0 ? uint256(fr) : 0;
        uint256 amt = want < avail ? want : avail;
        uint256 used = want == 0 ? sh : Math.mulDiv(sh, amt, want);
        o.done = true;
        if (pool == 0) cashH -= amt;
        else cashE -= amt;
        totalShares[pool] -= used;
        _credit(o.user, amt);
        emit OrderSettled(id, o.user, o.kind, used, amt);
        if (used < sh) {
            // the rest waits for free capital (never expires: it is the LP's own money)
            orders.push(Order(o.user, o.kind, false, uint64(block.number), uint64(block.number + 1), sh - used, 0));
            emit OrderPlaced(orders.length - 1, o.user, o.kind, sh - used);
        }
    }

    // ================================================================ internals
    function _place(Kind kind, uint256 amount, uint256 minOut) internal returns (uint256 id) {
        id = orders.length;
        orders.push(Order(msg.sender, kind, false, uint64(block.number), uint64(block.number + 1), amount, minOut));
        emit OrderPlaced(id, msg.sender, kind, amount);
    }

    /// Move an order to the back of the queue for the next update (keeps its age).
    function _requeue(Order storage o) internal {
        o.done = true;
        orders.push(Order(o.user, o.kind, false, o.placed, uint64(block.number + 1), o.amount, o.minOut));
    }

    function _refund(uint256 id, Order storage o, bytes32 why) internal {
        o.done = true;
        if (o.kind == Kind.BUY || o.kind == Kind.DEPOSIT_HEARTH || o.kind == Kind.DEPOSIT_EMBER) {
            uint256 usd = o.amount * USDC_TO_WAD;
            escrowUsd -= usd;
            _credit(o.user, usd);
        } else if (o.kind == Kind.SELL) {
            _transfer(address(this), o.user, o.amount);
        } else {
            shares[o.kind == Kind.WITHDRAW_HEARTH ? 0 : 1][o.user] += o.amount;
        }
        emit OrderRefused(id, o.user, o.kind, why);
    }

    function _payClaim(address who, uint256 tickets) internal returns (uint256 out) {
        uint256 pay = _mul(tickets, claimPerTicket);
        if (pay > endReserve) pay = endReserve;
        endReserve -= pay;
        uint256 fee = _mul(pay, cfg.sellFee);
        _takeFee(fee);
        out = pay - fee;
        _credit(who, out);
    }

    function _deposit(uint256 amount) internal returns (uint256) {
        return vault.deposit(amount, address(this), vault.previewDeposit(amount));
    }

    /// Redeem `units` shares now; returns USD WAD received.
    function _redeemUnits(uint256 units) internal returns (uint256) {
        return vault.redeem(units, address(this), address(this), vault.previewRedeem(units)) * USDC_TO_WAD;
    }

    /// How many of `units` LiquidV can redeem instantly from its idle cash.
    function _redeemableUnits(uint256 units) internal view returns (uint256) {
        uint256 idle = vault.availableIdle();
        uint256 need = vault.previewRedeem(units);
        if (need <= idle) return units;
        if (need == 0) return 0;
        uint256 part = Math.mulDiv(units, idle, need);
        return part > 1 ? part - 1 : 0; // round down so it always fits
    }

    function _credit(address who, uint256 usd) internal {
        claimable[who] += usd;
        claimableTotal += usd;
    }

    function _toPools(int256 amount) internal {
        int256 dH = _smul(amount, cfg.hearthShare);
        cashH = uint256(int256(cashH) + dH);
        cashE = uint256(int256(cashE) + amount - dH);
    }

    function _takeFee(uint256 fee) internal {
        uint256 lp = _mul(fee, cfg.lpFeeShare);
        _toPools(int256(lp));
        protocolFees += fee - lp;
    }

    function _mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return Math.mulDiv(a, b, WAD);
    }

    function _smul(int256 a, uint256 b) internal pure returns (int256) {
        return a >= 0 ? int256(Math.mulDiv(uint256(a), b, WAD)) : -int256(Math.mulDiv(uint256(-a), b, WAD));
    }
}
