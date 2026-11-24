"""Asphodel v0.5 engine, round 2: built to be attacked.

Same product as engine.py:
  x      = NAV_now / NAV_launch
  price  = clamp(1 + B*(x - 1), 0, C)              starts at $1.00
  base   = x per token, real $vTRADER (1/NAV_launch units per token)
  boost  = price - base, owed by (or to) the Meadow

Extra knobs, each one a design choice the attacks probe:
  stop_price      knock out at a price above $0 and pay holders what's left (stop buffer)
  ko_confirm      updates below the stop before a knockout fires
  crown_confirm   updates above the max before a Crown fires
  crown_mode      'fixed_C'     holders are promised exactly C, the Meadow pays the rest
                  'fixed_boost' the Meadow's payment is fixed; holders get base proceeds + it
  sale_delay      updates before the base can actually be sold at Crown/knockout
  impact_depth    LiquidV slippage: a mint/redeem of N dollars costs N/depth extra
  impact_payer    'transactor' (the buyer/seller pays it) or 'meadow' (LPs eat it)
  share_mode      'fixed' (Hearth/Ember split fixed) or 'prorata' (follows pool capital)
  deposit_lock    updates an LP deposit is locked
  gap_guard       refuse mints if the distance to the stop is smaller than k x the
                  biggest recent single-update move
  gap_fee         extra buy fee = gap_fee x biggest recent single-update move (to LPs)
  hedge_credit    Hearth's hedge counts as its coverage (valued at the max price, less
                  hedge_haircut); the hedge is bought/sold with each mint/redeem
"""
from dataclasses import dataclass, field
from collections import deque
import math

INF = float("inf")


@dataclass
class Params:
    B: float = 2.0
    C: float = 3.0
    buy_fee: float = 0.003
    sell_fee: float = 0.003
    lp_fee_share: float = 0.60
    lv_mint: float = 0.01
    lv_exit: float = 0.003
    hedge_band: float = 0.05
    mint_boost_limit: float = 4.0
    hearth_share: float = 0.5
    hedge_fee: bool = True
    stop_price: float = 0.0
    ko_confirm: int = 1
    crown_confirm: int = 1
    crown_mode: str = "fixed_boost"
    sale_delay: int = 0
    impact_depth: float = INF
    impact_payer: str = "transactor"
    share_mode: str = "fixed"
    share_band: float = 0.02
    deposit_lock: int = 0
    gap_guard: float = 0.0       # k; 0 = off
    gap_window: int = 72
    gap_fee: float = 0.0
    hedge_credit: bool = False
    hedge_haircut: float = 0.2

    @property
    def x_ceiling(self):
        return 1 + (self.C - 1) / self.B

    @property
    def x_stop(self):
        return 1 + (self.stop_price - 1) / self.B

    @property
    def max_liab(self):
        fb = (self.B - 1) * (self.x_ceiling - 1)
        if self.crown_mode == "fixed_C":
            return fb + self.x_ceiling * self.lv_exit
        return fb


class Refused(Exception):
    pass


@dataclass
class Market:
    nav0: float
    p: Params
    cash_H: float
    cash_E: float
    supply: float = 0.0
    hedge_units: float = 0.0
    status: str = "LIVE"            # LIVE, ENDING, CROWNED, KNOCKED_OUT
    end_kind: str = ""
    claim: float = 0.0              # per-token value after a Crown/knockout settles
    nav: float = 0.0
    step: int = 0
    fresh: bool = True              # price feed fresh (False = stale: no fills)
    violations: list = field(default_factory=list)
    log: list = field(default_factory=list)

    def __post_init__(self):
        self.nav = self.nav0
        self.h = self.p.hearth_share
        self.moves = deque(maxlen=self.p.gap_window)
        self.below = self.above = 0
        self.pending = None          # (due_step, base_units, hedge_units, kind, x_trigger)
        self.end_reserve = 0.0
        self.fees_protocol = self.lv_fees = self.impact_paid = 0.0
        self.impact_meadow = self.hedge_costs = self.gap_loss = 0.0
        self.unhedged_updates = 0
        self.refused = {}
        # LP ledgers: pool -> {owner: shares}; 1 share = $1 at start
        self.shares = {"H": {"passive": self.cash_H}, "E": {"passive": self.cash_E}}
        self.locked = {"H": {}, "E": {}}  # owner -> unlock step
        self.lp_flow = {}                 # owner -> net USDC put in (+) / taken out (-)
        self.q_dep, self.q_wd = [], []

    # ------------------------------------------------------------ pricing
    @property
    def x(self):
        return self.nav / self.nav0

    def raw_price(self, x=None):
        x = self.x if x is None else x
        return 1 + self.p.B * (x - 1)

    def price(self):
        if self.status in ("CROWNED", "KNOCKED_OUT"):
            return self.claim
        if self.status == "ENDING":
            return 0.0
        p = self.p
        if p.crown_mode == "fixed_boost":
            # the LPs' boost stops at the covered amount; the holder's real token keeps its full value
            fb = (p.B - 1) * (p.x_ceiling - 1)
            return max(0.0, min(self.raw_price(), self.x + fb))
        return min(max(self.raw_price(), 0.0), p.C)

    def boost_part(self):
        if self.status != "LIVE":
            return 0.0
        return self.price() - self.x

    def effective_boost(self):
        pr = self.price()
        return INF if pr <= 0 else self.p.B * self.x / pr

    def coverage_needed(self, supply=None):
        s = self.supply if supply is None else supply
        return s * self.p.max_liab if self.status in ("LIVE", "ENDING") else 0.0

    @property
    def cash(self):
        return self.cash_H + self.cash_E

    def hedge_target(self, supply=None, h=None):
        s = self.supply if supply is None else supply
        h = self.h if h is None else h
        return h * s * (self.p.B - 1) / self.nav0 if self.status == "LIVE" else 0.0

    def hedge_short_cost(self, supply=None, h=None):
        short = max(0.0, self.hedge_target(supply, h) - self.hedge_units)
        return short * self.nav * (1 + self.p.lv_mint)

    def hearth_need(self, supply=None, units=None):
        """Cash Hearth must hold. With hedge_credit, the hedge it holds pays its share at the max."""
        base = self.h * self.coverage_needed(supply)
        if not self.p.hedge_credit:
            return base
        u = self.hedge_units if units is None else units
        return max(0.0, base - u * self._credit_per_unit())

    def _credit_per_unit(self):
        p = self.p
        return self.nav0 * p.x_ceiling * (1 - p.lv_exit) * (1 - p.hedge_haircut)

    def free(self, pool):
        if pool == "H":
            if self.p.hedge_credit:
                return self.cash_H - self.hearth_need()
            return self.cash_H - self.h * self.coverage_needed() - self.hedge_short_cost()
        return self.cash_E - (1 - self.h) * self.coverage_needed()

    def liability(self):
        """What the Meadow owes holders on top of the base (negative = holders owe it)."""
        S, x, p = self.supply, self.x, self.p
        if self.status == "LIVE":
            return S * self.boost_part()
        if self.status == "ENDING":
            if self.end_kind == "CROWN":
                fb = (p.B - 1) * (p.x_ceiling - 1)
                if p.crown_mode == "fixed_boost":
                    return S * fb
                if p.crown_mode == "capped":
                    return S * min(fb, p.C - x * (1 - p.lv_exit))
                return S * (p.C - x * (1 - p.lv_exit))
            return S * (max(0.0, self.raw_price()) - x)
        return 0.0

    def equity(self, pool):
        share = self.h if pool == "H" else 1 - self.h
        liab = share * self.liability()
        if pool == "H":
            return self.cash_H + self.hedge_units * self.nav * (1 - self.p.lv_exit) - liab
        return self.cash_E - liab

    def jmax(self):
        return max(self.moves) if self.moves else 0.0

    # ------------------------------------------------------------ helpers
    def _impact(self, usd):
        return 0.0 if self.p.impact_depth == INF else min(0.5, usd / self.p.impact_depth)

    def _lv(self, units):
        """Mint (+) / redeem (-) at NAV. Returns (usd_moved, fee, impact) all >= 0."""
        usd = abs(units) * self.nav
        fee = usd * (self.p.lv_mint if units > 0 else self.p.lv_exit)
        imp = usd * self._impact(usd)
        self.lv_fees += fee
        self.impact_paid += imp
        return usd, fee, imp

    def _to_pools(self, amount, h=None):
        h = self.h if h is None else h
        self.cash_H += amount * h
        self.cash_E += amount * (1 - h)

    def _fee(self, amount):
        lp = amount * self.p.lp_fee_share
        self._to_pools(lp)
        self.fees_protocol += amount - lp

    def _refuse(self, why):
        self.refused[why] = self.refused.get(why, 0) + 1
        raise Refused(why)

    # ------------------------------------------------------------ trading
    def buy(self, usdc):
        p = self.p
        if self.status != "LIVE":
            self._refuse("not live")
        if not self.fresh:
            self._refuse("stale price")
        pr, x = self.price(), self.x
        if pr <= p.stop_price + 1e-12:
            self._refuse("at stop")
        if self.effective_boost() > p.mint_boost_limit:
            self._refuse("mint limit")
        if p.gap_guard and (pr - p.stop_price) < p.gap_guard * p.B * x * self.jmax():
            self._refuse("gap guard")
        h = self.h
        gapfee = p.gap_fee * self.jmax()
        hf_rate = h * (p.B - 1) * x * p.lv_mint if p.hedge_fee else 0.0
        q = usdc / (pr * (1 + p.buy_fee + gapfee) + min(pr, x) * p.lv_mint + hf_rate)
        for _ in range(3):  # impact depends on size
            imp_rate = self._impact(q * x)   # base notional = q/nav0 units x nav
            holder_imp = imp_rate * min(pr, x) if p.impact_payer == "transactor" else 0.0
            q = usdc / (pr * (1 + p.buy_fee + gapfee) + min(pr, x) * p.lv_mint + holder_imp + hf_rate)
        units = q / self.nav0
        usd, lvfee, imp = self._lv(units)
        holder_cost = q * (min(pr, x) * p.lv_mint + (imp / max(q * x, 1e-18)) * min(pr, x)
                           * (p.impact_payer == "transactor"))
        boost_in = q * (pr - x)                      # buyer pays the Meadow the boost (or Meadow pays)
        meadow_cost = (lvfee + imp) - holder_cost    # base costs not paid by the buyer
        need = self.coverage_needed(self.supply + q)
        hedge_cost = self.hedge_short_cost(self.supply + q)
        dE = (1 - h) * (boost_in - meadow_cost)
        dH = h * (boost_in - meadow_cost) + q * hf_rate
        if self.cash_E + dE < (1 - h) * need - 1e-9:
            self._lv_undo(lvfee, imp)
            self._refuse("coverage full")
        hunits = 0.0
        if p.hedge_credit:
            # Hearth buys this ticket's hedge now (the buyer's hedge fee pays its mint fee)
            hunits = max(0.0, self.hedge_target(self.supply + q) - self.hedge_units)
            hedge_cost = hunits * self.nav * (1 + p.lv_mint)
            if self.cash_H + dH - hedge_cost < self.hearth_need(self.supply + q, self.hedge_units + hunits) - 1e-9:
                self._lv_undo(lvfee, imp)
                self._refuse("coverage full")
        elif self.cash_H + dH - hedge_cost < h * need - 1e-9:
            self._lv_undo(lvfee, imp)
            self._refuse("coverage full")
        self.cash_E += dE
        self.cash_H += dH
        self._fee(q * pr * p.buy_fee)
        if gapfee:
            self._to_pools(q * pr * gapfee)
        if p.impact_payer == "meadow":
            self.impact_meadow += imp
        self.supply += q
        if hunits > 0:
            usd2, fee2, imp2 = self._lv(hunits)
            self.cash_H -= usd2 + fee2 + imp2
            self.hedge_costs += fee2 + imp2
            self.hedge_units += hunits
        return q

    def _lv_undo(self, fee, imp):
        self.lv_fees -= fee
        self.impact_paid -= imp

    def sell(self, q):
        """Sells are never refused while the price is fresh. Returns USDC to the seller."""
        p = self.p
        q = min(q, self.supply)
        if q <= 0:
            return 0.0
        if self.status in ("CROWNED", "KNOCKED_OUT"):
            pay = q * self.claim
            self.end_reserve -= pay
            fee = pay * p.sell_fee
            self._fee(fee)
            self.supply -= q
            return pay - fee
        if self.status == "ENDING":
            self._refuse("ending: waiting for base sale")
        if not self.fresh:
            self._refuse("stale price")
        pr, x = self.price(), self.x
        units = q / self.nav0
        usd, lvfee, imp = self._lv(-units)
        proceeds = usd - lvfee - imp
        holder_share = min(pr, x) / x if x > 0 else 0.0   # part of the base that is the holder's
        holder_cost = lvfee * holder_share + (imp * holder_share if p.impact_payer == "transactor" else 0.0)
        hf = self.h * (p.B - 1) * q * x * p.lv_exit if p.hedge_fee else 0.0
        fee = q * pr * p.sell_fee
        hf = min(hf, max(0.0, q * pr - fee - holder_cost))   # never charge more than the seller is owed
        payout = q * pr - fee - holder_cost - hf
        if payout < 0:
            self.violations.append(f"negative payout {payout:.6f}")
            payout = 0.0
        pool_delta = proceeds - payout - fee - hf
        need_after = self.coverage_needed(self.supply - q)
        self.cash_H += hf
        self._to_pools(pool_delta)
        self._fee(fee)
        if p.impact_payer == "meadow":
            self.impact_meadow += imp
        self.supply -= q
        if p.hedge_credit and self.hedge_units > 0:
            # the sold tickets' hedge is sold with them
            u = min(self.hedge_units, max(0.0, self.hedge_units - self.hedge_target()))
            if u > 0:
                usd2, fee2, imp2 = self._lv(-u)
                self.cash_H += usd2 - fee2 - imp2
                self.hedge_costs += fee2 + imp2
                self.hedge_units -= u
        if self.cash_H < -1e-6 or self.cash_E < -1e-6:
            self.violations.append(f"sell drove a pool negative H={self.cash_H:.2f} E={self.cash_E:.2f}")
        return payout

    # ------------------------------------------------------------ LPs
    def eq_per_share(self, pool):
        tot = sum(self.shares[pool].values())
        return self.equity(pool) / tot if tot > 0 else 1.0

    def deposit(self, pool, usdc, owner):
        self.q_dep.append((pool, usdc, owner))

    def withdraw(self, pool, owner, frac=1.0):
        self.q_wd.append((pool, owner, frac))

    def _apply_lp(self):
        for pool, usdc, owner in self.q_dep:
            sh = usdc / max(self.eq_per_share(pool), 1e-9)
            self.shares[pool][owner] = self.shares[pool].get(owner, 0.0) + sh
            self.locked[pool][owner] = self.step + self.p.deposit_lock
            self.lp_flow[owner] = self.lp_flow.get(owner, 0.0) + usdc
            if pool == "H":
                self.cash_H += usdc
            else:
                self.cash_E += usdc
        self.q_dep = []
        keep = []
        for pool, owner, frac in self.q_wd:
            if self.locked[pool].get(owner, -1) > self.step:
                keep.append((pool, owner, frac))
                continue
            sh = self.shares[pool].get(owner, 0.0) * frac
            if sh <= 0:
                continue
            want = sh * self.eq_per_share(pool)
            amt = max(0.0, min(want, self.free(pool)))
            if want <= 0:
                continue
            used = sh * amt / want
            self.shares[pool][owner] -= used
            if pool == "H":
                self.cash_H -= amt
            else:
                self.cash_E -= amt
            self.lp_flow[owner] = self.lp_flow.get(owner, 0.0) - amt
            if amt < want - 1e-6:
                keep.append((pool, owner, 1.0))   # rest waits for free capital
        self.q_wd = keep

    def lp_value(self, owner):
        v = 0.0
        for pool in "HE":
            v += self.shares[pool].get(owner, 0.0) * self.eq_per_share(pool)
        return v

    def lp_pnl(self, owner):
        return self.lp_value(owner) - self.lp_flow.get(owner, 0.0)

    # ------------------------------------------------------------ updates
    def update(self, nav, fresh=True):
        """One price update. fresh=False: the feed is stale (nav ignored, nothing fills)."""
        self.step += 1
        self.fresh = fresh
        if not fresh:
            return
        prev = self.nav
        self.nav = max(nav, 1e-12)
        self.moves.append(abs(self.nav / prev - 1))
        if self.status == "ENDING" and self.step >= self.pending[0]:
            self._settle_end()
        if self.status == "LIVE":
            x = self.x
            self.above = self.above + 1 if x >= self.p.x_ceiling else 0
            self.below = self.below + 1 if x <= self.p.x_stop else 0
            if self.above >= self.p.crown_confirm:
                self._trigger("CROWN")
            elif self.below >= self.p.ko_confirm:
                self._trigger("KNOCKOUT")
            else:
                if self.p.share_mode == "prorata":
                    self._reshare()
                self._rehedge()
        self._apply_lp()
        self._check()

    def _reshare(self):
        eH, eE = self.equity("H"), self.equity("E")
        if eH <= 0 or eE <= 0:
            return
        target = eH / (eH + eE)
        d = target - self.h
        if abs(d) < self.p.share_band:
            return
        # Hearth takes d more of every token's boost; Ember pays it that value
        val = d * self.liability()
        newh = self.h + d
        need = self.coverage_needed()
        if self.cash_H + val - self.hedge_short_cost(h=newh) < newh * need or \
           self.cash_E - val < (1 - newh) * need:
            return
        self.cash_H += val
        self.cash_E -= val
        self.h = newh

    def _rehedge(self):
        target = self.hedge_target()
        diff = target - self.hedge_units
        if abs(diff) < 1e-15:
            return
        if target > 0 and abs(diff) <= self.p.hedge_band * target:
            return
        if diff > 0:
            unit_cost = self.nav * (1 + self.p.lv_mint) * (1 + self._impact(diff * self.nav))
            if self.p.hedge_credit:
                k = self._credit_per_unit()
                room = self.cash_H - self.hearth_need()
                maxu = diff if unit_cost <= k else max(0.0, room) / (unit_cost - k)
                maxu = min(maxu, max(0.0, self.cash_H) / unit_cost)
            else:
                spendable = self.cash_H - self.h * self.coverage_needed()
                maxu = max(0.0, spendable) / unit_cost
            if maxu < diff:
                self.unhedged_updates += 1
                diff = maxu
            if diff <= 0:
                return
            usd, fee, imp = self._lv(diff)
            self.cash_H -= usd + fee + imp
        else:
            usd, fee, imp = self._lv(diff)
            self.cash_H += usd - fee - imp
        self.hedge_costs += fee + imp
        self.hedge_units += diff

    def _trigger(self, kind):
        self.status = "ENDING"
        self.end_kind = kind
        base_units = self.supply / self.nav0
        self.pending = (self.step + self.p.sale_delay, base_units, self.hedge_units, kind, self.x)
        self.log.append((kind, self.step, self.x))
        if self.p.sale_delay == 0:
            self._settle_end()

    def _settle_end(self):
        _, base_units, hedge_units, kind, x_trig = self.pending
        p = self.p
        usd, fee, imp = self._lv(-base_units) if base_units else (0.0, 0.0, 0.0)
        proceeds = usd - fee - imp
        S = self.supply
        if p.hedge_credit and hedge_units:
            # Hearth sells its hedge first: that is what pays its share of the Crown
            usd2, fee2, imp2 = self._lv(-hedge_units)
            self.cash_H += usd2 - fee2 - imp2
            self.hedge_costs += fee2 + imp2
            self.hedge_units = 0.0
            hedge_units = 0.0
        if kind == "CROWN":
            if p.crown_mode == "fixed_C":
                owed = S * p.C
                pool_pays = owed - proceeds
            elif p.crown_mode == "capped":
                # holders get at most C; the Meadow pays at most the covered boost;
                # any overshoot above C goes to the Meadow (offsets stop-loss gaps)
                fb = S * (p.B - 1) * (p.x_ceiling - 1)
                pool_pays = min(fb, S * p.C - proceeds)
                owed = proceeds + pool_pays
            else:
                pool_pays = S * (p.B - 1) * (p.x_ceiling - 1)
                owed = proceeds + pool_pays
            if pool_pays > self.cash + 1e-6:
                self.violations.append(f"Crown: Meadow owes {pool_pays:.2f}, holds {self.cash:.2f}")
            self._to_pools(-pool_pays)
            self.claim = owed / S if S else 0.0
            self.status = "CROWNED"
        else:
            xs = self.nav / self.nav0
            per = max(0.0, 1 + p.B * (xs - 1))            # what is left for holders at the sale price
            owed = min(S * per, proceeds)
            self._to_pools(proceeds - owed)
            ideal = S * p.x_stop
            self.gap_loss += max(0.0, ideal - S * xs)
            self.claim = owed / S if S else 0.0
            self.status = "KNOCKED_OUT"
        self.end_reserve += owed
        if hedge_units:
            usd, fee, imp = self._lv(-hedge_units)
            self.cash_H += usd - fee - imp
            self.hedge_costs += fee + imp
            self.hedge_units = 0.0
        self.pending = None

    def _check(self):
        if self.cash_H < -1e-6 or self.cash_E < -1e-6:
            self.violations.append(f"pool negative H={self.cash_H:.2f} E={self.cash_E:.2f}")
        if self.status == "LIVE":
            need = self.coverage_needed()
            if self.cash_E + 1e-6 < (1 - self.h) * need or self.cash_H + 1e-6 < self.hearth_need():
                self.violations.append("coverage broken")
        if self.end_reserve < -1e-6:
            self.violations.append("end reserve negative")
