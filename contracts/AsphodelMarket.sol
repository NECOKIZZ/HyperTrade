// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPriceFeed} from "./interfaces/IPriceFeed.sol";
import {IBase} from "./interfaces/IBase.sol";
import {IMarketCalendar} from "./interfaces/IMarketCalendar.sol";

/// @title Asphodel boost market: one Series of one boosted token on one asset.
/// @notice A buyer's money buys the real asset (the base). The Meadow (Hearth + Ember LP pools)
/// backs the boost: an extra (B - 1) x the asset's move since launch, capped at MAXB per ticket.
///
///   x      = price now / price at launch            (one common zero: the launch)
///   boost  = (B - 1) x (x - 1), capped at MAXB       MAXB = (B - 1)(C - 1) / B
///   price  = max(0, x + boost) x carry               = 1 + B(x - 1) up to the max; starts at $1
///
/// Stop: price <= stopPrice on `confirmUpdates` updates >= `confirmSeconds` apart -> the base is sold,
///       holders get what's left at the sale price, the Meadow the rest.
/// Crown: x >= xc on the same rule -> the Meadow pays exactly MAXB, holders get the base's real
///       sale value + MAXB.
/// Orders fill at the next price update after the block they were placed in (never at a price the
/// buyer could see). While the real market is shut (calendar): no new tickets, no stop/crown, and the
/// boost part of a sale uses the 1-hour average price.
/// Hearth holds the hedge ((B - 1) units of base per ticket, its share) and its hedge counts as its
/// collateral, valued at the max price less a haircut. Ember locks its share of MAXB in cash.
contract AsphodelMarket is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant USDC_TO_WAD = 1e12; // USDC has 6 decimals
    uint256 internal constant SAMPLES = 32;

    enum Status {
        LIVE,
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
        uint256 B; //                 boost level, WAD (2e18 = 2x)
        uint256 C; //                 max ticket price, WAD (3e18 = $3)
        uint256 stopPrice; //         WAD (0.25e18)
        uint256 hearthShare; //       Hearth's fixed share of every ticket's boost, WAD
        uint256 buyFee; //            WAD
        uint256 sellFee; //           WAD
        uint256 lpFeeShare; //        share of buy/sell fees to LPs, WAD (rest to protocol)
        uint256 mintBoostLimit; //    refuse mints when the live boost B*x/price is above this, WAD
        uint256 gapGuardK; //         refuse mints if price - stop < k * B * x * biggest recent move, WAD (0 = off)
        uint256 hedgeHaircut; //      haircut on Hearth's hedge counted as collateral, WAD (0.2e18)
        uint256 carryPerSecond; //    ticket value lost per second to carry, WAD (0 = off)
        uint32 confirmUpdates; //     updates in a row for a stop or crown (2)
        uint32 confirmSeconds; //     minimum time between first and confirming update (60)
        uint32 gapWindow; //          updates of history for the gap guard (<= 32)
        uint32 maxBatch; //           orders settled per update
        uint32 maxOrderAge; //        blocks: an order not settled within this many blocks expires
    }

    struct Order {
        address user;
        Kind kind;
        bool done;
        uint64 blockNumber;
        uint256 amount; //   BUY/DEPOSIT: USDC (6 dp); SELL: tickets (WAD); WITHDRAW: pool shares (WAD)
        uint256 minOut; //   BUY: min tickets; SELL: min USDC (6 dp)
    }

    // ---------------------------------------------------------------- immutable setup
    IERC20 public immutable usdc;
    IBase public immutable base;
    IPriceFeed public immutable feed;
    IMarketCalendar public immutable calendar;
    uint256 public immutable nav0; //      asset price at launch, WAD
    uint256 public immutable launchTime;
    uint256 public immutable xStop; //     x at the stop price
    uint256 public immutable xCrown; //    x at the max price
    uint256 public immutable maxBoost; //  MAXB per ticket, WAD
    Config internal cfg;

    // ---------------------------------------------------------------- state
    Status public status;
    uint256 public nav; //                 last good price, WAD
    uint256 public lastPokeBlock;
    uint256 public baseUnits; //           holders' base, units (WAD)
    uint256 public hedgeUnits; //          Hearth's hedge, units (WAD)
    uint256 public cashH; //               Hearth cash, USD WAD
    uint256 public cashE; //               Ember cash, USD WAD
    uint256 public protocolFees; //        USD WAD
    uint256 public endReserve; //          owed to holders after a Crown/stop, USD WAD
    uint256 public claimPerTicket; //      after a Crown/stop, USD WAD per ticket
    uint256 public escrowUsd; //           USDC waiting in buy/deposit orders, USD WAD
    uint256 public claimableTotal; //      USD WAD
    mapping(address => uint256) public claimable; // USD WAD

    uint32 public aboveCount;
    uint32 public belowCount;
    uint64 public aboveSince;
    uint64 public belowSince;

    uint256[SAMPLES] internal sampleTime;
    uint256[SAMPLES] internal samplePrice;
    uint256 internal sampleCount;
    uint256[SAMPLES] internal moves; //    |p / prev - 1| per update, WAD

    Order[] public orders;
    uint256 public head;

    mapping(uint256 => mapping(address => uint256)) public shares; // pool => owner => shares
    uint256[2] public totalShares;

    // ---------------------------------------------------------------- events / errors
    event OrderPlaced(uint256 indexed id, address indexed user, Kind kind, uint256 amount);
    event OrderSettled(uint256 indexed id, address indexed user, Kind kind, uint256 amountIn, uint256 amountOut);
    event OrderRefused(uint256 indexed id, address indexed user, Kind kind, bytes32 reason);
    event Poked(uint256 price, bool fresh, bool marketOpen);
    event Crowned(uint256 x, uint256 claimPerTicket);
    event KnockedOut(uint256 x, uint256 claimPerTicket);
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
        IERC20 usdc_,
        IBase base_,
        IPriceFeed feed_,
        IMarketCalendar calendar_,
        Config memory cfg_,
        address owner_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        if (
            cfg_.B <= WAD || cfg_.C <= WAD || cfg_.stopPrice >= WAD || cfg_.hearthShare > WAD
                || cfg_.lpFeeShare > WAD || cfg_.hedgeHaircut >= WAD || cfg_.confirmUpdates == 0
                || cfg_.gapWindow > SAMPLES || cfg_.maxBatch == 0 || cfg_.maxOrderAge == 0
        ) revert BadConfig();
        usdc = usdc_;
        base = base_;
        feed = feed_;
        calendar = calendar_;
        cfg = cfg_;
        (uint256 p, bool ok) = feed_.read();
        if (!ok || p == 0) revert BadPrice();
        nav0 = p;
        nav = p;
        launchTime = block.timestamp;
        xStop = WAD - Math.mulDiv(WAD - cfg_.stopPrice, WAD, cfg_.B);
        xCrown = WAD + Math.mulDiv(cfg_.C - WAD, WAD, cfg_.B);
        maxBoost = _mul(cfg_.B - WAD, xCrown - WAD);
        _record(p, 0);
        usdc_.forceApprove(address(base_), type(uint256).max);
    }

    // ================================================================ views
    function config() external view returns (Config memory) {
        return cfg;
    }

    function x() public view returns (uint256) {
        return Math.mulDiv(nav, WAD, nav0);
    }

    /// Ticket value at x for the base and xBoost for the boost part (equal outside weekends).
    function priceAt(uint256 xBase, uint256 xBoost) public view returns (uint256) {
        int256 boost = int256(_mul(cfg.B - WAD, xBoost)) - int256(cfg.B - WAD); // (B-1)(x-1)
        if (boost > int256(maxBoost)) boost = int256(maxBoost);
        int256 v = int256(xBase) + boost;
        if (v <= 0) return 0;
        return _mul(uint256(v), carryFactor());
    }

    /// Ticket value now (after a Crown/stop: the fixed claim).
    function price() public view returns (uint256) {
        if (status != Status.LIVE) return claimPerTicket;
        uint256 xx = x();
        return priceAt(xx, xx);
    }

    function carryFactor() public view returns (uint256) {
        uint256 lost = cfg.carryPerSecond * (block.timestamp - launchTime);
        return lost >= WAD ? 0 : WAD - lost;
    }

    /// Live boost a buyer gets now: B * x / price.
    function effectiveBoost() public view returns (uint256) {
        uint256 pr = price();
        if (pr == 0) return type(uint256).max;
        return Math.mulDiv(_mul(cfg.B, x()), WAD, pr);
    }

    /// What the Meadow owes holders on top of the base (negative: holders owe it). USD WAD.
    function liability() public view returns (int256) {
        if (status != Status.LIVE) return 0;
        uint256 xx = x();
        return _smul(int256(priceAt(xx, xx)) - int256(xx), totalSupply());
    }

    function coverageNeeded(uint256 supply) public view returns (uint256) {
        return status == Status.LIVE ? _mul(supply, maxBoost) : 0;
    }

    /// Cash Hearth must hold: its share of MAXB, less what its hedge would sell for at the max.
    function hearthNeed(uint256 supply, uint256 hedge) public view returns (uint256) {
        uint256 need = _mul(cfg.hearthShare, coverageNeeded(supply));
        uint256 credit = _mul(_mul(_mul(hedge, _mul(nav0, xCrown)), WAD - base.exitFeeWad()), WAD - cfg.hedgeHaircut);
        return need > credit ? need - credit : 0;
    }

    function emberNeed(uint256 supply) public view returns (uint256) {
        return _mul(WAD - cfg.hearthShare, coverageNeeded(supply));
    }

    function hedgeTarget(uint256 supply) public view returns (uint256) {
        if (status != Status.LIVE) return 0;
        return Math.mulDiv(_mul(_mul(cfg.hearthShare, supply), cfg.B - WAD), WAD, nav0);
    }

    function equity(uint256 pool) public view returns (int256) {
        int256 liab = liability();
        if (pool == 0) {
            uint256 hedgeVal = _mul(_mul(hedgeUnits, nav), WAD - base.exitFeeWad());
            return int256(cashH + hedgeVal) - _smul(liab, cfg.hearthShare);
        }
        return int256(cashE) - _smul(liab, WAD - cfg.hearthShare);
    }

    function free(uint256 pool) public view returns (int256) {
        if (pool == 0) return int256(cashH) - int256(hearthNeed(totalSupply(), hedgeUnits));
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

    /// Biggest single-update move in the gap window.
    function biggestMove() public view returns (uint256 m) {
        uint256 n = sampleCount < cfg.gapWindow ? sampleCount : cfg.gapWindow;
        for (uint256 i = 0; i < n; i++) {
            uint256 v = moves[(sampleCount - 1 - i) % SAMPLES];
            if (v > m) m = v;
        }
    }

    /// Average price over the last hour of updates (the current one if there are none).
    function hourAverage() public view returns (uint256) {
        uint256 sum;
        uint256 k;
        uint256 n = sampleCount < SAMPLES ? sampleCount : SAMPLES;
        for (uint256 i = 0; i < n; i++) {
            uint256 j = (sampleCount - 1 - i) % SAMPLES;
            if (block.timestamp - sampleTime[j] > 1 hours) break;
            sum += samplePrice[j];
            k++;
        }
        return k == 0 ? nav : sum / k;
    }

    // ================================================================ orders
    function requestBuy(uint256 usdcIn, uint256 minTickets) external nonReentrant returns (uint256 id) {
        if (status != Status.LIVE) revert NotLive();
        if (usdcIn == 0) revert Zero();
        usdc.safeTransferFrom(msg.sender, address(this), usdcIn);
        escrowUsd += usdcIn * USDC_TO_WAD;
        id = _place(Kind.BUY, usdcIn, minTickets);
    }

    function requestSell(uint256 tickets, uint256 minUsdc) external nonReentrant returns (uint256 id) {
        if (status != Status.LIVE) revert NotLive();
        if (tickets == 0) revert Zero();
        _transfer(msg.sender, address(this), tickets);
        id = _place(Kind.SELL, tickets, minUsdc);
    }

    function requestDeposit(bool hearth, uint256 usdcIn) external nonReentrant returns (uint256 id) {
        if (usdcIn == 0) revert Zero();
        usdc.safeTransferFrom(msg.sender, address(this), usdcIn);
        escrowUsd += usdcIn * USDC_TO_WAD;
        id = _place(hearth ? Kind.DEPOSIT_HEARTH : Kind.DEPOSIT_EMBER, usdcIn, 0);
    }

    function requestWithdraw(bool hearth, uint256 poolShares) external nonReentrant returns (uint256 id) {
        uint256 pool = hearth ? 0 : 1;
        if (poolShares == 0 || poolShares > shares[pool][msg.sender]) revert Zero();
        shares[pool][msg.sender] -= poolShares; // escrowed until the order settles
        id = _place(hearth ? Kind.WITHDRAW_HEARTH : Kind.WITHDRAW_EMBER, poolShares, 0);
    }

    /// Take back an order nobody settled (feed stale, no updates) after maxOrderAge blocks.
    /// Not earlier: cancelling after seeing the price would be a free option against LPs.
    function cancel(uint256 id) external nonReentrant {
        Order storage o = orders[id];
        if (o.user != msg.sender) revert NotYours();
        if (o.done) revert Zero();
        if (block.number <= o.blockNumber + cfg.maxOrderAge) revert TooYoung();
        _refund(id, o, "cancelled");
    }

    /// After a Crown or stop: swap tickets for their fixed claim.
    function redeem(uint256 tickets) external nonReentrant returns (uint256 usdOut) {
        if (status == Status.LIVE) revert NotEnded();
        _burn(msg.sender, tickets);
        uint256 pay = _mul(tickets, claimPerTicket);
        if (pay > endReserve) pay = endReserve;
        endReserve -= pay;
        uint256 fee = _mul(pay, cfg.sellFee);
        _takeFee(fee);
        usdOut = pay - fee;
        _credit(msg.sender, usdOut);
        emit Redeemed(msg.sender, tickets, usdOut);
    }

    /// Withdraw USDC owed (sale proceeds, refunds, LP withdrawals).
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
    /// One price update: read the price, check stop/crown, then settle orders placed in earlier blocks.
    /// Anyone can call it, once per block.
    function poke() external nonReentrant {
        if (block.number <= lastPokeBlock) revert AlreadyPoked();
        lastPokeBlock = block.number;
        (uint256 p, bool ok) = feed.read();
        bool open = calendar.isOpen(block.timestamp);
        emit Poked(p, ok && p > 0, open);
        if (!ok || p == 0) return; // stale: nothing fills, nothing triggers
        _record(p, nav);
        nav = p;
        if (status == Status.LIVE) _checkTriggers(open);
        _settleOrders(open);
    }

    function _checkTriggers(bool open) internal {
        if (!open) {
            // stops and maxes only fire on real-market prices; a half-confirmed one isn't carried
            aboveCount = 0;
            belowCount = 0;
            return;
        }
        uint256 xx = x();
        uint64 nowT = uint64(block.timestamp);
        if (xx >= xCrown) {
            if (aboveCount == 0) aboveSince = nowT;
            aboveCount++;
        } else {
            aboveCount = 0;
        }
        if (priceAt(xx, xx) <= cfg.stopPrice) {
            if (belowCount == 0) belowSince = nowT;
            belowCount++;
        } else {
            belowCount = 0;
        }
        if (aboveCount >= cfg.confirmUpdates && nowT - aboveSince >= cfg.confirmSeconds) {
            _crown();
        } else if (belowCount >= cfg.confirmUpdates && nowT - belowSince >= cfg.confirmSeconds) {
            _knockOut();
        }
    }

    function _settleOrders(bool open) internal {
        uint256 n;
        while (head < orders.length && n < cfg.maxBatch) {
            Order storage o = orders[head];
            if (o.blockNumber >= block.number) break; // placed this block: next update
            uint256 id = head;
            head++;
            if (o.done) continue;
            n++;
            if (block.number > o.blockNumber + cfg.maxOrderAge) {
                _refund(id, o, "expired");
                continue;
            }
            if (o.kind == Kind.BUY) _settleBuy(id, o, open);
            else if (o.kind == Kind.SELL) _settleSell(id, o, open);
            else if (o.kind == Kind.DEPOSIT_HEARTH || o.kind == Kind.DEPOSIT_EMBER) _settleDeposit(id, o);
            else _settleWithdraw(id, o);
        }
    }

    // ---------------------------------------------------------------- buy
    struct BuyCalc {
        uint256 xx;
        uint256 pr;
        uint256 usd;
        uint256 q;
        uint256 mf;
        uint256 hold;
        uint256 hfRate;
        int256 toPools; //    boost paid in, less the base fee the Meadow covers
        uint256 hedgeAdd;
        uint256 hedgeCost;
    }

    function _settleBuy(uint256 id, Order storage o, bool open) internal {
        if (status != Status.LIVE) return _refund(id, o, "not live");
        if (!open) return _refund(id, o, "market shut");
        BuyCalc memory c;
        c.xx = x();
        c.pr = priceAt(c.xx, c.xx);
        if (c.pr <= cfg.stopPrice) return _refund(id, o, "at stop");
        if (Math.mulDiv(_mul(cfg.B, c.xx), WAD, c.pr) > cfg.mintBoostLimit) return _refund(id, o, "mint limit");
        if (cfg.gapGuardK > 0 && c.pr - cfg.stopPrice < _mul(_mul(_mul(cfg.gapGuardK, cfg.B), c.xx), biggestMove())) {
            return _refund(id, o, "gap guard");
        }
        uint256 h = cfg.hearthShare;
        c.usd = o.amount * USDC_TO_WAD;
        c.mf = base.mintFeeWad();
        c.hold = c.pr < c.xx ? c.pr : c.xx;
        c.hfRate = _mul(_mul(_mul(h, cfg.B - WAD), c.xx), c.mf);
        uint256 denom = _mul(c.pr, WAD + cfg.buyFee) + _mul(c.hold, c.mf) + c.hfRate;
        c.q = Math.mulDiv(c.usd, WAD, denom);
        if (c.q == 0 || c.q < o.minOut) return _refund(id, o, "min out");

        uint256 baseCost = _mul(_mul(c.q, c.xx), WAD + c.mf); // q/nav0 units at nav, plus fee
        uint256 meadowFee = _mul(_mul(c.q, c.xx - c.hold), c.mf); // base fee on the Meadow's part
        c.toPools = int256(_mul(c.q, c.pr)) - int256(_mul(c.q, c.xx)) - int256(meadowFee);
        c.hedgeAdd = Math.mulDiv(_mul(_mul(h, c.q), cfg.B - WAD), WAD, nav0);
        c.hedgeCost = _mul(_mul(c.hedgeAdd, nav), WAD + c.mf);
        uint256 S = totalSupply() + c.q;

        int256 dE = _smul(c.toPools, WAD - h);
        int256 dH = _smul(c.toPools, h) + int256(_mul(c.q, c.hfRate));
        if (int256(cashE) + dE < int256(emberNeed(S))) return _refund(id, o, "coverage full");
        if (int256(cashH) + dH - int256(c.hedgeCost) < int256(hearthNeed(S, hedgeUnits + c.hedgeAdd))) {
            return _refund(id, o, "coverage full");
        }

        // execute
        o.done = true;
        escrowUsd -= c.usd;
        uint256 fee = _mul(_mul(c.q, c.pr), cfg.buyFee);
        // what the buyer paid for: the base, the pools' take (boost in, hedge fee), the trading fee
        uint256 spent = uint256(int256(baseCost) + dE + dH + int256(fee));
        cashE = uint256(int256(cashE) + dE);
        cashH = uint256(int256(cashH) + dH) - c.hedgeCost;
        _takeFee(fee);
        baseUnits += base.buy(baseCost / USDC_TO_WAD);
        if (c.hedgeCost > 0) hedgeUnits += base.buy(c.hedgeCost / USDC_TO_WAD);
        if (spent < c.usd) _credit(o.user, c.usd - spent); // rounding dust back to the buyer
        _mint(o.user, c.q);
        emit OrderSettled(id, o.user, Kind.BUY, o.amount, c.q);
    }

    // ---------------------------------------------------------------- sell
    function _settleSell(uint256 id, Order storage o, bool open) internal {
        uint256 q = o.amount;
        if (status != Status.LIVE) {
            // ended between the request and this update: settle at the claim
            o.done = true;
            uint256 pay = _mul(q, claimPerTicket);
            if (pay > endReserve) pay = endReserve;
            endReserve -= pay;
            uint256 endFee = _mul(pay, cfg.sellFee);
            _takeFee(endFee);
            _burn(address(this), q);
            _credit(o.user, pay - endFee);
            emit OrderSettled(id, o.user, Kind.SELL, q, pay - endFee);
            return;
        }
        uint256 xx = x();
        uint256 pr = open ? priceAt(xx, xx) : priceAt(xx, Math.mulDiv(hourAverage(), WAD, nav0));
        uint256 xf = base.exitFeeWad();
        uint256 hold = pr < xx ? pr : xx;
        uint256 value = _mul(q, pr);
        uint256 fee = _mul(value, cfg.sellFee);
        uint256 holderCost = _mul(_mul(q, hold), xf); //     base exit fee on the holder's own part
        uint256 hf = _mul(_mul(_mul(_mul(cfg.hearthShare, cfg.B - WAD), q), xx), xf); // Hearth's hedge exit
        uint256 room = value > fee + holderCost ? value - fee - holderCost : 0;
        if (hf > room) hf = room; // never charge more than the seller is owed
        uint256 payout = value > fee + holderCost + hf ? value - fee - holderCost - hf : 0;
        if (payout / USDC_TO_WAD < o.minOut) {
            o.done = true;
            _transfer(address(this), o.user, q);
            emit OrderRefused(id, o.user, Kind.SELL, "min out");
            return;
        }
        o.done = true;
        uint256 S = totalSupply();
        uint256 units = Math.mulDiv(baseUnits, q, S);
        baseUnits -= units;
        uint256 proceeds = base.sell(units) * USDC_TO_WAD;
        _burn(address(this), q);
        // the sold tickets' hedge goes with them (first: it is what pays Hearth's share)
        uint256 target = hedgeTarget(totalSupply());
        if (hedgeUnits > target) {
            uint256 u = hedgeUnits - target;
            hedgeUnits = target;
            cashH += base.sell(u) * USDC_TO_WAD;
        }
        int256 poolDelta = int256(proceeds) - int256(payout) - int256(fee) - int256(hf);
        cashH += hf;
        _toPools(poolDelta);
        _takeFee(fee);
        _credit(o.user, payout);
        emit OrderSettled(id, o.user, Kind.SELL, q, payout);
    }

    // ---------------------------------------------------------------- LPs
    function _settleDeposit(uint256 id, Order storage o) internal {
        uint256 pool = o.kind == Kind.DEPOSIT_HEARTH ? 0 : 1;
        uint256 usd = o.amount * USDC_TO_WAD;
        int256 eq = equity(pool);
        uint256 ts = totalShares[pool];
        uint256 sh;
        if (ts == 0) {
            sh = usd;
        } else {
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
        o.done = true;
        if (eq <= 0 || ts == 0) {
            totalShares[pool] -= sh; // worthless
            emit OrderSettled(id, o.user, o.kind, sh, 0);
            return;
        }
        uint256 want = Math.mulDiv(sh, uint256(eq), ts);
        int256 fr = free(pool);
        uint256 avail = fr > 0 ? uint256(fr) : 0;
        uint256 amt = want < avail ? want : avail;
        uint256 used = want == 0 ? sh : Math.mulDiv(sh, amt, want);
        if (pool == 0) cashH -= amt;
        else cashE -= amt;
        totalShares[pool] -= used;
        _credit(o.user, amt);
        emit OrderSettled(id, o.user, o.kind, used, amt);
        if (used < sh) {
            // the rest waits for free capital: back of the queue
            orders.push(Order(o.user, o.kind, false, uint64(block.number), sh - used, 0));
            emit OrderPlaced(orders.length - 1, o.user, o.kind, sh - used);
        }
    }

    // ---------------------------------------------------------------- Crown / stop
    function _sellHedge() internal {
        if (hedgeUnits > 0) {
            uint256 u = hedgeUnits;
            hedgeUnits = 0;
            cashH += base.sell(u) * USDC_TO_WAD;
        }
    }

    function _crown() internal {
        uint256 S = totalSupply();
        uint256 xx = x();
        _sellHedge(); // Hearth's hedge pays its share
        uint256 proceeds = baseUnits > 0 ? base.sell(baseUnits) * USDC_TO_WAD : 0;
        baseUnits = 0;
        status = Status.CROWNED;
        uint256 owed = _mul(proceeds + _mul(S, maxBoost), carryFactor());
        _toPools(int256(proceeds) - int256(owed)); // the Meadow pays exactly MAXB (less carry)
        endReserve = owed;
        claimPerTicket = S > 0 ? Math.mulDiv(owed, WAD, S) : 0;
        emit Crowned(xx, claimPerTicket);
    }

    function _knockOut() internal {
        uint256 S = totalSupply();
        uint256 xx = x();
        _sellHedge();
        uint256 proceeds = baseUnits > 0 ? base.sell(baseUnits) * USDC_TO_WAD : 0;
        baseUnits = 0;
        status = Status.KNOCKED_OUT;
        uint256 left = priceAt(xx, xx); // what's left for holders at the sale price (>= 0)
        uint256 owed = _mul(S, left);
        if (owed > proceeds) owed = proceeds;
        _toPools(int256(proceeds) - int256(owed));
        endReserve = owed;
        claimPerTicket = S > 0 ? Math.mulDiv(owed, WAD, S) : 0;
        emit KnockedOut(xx, claimPerTicket);
    }

    // ================================================================ internals
    function _place(Kind kind, uint256 amount, uint256 minOut) internal returns (uint256 id) {
        id = orders.length;
        orders.push(Order(msg.sender, kind, false, uint64(block.number), amount, minOut));
        emit OrderPlaced(id, msg.sender, kind, amount);
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

    function _credit(address who, uint256 usd) internal {
        claimable[who] += usd;
        claimableTotal += usd;
    }

    function _toPools(int256 amount) internal {
        int256 dH = _smul(amount, cfg.hearthShare);
        int256 dE = amount - dH;
        cashH = uint256(int256(cashH) + dH); // reverts if a pool would go negative
        cashE = uint256(int256(cashE) + dE);
    }

    function _takeFee(uint256 fee) internal {
        uint256 lp = _mul(fee, cfg.lpFeeShare);
        _toPools(int256(lp));
        protocolFees += fee - lp;
    }

    function _record(uint256 p, uint256 prev) internal {
        uint256 j = sampleCount % SAMPLES;
        sampleTime[j] = block.timestamp;
        samplePrice[j] = p;
        if (prev > 0) {
            uint256 d = p > prev ? p - prev : prev - p;
            moves[j] = Math.mulDiv(d, WAD, prev);
        }
        sampleCount++;
    }

    function _mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return Math.mulDiv(a, b, WAD);
    }

    function _smul(int256 a, uint256 b) internal pure returns (int256) {
        return a >= 0 ? int256(Math.mulDiv(uint256(a), b, WAD)) : -int256(Math.mulDiv(uint256(-a), b, WAD));
    }
}
