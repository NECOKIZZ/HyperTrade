"""Asphodel v0.5 boost-token engine.

One boost token on top of one LiquidV token ($vTRADER).
  x        = NAV_now / NAV_launch
  price    = clamp(1 + B*(x - 1), 0, C)           (starts at $1.00)
  base     = x per token, held as real $vTRADER (1/NAV_launch units per token)
  boost    = price - base, owed by (or to) the Meadow
The Meadow has two pools, Hearth (hedged with $vTRADER) and Ember (unhedged),
each backing a fixed share of every token's boost.
"""
from dataclasses import dataclass, field


@dataclass
class Params:
    B: float = 2.0               # real move + equal LP move
    C: float = 3.0               # max price (ceiling)
    buy_fee: float = 0.003       # Asphodel buy fee
    sell_fee: float = 0.003      # Asphodel sell fee
    lp_fee_share: float = 0.60   # share of Asphodel fees to LPs
    lv_mint: float = 0.01        # LiquidV mint fee (live: mintFeeBps 100)
    lv_exit: float = 0.003       # LiquidV exit fee (live: exitFeeBps 30)
    hedge_band: float = 0.05     # Hearth resizes its hedge only outside +-5%
    mint_boost_limit: float = 4.0  # Meadow stops minting above this live boost
    hearth_share: float = 0.5    # share of every boost backed by Hearth
    hedge_fee: bool = True       # buyers/sellers pay Hearth's LiquidV fee on its hedge

    @property
    def x_ceiling(self):
        return 1 + (self.C - 1) / self.B

    @property
    def x_stop(self):
        return 1 - 1 / self.B

    @property
    def max_liab(self):  # most the Meadow can ever owe per token, incl. exit fee at Crown
        return (self.B - 1) * (self.C - 1) / self.B + self.x_ceiling * self.lv_exit


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
    status: str = "LIVE"          # LIVE, CROWNED, KNOCKED_OUT
    crown_reserve: float = 0.0    # USDC held for Crowned tokens at C each
    nav: float = 0.0
    # accounting
    fees_lp_H: float = 0.0
    fees_lp_E: float = 0.0
    fees_protocol: float = 0.0
    lv_fees_paid: float = 0.0
    hedge_costs: float = 0.0
    gap_loss: float = 0.0
    flow_in: float = 0.0          # base units minted this step
    flow_out: float = 0.0         # base units redeemed this step
    nettable_units: float = 0.0
    unhedged_updates: int = 0
    gross_units: float = 0.0
    violations: list = field(default_factory=list)
    log: list = field(default_factory=list)

    def __post_init__(self):
        self.nav = self.nav0
        self.H0, self.E0 = self.cash_H, self.cash_E

    # ---- pricing -------------------------------------------------------
    @property
    def x(self):
        return self.nav / self.nav0

    def price(self, x=None):
        if self.status == "CROWNED":
            return self.p.C
        if self.status == "KNOCKED_OUT":
            return 0.0
        x = self.x if x is None else x
        return min(max(1 + self.p.B * (x - 1), 0.0), self.p.C)

    def boost_part(self):
        return self.price() - self.x

    def effective_boost(self):
        pr = self.price()
        return float("inf") if pr <= 0 else self.p.B * self.x / pr

    @property
    def base_units(self):
        return self.supply / self.nav0 if self.status == "LIVE" else 0.0

    def coverage_needed(self, supply=None):
        s = self.supply if supply is None else supply
        return s * self.p.max_liab if self.status == "LIVE" else 0.0

    @property
    def cash(self):
        return self.cash_H + self.cash_E

    def hedge_target(self, supply=None):
        s = self.supply if supply is None else supply
        if self.status != "LIVE":
            return 0.0
        return self.p.hearth_share * s * (self.p.B - 1) / self.nav0

    def hedge_shortfall_cost(self, supply=None):
        short = max(0.0, self.hedge_target(supply) - self.hedge_units)
        return short * self.nav * (1 + self.p.lv_mint)

    def free(self, pool):
        h = self.p.hearth_share
        if pool == "H":
            return self.cash_H - h * self.coverage_needed() - self.hedge_shortfall_cost()
        return self.cash_E - (1 - h) * self.coverage_needed()

    def equity(self, pool):
        """Mark-to-market LP equity (hedge valued at what it would redeem for)."""
        h = self.p.hearth_share
        share = h if pool == "H" else 1 - h
        liab = share * self.supply * self.boost_part() if self.status == "LIVE" else 0.0
        if pool == "H":
            return self.cash_H + self.hedge_units * self.nav * (1 - self.p.lv_exit) - liab
        return self.cash_E - liab

    # ---- LiquidV leg (mint/redeem base) --------------------------------
    def _lv_trade(self, units):
        """Mint (+) or redeem (-) $vTRADER at NAV, returns USDC cost (+) or proceeds (-)."""
        if units >= 0:
            fee = units * self.nav * self.p.lv_mint
        else:
            fee = -units * self.nav * self.p.lv_exit
        self.lv_fees_paid += fee
        return units * self.nav + fee

    def _split(self, amount):
        h = self.p.hearth_share
        self.cash_H += amount * h
        self.cash_E += amount * (1 - h)

    def _fee(self, amount):
        lp = amount * self.p.lp_fee_share
        h = self.p.hearth_share
        self.fees_lp_H += lp * h
        self.fees_lp_E += lp * (1 - h)
        self.cash_H += lp * h
        self.cash_E += lp * (1 - h)
        self.fees_protocol += amount - lp

    # ---- trading -------------------------------------------------------
    def buy(self, usdc):
        """Buyer spends `usdc`; returns tokens received. Raises Refused."""
        if self.status != "LIVE":
            raise Refused("not live")
        pr = self.price()
        if pr <= 0:
            raise Refused("at stop-loss")
        if self.effective_boost() > self.p.mint_boost_limit:
            raise Refused("live boost above mint limit")
        x = self.x
        # buyer pays price + Asphodel fee + LiquidV mint fee on the base
        per_token_cost = pr * (1 + self.p.buy_fee) + x * self.p.lv_mint
        q = usdc / per_token_cost
        h = self.p.hearth_share
        hedge_fee = h * (self.p.B - 1) * x * self.p.lv_mint if self.p.hedge_fee else 0.0
        if hedge_fee:
            per_token_cost += hedge_fee
            q = usdc / per_token_cost
        # coverage checked PER POOL, after the boost settlement and after Hearth pays its hedge
        boost_in = q * (pr - x)
        need = self.coverage_needed(self.supply + q)
        hedge_cost = self.hedge_shortfall_cost(self.supply + q)
        if self.cash_E + (1 - h) * boost_in < (1 - h) * need - 1e-9:
            raise Refused("coverage full (Ember)")
        if self.cash_H + h * boost_in + q * hedge_fee - hedge_cost < h * need - 1e-9:
            raise Refused("coverage full (Hearth, incl. hedge)")
        self._split(boost_in)
        self.cash_H += q * hedge_fee
        self._fee(q * pr * self.p.buy_fee)
        self._lv_trade(q / self.nav0)            # buyer's money buys the real base (+ fee)
        self.flow_in += q / self.nav0
        self.supply += q
        return q

    def sell(self, q):
        """Seller returns q tokens; returns USDC paid out. Never refused."""
        q = min(q, self.supply)
        if q <= 0:
            return 0.0
        if self.status == "CROWNED":
            pay = q * self.p.C * (1 - self.p.sell_fee)
            self.crown_reserve -= q * self.p.C
            self._fee(q * self.p.C * self.p.sell_fee)
            self.supply -= q
            return pay
        if self.status == "KNOCKED_OUT":
            self.supply -= q
            return 0.0
        pr, x = self.price(), self.x
        boost_out = q * (pr - x)
        if boost_out > self.cash + 1e-9:
            self.violations.append(f"sell could not be paid: owe {boost_out:.2f} cash {self.cash:.2f}")
        self._split(-boost_out)
        fee = q * pr * self.p.sell_fee
        self._fee(fee)
        proceeds = -self._lv_trade(-q / self.nav0)
        lv_fee = q * x - proceeds
        if self.p.hedge_fee:
            hf = self.p.hearth_share * (self.p.B - 1) * q * x * self.p.lv_exit
            self.cash_H += hf
            lv_fee += hf
        self.flow_out += q / self.nav0
        self.supply -= q
        return q * pr - fee - lv_fee

    # ---- LPs ---------------------------------------------------------------
    def withdraw(self, pool, amount):
        """LP withdrawal: free capital only. Returns amount actually paid."""
        amt = max(0.0, min(amount, self.free(pool)))
        if pool == "H":
            self.cash_H -= amt
        else:
            self.cash_E -= amt
        return amt

    # ---- each price update ------------------------------------------------
    def update(self, nav):
        # netting: units that could have been matched between buyers and sellers this step
        self.nettable_units += min(self.flow_in, self.flow_out)
        self.gross_units += self.flow_in + self.flow_out
        self.flow_in = self.flow_out = 0.0
        prev_eq_H = self.equity("H")
        self.nav = nav
        if self.status != "LIVE":
            return
        x = self.x
        if x >= self.p.x_ceiling:
            self._crown()
        elif x <= self.p.x_stop:
            self._knockout(prev_eq_H)
        else:
            self._rehedge()
        self._check()

    def _rehedge(self):
        h = self.p.hearth_share
        target = h * self.supply * (self.p.B - 1) / self.nav0
        diff = target - self.hedge_units
        if target == 0 and self.hedge_units == 0:
            return
        if target > 0 and abs(diff) <= self.p.hedge_band * target:
            return
        if diff > 0:
            # never spend coverage money on the hedge: buy only what free cash allows
            spendable = self.cash_H - h * self.coverage_needed()
            max_units = max(0.0, spendable) / (self.nav * (1 + self.p.lv_mint))
            if max_units < diff:
                self.unhedged_updates += 1
                diff = max_units
        if diff == 0:
            return
        cost = self._lv_trade(diff)
        fee = abs(diff) * self.nav * (self.p.lv_mint if diff > 0 else self.p.lv_exit)
        self.hedge_costs += fee
        self.cash_H -= cost
        self.hedge_units += diff

    def _close_hedge(self):
        if self.hedge_units:
            proceeds = -self._lv_trade(-self.hedge_units)
            self.hedge_costs += self.hedge_units * self.nav * self.p.lv_exit
            self.cash_H += proceeds
            self.hedge_units = 0.0

    def _crown(self):
        # sell the base, guarantee C per token, pay the boost from coverage
        base_units = self.supply / self.nav0
        proceeds = -self._lv_trade(-base_units)
        owed = self.supply * self.p.C
        self._split(proceeds - owed)          # pool pays (owed - proceeds)
        self.crown_reserve += owed
        self.status = "CROWNED"
        self._close_hedge()
        self.log.append(("CROWN", self.x))

    def _knockout(self, prev_eq_H):
        base_units = self.supply / self.nav0
        proceeds = -self._lv_trade(-base_units)
        # holders get 0; the base belongs to the Meadow
        self._split(proceeds)
        # gap = how much less the Meadow got than if the stop-loss had filled exactly at x_stop
        ideal = self.supply * self.p.x_stop
        self.gap_loss += max(0.0, ideal - self.supply * self.x)
        self.status = "KNOCKED_OUT"
        self._close_hedge()
        self.log.append(("KNOCKOUT", self.x))

    def _check(self):
        if self.status != "LIVE":
            return
        if self.cash + 1e-6 < self.coverage_needed():
            self.violations.append(f"coverage broken: cash {self.cash:.2f} < {self.coverage_needed():.2f}")
        pr = self.price()
        if not (-1e-12 <= pr <= self.p.C + 1e-12):
            self.violations.append(f"price out of bounds {pr}")
        if abs(pr - (self.x + self.boost_part())) > 1e-9:
            self.violations.append("price != base + boost")
