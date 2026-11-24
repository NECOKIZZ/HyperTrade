"""Closed-form checks of the engine against the spec's worked example (§14)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from engine2 import Market, Params, Refused

NOFEE = dict(buy_fee=0, sell_fee=0, lv_mint=0, lv_exit=0, hedge_band=0)


def mk(h, nav0=10.0, cash=100.0, **kw):
    p = Params(hearth_share=h, **{**NOFEE, **kw})
    m = Market(nav0=nav0, p=p, cash_H=cash * h, cash_E=cash * (1 - h))
    return m


def close(a, b, tol=1e-6):
    assert abs(a - b) < tol, (a, b)


def run_case(h, path, expect_alice, expect_lp):
    # Hearth-only needs coverage + hedge money: give it $200, Ember $100
    cash = 200.0 if h == 1 else 100.0
    m = mk(h, cash=cash)
    q = m.buy(100.0)
    close(q, 100.0)
    m.update(m.nav)  # put the hedge on
    for nav in path:
        m.update(nav)
    alice = m.sell(q)
    lp = m.equity("H") + m.equity("E") - cash
    close(alice, expect_alice)
    close(lp, expect_lp)
    assert not m.violations, m.violations
    return m


def test_worked_example():
    # 0xWhale +10%: Alice $120. Bob (hedged) $0, Carol (unhedged) -$10
    run_case(1, [11.0], 120, 0)
    run_case(0, [11.0], 120, -10)
    # -20%: Alice $60. Bob 0, Carol +20
    run_case(1, [8.0], 60, 0)
    run_case(0, [8.0], 60, 20)
    # +100%: Crowned at $3 -> Alice $300. Bob 0, Carol -100
    m = run_case(1, [20.0], 300, 0); assert m.status == "CROWNED"
    run_case(0, [20.0], 300, -100)
    # -50%: Knocked out -> Alice $0. Bob 0, Carol +50
    m = run_case(1, [5.0], 0, 0); assert m.status == "KNOCKED_OUT"
    run_case(0, [5.0], 0, 50)
    # Gap: falls straight to -55%. Alice 0, Bob loses the gap on base + hedge (-$10), Carol +45
    m = run_case(1, [4.5], 0, -10)
    close(m.gap_loss, 5.0)
    run_case(0, [4.5], 0, 45)


def test_late_buyer_ed():
    m = mk(0, cash=1000.0)
    m.buy(100.0)
    m.update(12.0)            # whale +20% since launch, price 1.40
    close(m.price(), 1.40)
    q = m.buy(140.0)
    close(q, 100.0)
    close(m.effective_boost(), 2 * 1.2 / 1.4)
    m.update(13.2)            # +10% from Thursday
    close(m.sell(q), 164.0)   # Ed +17%
    m2 = mk(0, cash=1000.0); m2.buy(100.0); m2.update(12.0); q = m2.buy(140.0)
    m2.update(10.8)           # -10% from Thursday
    close(m2.sell(q), 116.0)  # Ed -17%


def test_start_at_one_equals_mirroring():
    """Starting at $1 vs starting at the LiquidV price is the same product in different units."""
    for nav0 in (1.0, 1.4212):
        m = mk(0, nav0=nav0, cash=1000.0)
        m.buy(100.0)
        m.update(nav0 * 1.1)
        assert abs(m.equity("E") - 1000.0 + 10.0) < 1e-6


def test_coverage_refuses_mint():
    m = mk(0, cash=100.0)
    m.buy(100.0)             # 100 tokens need $100 of coverage: full
    try:
        m.buy(1.0); raise AssertionError("should refuse")
    except Refused as e:
        assert "coverage" in str(e)


def test_mint_limit_near_stop():
    m = mk(0, cash=10_000.0)
    m.buy(100.0)
    m.update(5.6)            # x=0.56, price 0.12, live boost 9.3x
    try:
        m.buy(100.0); raise AssertionError("should refuse")
    except Refused as e:
        assert "mint limit" in str(e)
    assert m.sell(50) >= 0   # selling still works




def test_near_zero_sell_v1_bug():
    """v1 charged the seller LiquidV's exit fee on the whole base, even the part that
    belongs to the Meadow. Near the stop-loss that made the payout negative."""
    import engine as e1
    m = e1.Market(nav0=10.0, p=e1.Params(hearth_share=0.5), cash_H=5000, cash_E=5000)
    q = m.buy(100.0); m.update(10.0)
    m.update(5.0001)                      # x just above the stop, price ~$0.00002
    v1 = m.sell(q)
    m2 = Market(nav0=10.0, p=Params(hearth_share=0.5), cash_H=5000, cash_E=5000)
    q2 = m2.buy(100.0); m2.update(10.0); m2.update(5.0001)
    v2 = m2.sell(q2)
    print(f"   near-zero sell: v1 payout {v1:.4f}, v2 payout {v2:.6f}")
    assert v1 < 0 and v2 >= 0 and not m2.violations


def test_fixed_boost_unconfirmed_crown_pays_real_value():
    """Above the max but before the Crown confirms, a seller must get base + capped boost, not $3."""
    m = Market(nav0=1.0, p=Params(crown_confirm=2, **NOFEE), cash_H=0.0, cash_E=1000.0)
    m.p.hearth_share = 0.0; m.h = 0.0
    q = m.buy(100.0)
    m.update(2.2)                      # real token +120%, max is at +100%
    assert m.status == "LIVE"
    close(m.sell(q), 100 * (2.2 + 1.0))   # $3.20 a ticket: $2.20 real + $1.00 boost
    assert not m.violations


def test_spec_v05_worked_example_new_rules():
    """§14 rows under the final rules: stop $0.25, fixed-boost Crown (no confirmation needed for exact jumps)."""
    def case(h, path, alice, lp):
        cash = 200.0 if h == 1 else 100.0
        p = Params(hearth_share=h, stop_price=0.25, **NOFEE)
        m = Market(nav0=10.0, p=p, cash_H=cash * h, cash_E=cash * (1 - h))
        q = m.buy(100.0); m.update(10.0)
        for nav in path:
            m.update(nav)
        close(m.sell(q), alice)
        close(m.equity("H") + m.equity("E") - cash, lp)
        assert not m.violations, m.violations
    case(1, [6.25], 25, 0); case(0, [6.25], 25, 37.5)          # stop exactly at -37.5%
    case(1, [5.5], 10, 0); case(0, [5.5], 10, 45)              # gap to -45%: cushion takes it
    case(1, [4.0], 0, -20); case(0, [4.0], 0, 40)              # gap past $0
    case(1, [21.0], 310, 10); case(0, [21.0], 310, -100)       # overshoot to +110%



def test_hedge_credit_halves_hearth_cash():
    """2x, max $3: a hedged Hearth needs the hedge ($100) but not another $100 of cover."""
    P = dict(B=2.0, C=3.0, stop_price=0.25, ko_confirm=2, crown_mode="fixed_boost", crown_confirm=2,
             hearth_share=1.0, lv_mint=0.0, lv_exit=0.0, buy_fee=0.0, sell_fee=0.0, hedge_band=0.0)
    old = Market(nav0=1.0, p=Params(**P), cash_H=110.0, cash_E=0.0)
    try:
        old.buy(100.0)
        assert False, "old rule should need $200"
    except Refused:
        pass
    m = Market(nav0=1.0, p=Params(hedge_credit=True, **P), cash_H=110.0, cash_E=0.0)
    q = m.buy(100.0)
    assert abs(q - 100.0) < 1e-9 and abs(m.hedge_units - 100.0) < 1e-9
    m.update(2.0); m.update(2.0)              # doubled for 2 updates: Crowned
    assert m.status == "CROWNED", m.status
    assert abs(m.claim - 3.0) < 1e-9, m.claim  # real base $2 + max boost $1
    assert not m.violations, m.violations
    assert abs(m.cash_H - (10.0 + 200.0 - 100.0)) < 1e-6, m.cash_H   # $10 left after the hedge; hedge sold $200, paid $100

if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn(); print("PASS", name)
