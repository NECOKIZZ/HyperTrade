"""Round 3: fairness bugs. Not attacks: places where the rules themselves make an honest
holder or LP lose money they were owed, or stop them being paid.

Usage: python3 -I sim/fairness.py <data_dir> <report_path>
"""
import sys, os, json, glob, random, statistics, zlib, copy, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from engine2 import Market, Params, Refused, INF
import engine as e1

DATA, REPORT = sys.argv[1], sys.argv[2]
POOL = 25_000.0
OUT = []
w = OUT.append


def rng_for(*k):
    return random.Random(zlib.crc32("|".join(map(str, k)).encode()))


def load():
    paths = {}
    for f in sorted(glob.glob(os.path.join(DATA, "tok_*.json"))):
        d = json.load(open(f))
        h = [x["backingPerToken"] for x in d.get("history", []) if x.get("backingPerToken")]
        if len(h) >= 100 and max(h) != min(h):
            paths[d["token"]["ticker"]] = h
    return paths


def table(header, rows):
    w("| " + " | ".join(header) + " |")
    w("|" + "---|" * len(header))
    for r in rows:
        w("| " + " | ".join(str(c) for c in r) + " |")
    w("")


def f0(x):
    return f"{x:,.0f}"


def f2(x):
    return f"{x:,.2f}"


def buy(m, usd):
    try:
        return m.buy(usd)
    except Refused:
        return 0.0


# ---------------------------------------------------------------- 1. real data: who loses at the edges
def mean0(v):
    return statistics.mean(v) if v else 0.0


def max0(v):
    return max(v) if v else 0.0


def r1_edges(paths, C=3.0):
    if C == 3.0:
        w("## 1. Real LiquidV data: what the stop-loss and the max price take from each side\n")
    if C == 3.0:
      w("Launch a $1.00 ticket (B = 2, max $3, stop $0) at EVERY update of all 18 real LiquidV histories "
      "and follow it until it ends. At LiquidV's real update speed (every 7–23 minutes) the price can jump "
      "past either edge in one update:\n"
      "- **Past the stop (gap):** the holder is floored at $0, so the LPs collect less than the stop promised them. Honest LPs lose.\n"
      "- **Past the max (overshoot):** the real token inside is worth more than the edge. Who keeps the extra depends "
      "on the Crown rule: holders ('fixed boost') or LPs ('capped').\n")
    B = 2.0
    xk, xc = 0.5, 1 + (C - 1) / B
    w(f"**Max price ${C:.0f}** (max hit when the real token is up {100*(xc-1):.0f}% since launch):\n")
    rows = []
    tot = dict(launch=0, ko=0, crown=0, gap=[], over=[], wick=0)
    for t, h in paths.items():
        ko = cr = 0
        gaps, overs = [], []
        wick = 0
        for i in range(len(h) - 1):
            x0 = h[i]
            for j in range(i + 1, len(h)):
                x = h[j] / x0
                if x <= xk:
                    ko += 1
                    gaps.append(xk - x)          # per $1 ticket the LPs did not collect
                    if j + 1 < len(h) and h[j + 1] / x0 > xk:
                        wick += 1                # back above the stop the very next update
                    break
                if x >= xc:
                    cr += 1
                    overs.append(x - xc)         # real-token value above the max
                    break
        n = len(h) - 1
        tot["launch"] += n
        tot["ko"] += ko
        tot["crown"] += cr
        tot["gap"] += gaps
        tot["over"] += overs
        tot["wick"] += wick
        if ko or cr:
            rows.append((t, n, ko, cr, f2(statistics.mean(gaps)) if gaps else "–", f2(max(gaps)) if gaps else "–",
                         f2(statistics.mean(overs)) if overs else "–", f2(max(overs)) if overs else "–", wick))
    table(["Token", "Launch points", "Hit stop", "Hit max", "Avg gap $/ticket", "Worst gap", "Avg overshoot $/ticket",
           "Worst overshoot", "Stop hits that bounced back next update"], rows)
    g, o = tot["gap"], tot["over"]
    w(f"All tokens: {tot['launch']:,} launch points, **{tot['ko']:,} stop hits** "
      f"(average gap ${mean0(g):.3f} per $1 ticket, worst ${max0(g):.2f}), **{tot['crown']:,} max-price hits** "
      f"(average overshoot ${mean0(o):.3f}, worst ${max0(o):.2f}). {tot['wick']:,} stop hits "
      f"({100*tot['wick']/max(tot['ko'],1):.0f}%) were back above the stop the very next update.\n")
    return tot


# ---------------------------------------------------------------- 2. can everyone be paid at once?
def r2_everyone_exits(paths):
    w("## 2. Can every holder AND every LP be paid in full, at any moment?\n")
    w("At 40 random moments in each real history (with random retail trading and LP deposits and "
      "withdrawals running), freeze a copy of the market and make **every holder sell everything**, then "
      "**every LP withdraw everything**. Checks: every holder gets exactly price × tokens minus the disclosed "
      "fees, no pool goes negative, and LPs get back their marked value.\n")
    checks = bad_hold = bad_lp = 0
    worst_hold = worst_lp = 0.0
    lp_short = []
    for t, h in paths.items():
        m = Market(nav0=h[0], p=Params(stop_price=0.25, ko_confirm=2, crown_mode="capped", crown_confirm=2),
                   cash_H=POOL, cash_E=POOL)
        r = rng_for("exit", t)
        tokens = 0.0
        moments = set(r.sample(range(5, len(h)), 40))
        for i, nav in enumerate(h):
            if m.status == "LIVE" and r.random() < 0.4:
                tokens += buy(m, 300 * r.lognormvariate(0, 1))
            if r.random() < 0.3 and tokens > 0:
                try:
                    m.sell(tokens * 0.1); tokens *= 0.9
                except Refused:
                    pass
            if r.random() < 0.05:
                m.deposit(r.choice("HE"), r.uniform(1000, 10000), f"lp{r.randrange(3)}")
            if r.random() < 0.05:
                m.withdraw(r.choice("HE"), f"lp{r.randrange(3)}", r.random())
            m.update(nav)
            if i in moments and m.status == "LIVE":
                c = copy.deepcopy(m)
                checks += 1
                pr, x = c.price(), c.x
                expect = tokens * pr
                got = c.sell(tokens) if tokens else 0.0
                fees = expect - got
                # disclosed fees: Asphodel sell fee + LiquidV exit on the holder's base + hedge fee
                max_fees = tokens * (pr * c.p.sell_fee + min(pr, x) * c.p.lv_exit
                                     + c.h * (c.p.B - 1) * x * c.p.lv_exit) + 1e-6
                if fees > max_fees or c.violations:
                    bad_hold += 1
                worst_hold = max(worst_hold, fees - max_fees)
                # every LP withdraws everything
                c.update(c.nav)
                for pool in "HE":
                    for owner in list(c.shares[pool]):
                        c.withdraw(pool, owner, 1.0)
                vals = {o: c.lp_value(o) for o in set(c.shares["H"]) | set(c.shares["E"])}
                c.update(c.nav)
                c.update(c.nav)
                left = sum(c.lp_value(o) for o in vals)
                lp_short.append(left)
                if c.cash_H < -1e-6 or c.cash_E < -1e-6 or c.violations:
                    bad_lp += 1
    w(f"**{checks} full-exit checks.** Holders short-changed: **{bad_hold}**. Pools negative or broken: **{bad_lp}**. "
      f"LP value still stuck in the pool after every holder left and every LP asked to withdraw: "
      f"max ${max(lp_short):,.2f}.\n")


# ---------------------------------------------------------------- 3. LP value that can't be withdrawn
def r3_lp_liquidity(paths):
    w("## 3. LPs: value you own but can't withdraw yet\n")
    w("An LP's share is marked to market, but only **free capital** can leave. Two things lock value: "
      "coverage for holders' possible winnings, and the LPs' own unrealized gains when holders are losing "
      "(that gain sits inside the real token in the vault, not in cash, until holders sell or are stopped out). "
      "Over normal trading on the real histories, how much of an LP's marked value could actually be withdrawn?\n")
    rows = []
    for t, h in paths.items():
        m = Market(nav0=h[0], p=Params(), cash_H=POOL, cash_E=POOL)
        r = rng_for("liq", t)
        tokens = 0.0
        ratios = {"H": [], "E": []}
        for nav in h:
            if m.status == "LIVE" and r.random() < 0.4:
                tokens += buy(m, 300 * r.lognormvariate(0, 1))
            if r.random() < 0.3 and tokens > 0:
                try:
                    m.sell(tokens * 0.1); tokens *= 0.9
                except Refused:
                    pass
            m.update(nav)
            if m.status != "LIVE":
                break
            for pool in "HE":
                eq = m.equity(pool)
                if eq > 0:
                    ratios[pool].append(max(0.0, m.free(pool)) / eq)
        rows.append((t, f"{100*statistics.mean(ratios['H']):.0f}%", f"{100*min(ratios['H']):.0f}%",
                     f"{100*statistics.mean(ratios['E']):.0f}%", f"{100*min(ratios['E']):.0f}%"))
    table(["Token", "Hearth: avg withdrawable", "Hearth: lowest", "Ember: avg withdrawable", "Ember: lowest"], rows)


# ---------------------------------------------------------------- 4. fees that overcharge near the stop
def r4_fee_overcharge():
    w("## 4. Fees near the stop: is anyone charged for money that isn't theirs?\n")
    w("Near the stop, most of the real token inside a ticket belongs to the LPs, not the holder (the holder's "
      "share is the ticket price). Total cost of a $100 buy and of selling it straight back, as % of the "
      "money moved. v1 charged LiquidV's fees on the WHOLE base; v2 charges the holder only on their part.\n")
    rows = []
    for xv in (1.0, 0.8, 0.7, 0.6, 0.55, 0.51):
        pr = 1 + 2 * (xv - 1)
        res = []
        for E in ("v1", "v2"):
            if E == "v1":
                m = e1.Market(nav0=1.0, p=e1.Params(mint_boost_limit=INF), cash_H=1e6, cash_E=1e6)
            else:
                m = Market(nav0=1.0, p=Params(mint_boost_limit=INF), cash_H=1e6, cash_E=1e6)
            m.update(xv)
            try:
                q = m.buy(100.0)
            except Exception:
                res.append(("refused", "–"))
                continue
            buy_cost = 100 - q * pr
            back = m.sell(q)
            rt = 100 - back
            res.append((f"{buy_cost:.2f}%", f"{rt:.2f}%"))
        rows.append((f"${pr:.2f}", f"{2*xv/pr:.1f}x", res[0][0], res[1][0], res[0][1], res[1][1]))
    table(["Ticket price", "Live boost", "Buy cost v1", "Buy cost v2", "Round trip v1", "Round trip v2"], rows)


# ---------------------------------------------------------------- 5. LP churn under a pro-rata split
def r5_churn(paths):
    w("## 5. Ordinary LPs coming and going: who pays for it?\n")
    w("No attacker: a handful of normal Ember LPs deposit and withdraw a few thousand dollars at random "
      "(a few times a day). If the Hearth/Ember split follows pool capital, every change resizes Hearth's "
      "hedge, and **Hearth's LPs pay LiquidV's fee for other people's deposits**.\n")
    rows = []
    for mode in ("fixed", "prorata"):
        extra, dh = [], []
        for t, h in paths.items():
            res = []
            for churn in (False, True):
                m = Market(nav0=h[0], p=Params(share_mode=mode), cash_H=POOL, cash_E=POOL)
                r = rng_for("churn", t)
                rc = rng_for("churn-lp", t)
                tokens = 0.0
                for nav in h:
                    if m.status == "LIVE" and r.random() < 0.4:
                        tokens += buy(m, 300 * r.lognormvariate(0, 1))
                    if r.random() < 0.3 and tokens > 0:
                        try:
                            m.sell(tokens * 0.1); tokens *= 0.9
                        except Refused:
                            pass
                    if churn and rc.random() < 0.08:
                        if rc.random() < 0.5:
                            m.deposit("E", rc.uniform(2000, 8000), f"e{rc.randrange(5)}")
                        else:
                            m.withdraw("E", f"e{rc.randrange(5)}", 1.0)
                    m.update(nav)
                res.append(m)
            base, ch = res
            extra.append(ch.hedge_costs - base.hedge_costs)
            dh.append(ch.shares["H"]["passive"] * ch.eq_per_share("H") - base.shares["H"]["passive"] * base.eq_per_share("H"))
        rows.append((mode, f0(statistics.mean(extra)), f0(max(extra)), f0(statistics.mean(dh)), f0(min(dh))))
    table(["Split", "Extra Hearth hedge cost avg $", "worst $", "Hearth LPs Δ avg $", "worst $"], rows)


# ---------------------------------------------------------------- 6. fast exits before a gap
def r6_fast_exit():
    w("## 6. Hearth LPs who leave fast vs LPs who stay, before a liquidation gap\n")
    w("Two equal Hearth LPs ($25,000 each). The hero drifts toward the stop; LP 'fast' withdraws when the "
      "price is within 15% of the stop (a public signal: the hero's liquidation price is visible). Then the "
      "hero is liquidated in one update. Withdrawals pay the **marked** value, and the mark doesn't price the "
      "risk of a gap, so whoever leaves first escapes the loss.\n")
    rows = []
    for rule, extra in (("plain mark", dict()),
                        ("exit haircut near the stop", dict())):
        m = Market(nav0=1.0, p=Params(), cash_H=50_000.0, cash_E=25_000.0)
        m.shares["H"] = {"fast": 25_000.0, "stay": 25_000.0}
        m.lp_flow = {"fast": 25_000.0, "stay": 25_000.0}
        buy(m, 20_000.0)
        m.update(1.0)
        nav = 1.0
        left = False
        for i in range(40):
            nav *= 0.985
            near = m.price() < 0.30 + 0.15
            if near and not left:
                if rule == "plain mark":
                    m.withdraw("H", "fast", 1.0)
                else:
                    # haircut: the leaver leaves behind the expected gap cost of their share
                    sh = m.shares["H"]["fast"]
                    tot = sum(m.shares["H"].values())
                    gap_cost = m.h * m.supply * (m.p.B - 1) * m.x * 0.5   # assume a 50% gap probability-weighted
                    m.shares["H"]["fast"] -= sh * (gap_cost * sh / tot) / max(m.equity("H") * sh / tot, 1e-9)
                    m.shares["H"]["stay"] += 0.0
                    m.withdraw("H", "fast", 1.0)
                left = True
            m.update(nav)
        m.update(nav * 0.02)                # liquidation
        m.update(m.nav)
        rows.append((rule, f0(m.lp_pnl("fast")), f0(m.lp_pnl("stay"))))
    table(["Rule", "'Fast' LP $", "'Stay' LP $"], rows)


# ---------------------------------------------------------------- 7. the Crown and the stop, rule by rule
def r7_edge_rules(paths, C=3.0):
    if C == 3.0:
        w("## 7. The Crown and the stop, rule by rule: who is paid what they were promised\n")
    if C == 3.0:
      w("On the real histories, every launch point that ends (stop or max), with real-speed gaps, under "
      "each rule. 'Promised' = $3 at the max; at the stop, the LPs were promised the base at the stop "
      "level. All figures per $1 ticket, averaged over every ended ticket.\n")
    B, xk = 2.0, 0.5
    xc = 1 + (C - 1) / B
    fb = (B - 1) * (xc - 1)
    w(f"**Max price ${C:.0f}:**\n")
    ends = []
    for t, h in paths.items():
        for i in range(len(h) - 2):
            x0 = h[i]
            for j in range(i + 1, len(h) - 1):
                x = h[j] / x0
                if x <= xk or x >= xc:
                    ends.append((x, h[j + 1] / x0))
                    break
    crowns = [e for e in ends if e[0] >= xc]
    kos = [e for e in ends if e[0] <= xk]
    rows = []
    for name, sale_next in (("sold the same update", False), ("sold one update later", True)):
        hold_fb, hold_cap, hold_C, lp_fb, lp_cap, lp_C = [], [], [], [], [], []
        for x_trig, x_next in crowns:
            xs = x_next if sale_next else x_trig
            # fixed boost: holder gets base + fb; LP pays fb
            hold_fb.append(xs + fb); lp_fb.append(-fb)
            pay = min(fb, C - xs)
            hold_cap.append(xs + pay); lp_cap.append(-pay)
            hold_C.append(C); lp_C.append(-(C - xs))
        if not crowns:
            continue
        rows.append((f"Max price, {name}", f2(statistics.mean(hold_C)), f2(statistics.mean(hold_fb)),
                     f2(statistics.mean(hold_cap)), f2(min(lp_C)), f2(-fb), f2(-fb)))
    if rows:
        table(["Event", f"Holder gets: 'exactly ${C:.0f}'", "Holder gets: 'fixed boost'", "Holder gets: 'capped'",
               f"LP pays, worst: 'exactly ${C:.0f}'", "LP pays, worst: 'fixed boost'", "LP pays, worst: 'capped'"], rows)
        need = max(C - x_next for _, x_next in crowns)
        w(f"{len(crowns):,} max-price hits and {len(kos):,} stop hits. LP coverage per ticket is ${fb:.2f}. "
          f"'Exactly ${C:.0f}' with the sale one update late needs up to ${need:.2f} per ticket"
          + (" — **more than the coverage locked, so somebody can't be paid.**" if need > fb + 1e-9 else ".") + "\n")
    else:
        w(f"No max-price hits in the real data at ${C:.0f}; {len(kos):,} stop hits.\n")
    if C != 3.0:
        return
    w("**Stop rules** (each stop has its own trigger; the LPs' promised take at the stop is the base minus "
      "what the holder keeps, at the trigger level):\n")
    rows = []
    for stop in (0.0, 0.25):
        xk_s = 1 + (stop - 1) / B
        promised = xk_s - stop                      # LPs' take per ticket if the stop fills exactly
        trig = []
        for t, h in paths.items():
            for i in range(len(h) - 2):
                x0 = h[i]
                for j in range(i + 1, len(h) - 1):
                    x = h[j] / x0
                    if x <= xk_s or x >= xc:
                        if x <= xk_s:
                            trig.append((x, h[j + 1] / x0))
                        break
        for name, sale_next, confirm in (("instant, sold the same update", False, False),
                                         ("needs 2 updates below", True, True)):
            hold, short, saved = [], [], 0
            for x_trig, x_next in trig:
                if confirm and x_next > xk_s:
                    saved += 1                       # bounced back: not knocked out
                    continue
                xs = x_next if sale_next else x_trig
                hv = max(0.0, 1 + B * (xs - 1))
                hold.append(hv)
                short.append(max(0.0, promised - (xs - hv)))
            rows.append((f"Stop ${stop:.2f}, {name}", len(trig), saved, f2(mean0(hold)), f2(max0(hold)),
                         f2(mean0(short)), f2(max0(short))))
    table(["Stop rule", "Stop hits", "Saved by bouncing back", "Holder keeps avg $", "best $",
           "LPs short of promised avg $", "worst $"], rows)


# ---------------------------------------------------------------- 8. sells while a Crown/stop settles
def r8_ending_window(paths):
    w("## 8. 'Sells always open' vs the moment a ticket ends\n")
    w("Between the stop/max firing and the base actually being sold, nobody can sell (the final value "
      "isn't known yet). How long is that window, and how often would a holder hit it?\n")
    rows = []
    for delay in (0, 1, 3):
        refused = attempts = 0
        for t, h in paths.items():
            m = Market(nav0=h[0], p=Params(sale_delay=delay, ko_confirm=2, stop_price=0.25), cash_H=POOL, cash_E=POOL)
            r = rng_for("end", t)
            tokens = buy(m, 2000.0)
            for nav in h:
                m.update(nav)
                if r.random() < 0.5 and tokens > 0:
                    attempts += 1
                    try:
                        m.sell(tokens * 0.01); tokens *= 0.99
                    except Refused:
                        refused += 1
        rows.append((delay, attempts, refused))
    table(["Base sale delay (updates)", "Sell attempts", "Refused (ticket ending)"], rows)


def main():
    t0 = time.time()
    paths = load()
    w("# Asphodel v0.5, round 3: fairness bugs\n")
    w("Not attacks. Each test asks: does an honest holder or LP ever lose money they were owed, or get "
      "stopped from being paid, because of how the rules work? Engine `sim/engine2.py`, 18 real LiquidV "
      "histories.\n")
    r1_edges(paths, 3.0)
    r1_edges(paths, 2.0)
    r7_edge_rules(paths, 3.0)
    r7_edge_rules(paths, 2.0)
    r2_everyone_exits(paths)
    r3_lp_liquidity(paths)
    r4_fee_overcharge()
    r5_churn(paths)
    r6_fast_exit()
    r8_ending_window(paths)
    w(f"_Run time {time.time()-t0:.0f} s._")
    open(REPORT, "w").write("\n".join(OUT) + "\n")
    print("\n".join(OUT))


if __name__ == "__main__":
    main()
