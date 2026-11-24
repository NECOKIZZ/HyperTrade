"""Try to break Asphodel v0.5 on LiquidV's live price histories.

Usage: python3 -I sim/run.py <data_dir> <report_path>
"""
import sys, os, json, glob, random, math, statistics, zlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from engine import Market, Params, Refused

DATA, REPORT = sys.argv[1], sys.argv[2]
POOL_H, POOL_E = 25_000.0, 25_000.0


def load():
    paths = {}
    meta = {}
    for f in sorted(glob.glob(os.path.join(DATA, "tok_*.json"))):
        d = json.load(open(f))
        h = [x["backingPerToken"] for x in d.get("history", []) if x.get("backingPerToken")]
        if len(h) < 100 or max(h) == min(h):
            continue
        t = d["token"]["ticker"]
        paths[t] = h
        meta[t] = dict(vault_usd=d["stageView"].get("vaultUsd") or 0.0)
    return paths, meta


def new_market(nav0, **kw):
    return Market(nav0=nav0, p=Params(**kw), cash_H=POOL_H, cash_E=POOL_E)


def retail_step(m, rng, stats):
    if m.status == "LIVE" and rng.random() < 0.4:
        try:
            q = m.buy(300 * rng.lognormvariate(0, 1))
            stats["paid_in"] += q * m.price()  # approx, fees tracked separately
            stats["holder_tokens"] += q
        except Refused as e:
            stats["refused"][str(e)] = stats["refused"].get(str(e), 0) + 1
    if rng.random() < 0.3 and m.supply > 0:
        q = m.supply * 0.10
        stats["paid_out"] += m.sell(q)


def summarize(m, extra=None):
    r = dict(
        status=m.status,
        violations=len(m.violations),
        hearth_pct=100 * (m.equity("H") - POOL_H) / POOL_H,
        ember_pct=100 * (m.equity("E") - POOL_E) / POOL_E,
        protocol_fees=m.fees_protocol,
        lv_fees=m.lv_fees_paid,
        hedge_costs=m.hedge_costs,
        gap_loss=m.gap_loss,
        nettable_usd=m.nettable_units * m.nav0,
        unhedged=m.unhedged_updates,
        netted_pct=100 * 2 * m.nettable_units / m.gross_units if m.gross_units else 0.0,
        violation_kinds=sorted(set(v.split(':')[0] for v in m.violations)),
    )
    if extra:
        r.update(extra)
    return r


# ---------------------------------------------------------------- scenarios
def scen_baseline(paths, seeds=10, launches=4, **kw):
    out = []
    for t, h in paths.items():
        for li in range(launches):
            start = li * len(h) // (launches + 1)
            for s in range(seeds):
                rng = random.Random(zlib.crc32(f"{t}|{li}|{s}".encode()))
                m = new_market(h[start], **kw)
                st = dict(paid_in=0.0, paid_out=0.0, holder_tokens=0.0, refused={})
                for nav in h[start:]:
                    retail_step(m, rng, st)
                    m.update(nav)
                if m.supply:
                    st["paid_out"] += m.sell(m.supply)
                out.append(dict(token=t, **summarize(m, dict(refused=sum(st["refused"].values())))))
    return out


def scen_fill_coverage(paths):
    """A whale fills the whole pool at launch, then holds to the end (or sells at the best moment)."""
    out = []
    for t, h in paths.items():
        m = new_market(h[0])
        bought = 0.0
        while True:
            try:
                bought += m.buy(1000.0)
            except Refused:
                break
        locked = 100 * m.coverage_needed() / (POOL_H + POOL_E)
        for nav in h:
            m.update(nav)
        payout = m.sell(m.supply)
        out.append(dict(token=t, tokens=bought, coverage_used=locked,
                        payout=payout, **summarize(m)))
    return out


def scen_cheap_tickets(paths, limit):
    """Buy as much as allowed whenever the ticket is under $0.30 (betting on a bounce)."""
    out = []
    for t, h in paths.items():
        m = new_market(h[0], mint_boost_limit=limit, C=3.0)
        spent = got = 0.0
        for nav in h:
            m.update(nav)
            if m.status == "LIVE" and 0 < m.price() < 0.30:
                try:
                    q = m.buy(2000.0); spent += 2000.0
                except Refused:
                    pass
        if m.supply:
            got = m.sell(m.supply)
        out.append(dict(token=t, spent=spent, got=got, **summarize(m)))
    return out


def scen_lp_run(paths, seeds=5):
    """Every step, both pools try to pull out everything they can. Retail keeps trading."""
    out = []
    for t, h in paths.items():
        for s in range(seeds):
            rng = random.Random(s)
            m = new_market(h[0])
            st = dict(paid_in=0.0, paid_out=0.0, holder_tokens=0.0, refused={})
            pulled = 0.0
            for i, nav in enumerate(h):
                retail_step(m, rng, st)
                if i > 10:
                    pulled += m.withdraw("H", 1e12) + m.withdraw("E", 1e12)
                m.update(nav)
            if m.supply:
                m.sell(m.supply)
            out.append(dict(token=t, pulled=pulled, **summarize(m)))
    return out


def scen_foresight(paths, fill_next):
    """Attacker knows the next price update before it lands (e.g. reads the whale live on
    Hyperliquid while our price source updates late). Round trip every step with $5k."""
    out = []
    for t, h in paths.items():
        m = new_market(h[0])
        pnl = 0.0
        for i in range(len(h) - 1):
            m.update(h[i])
            if m.status != "LIVE":
                break
            up = h[i + 1] > h[i] * 1.002
            if up:
                if fill_next:
                    m.update(h[i + 1])        # request fills at the next update's price
                    if m.status != "LIVE":
                        break
                try:
                    cost = 5000.0
                    q = m.buy(cost)
                    if not fill_next:
                        m.update(h[i + 1])
                    pnl += m.sell(q) - cost
                except Refused:
                    pass
        out.append(dict(token=t, attacker_pnl=pnl, **summarize(m)))
    return out


def scen_gap_stress(paths, mult):
    """Scale every single-update move by `mult` (bigger, faster crashes and pumps)."""
    out = []
    for t, h in paths.items():
        path = [h[0]]
        for a, b in zip(h, h[1:]):
            path.append(max(path[-1] * (1 + mult * (b / a - 1)), 1e-6))
        rng = random.Random(7)
        m = new_market(path[0])
        st = dict(paid_in=0.0, paid_out=0.0, holder_tokens=0.0, refused={})
        for nav in path:
            retail_step(m, rng, st)
            m.update(nav)
        if m.supply:
            m.sell(m.supply)
        out.append(dict(token=t, **summarize(m)))
    return out


def scen_fuzz(n=3000):
    """Random jumpy paths and random actions; count any invariant violation."""
    bad = 0
    kinds = {}
    events = dict(CROWNED=0, KNOCKED_OUT=0, LIVE=0)
    for k in range(n):
        rng = random.Random(1000 + k)
        nav = 1.0
        m = Market(nav0=nav, p=Params(B=rng.choice([1.5, 2, 3]), C=rng.choice([2, 3, 5]),
                                      hearth_share=rng.random()),
                   cash_H=rng.uniform(1e3, 5e4), cash_E=rng.uniform(1e3, 5e4))
        for _ in range(300):
            r = rng.random()
            try:
                if r < 0.35:
                    m.buy(rng.uniform(1, 5000))
                elif r < 0.6:
                    m.sell(m.supply * rng.random())
                elif r < 0.7:
                    m.withdraw(rng.choice("HE"), rng.uniform(0, 1e5))
            except Refused:
                pass
            jump = rng.gauss(0, 0.03) + (rng.choice([-0.5, -0.3, 0.3, 0.8]) if rng.random() < 0.01 else 0)
            nav = max(nav * (1 + jump), 1e-6)
            m.update(nav)
        if m.supply:
            m.sell(m.supply)
        if m.cash_H < -1e-6 or m.cash_E < -1e-6:
            m.violations.append("negative pool cash")
        bad += bool(m.violations)
        for v in set(x.split(':')[0] for x in m.violations):
            kinds[v] = kinds.get(v, 0) + 1
        events[m.status] += 1
    return dict(runs=n, runs_with_violations=bad, violation_kinds=kinds, **events)


# ---------------------------------------------------------------- report
def agg(rows, key):
    v = [r[key] for r in rows]
    return statistics.mean(v), min(v), max(v)


def fmt(x):
    return f"{x:,.2f}"


def main():
    paths, meta = load()
    L = []
    w = L.append
    w("# Asphodel v0.5: simulation on LiquidV's live prices\n")
    w(f"Data: {len(paths)} LiquidV tokens with a moving price, ~720 updates each (about 11 days, "
      f"one update every 7–23 minutes). Pools: Hearth ${POOL_H:,.0f}, Ember ${POOL_E:,.0f}. "
      "Boost token: real move + equal LP move (B = 2), max price $3, stop-loss $0. "
      "Fees: Asphodel 0.3% buy and sell; LiquidV 1% mint, 0.3% exit (their live settings).\n")

    nofee = scen_baseline(paths, hedge_fee=False)
    base = scen_baseline(paths)
    w("## 1. Normal trading (random buyers and sellers)\n")
    w(f"Hearth return WITHOUT the hedge fee (Hearth pays LiquidV's 1% itself): average "
      f"{statistics.mean(r['hearth_pct'] for r in nofee):.2f}%, worst {min(r['hearth_pct'] for r in nofee):.2f}%. "
      "Everything below is WITH the hedge fee (buyers pay it).\n")
    w(f"{len(base)} runs (each token, 4 launch dates, 10 random seeds).\n")
    w("| Metric | Average | Worst | Best |\n|---|---|---|---|")
    for k, label in [("violations", "Safety-rule violations"), ("hearth_pct", "Hearth return, %"),
                     ("ember_pct", "Ember return, %"), ("protocol_fees", "Protocol fees, $"),
                     ("lv_fees", "LiquidV fees paid, $"), ("hedge_costs", "Hearth hedge costs, $"),
                     ("gap_loss", "Stop-loss gap loss, $"), ("nettable_usd", "Flow that could be netted, $"),
                     ("netted_pct", "Share of base flow that nets (buys vs sells), %"),
                     ("unhedged", "Updates Hearth could not fully hedge"), ("refused", "Buys refused")]:
        a, lo, hi = agg(base, k)
        w(f"| {label} | {fmt(a)} | {fmt(lo)} | {fmt(hi)} |")
    ends = {s: sum(r["status"] == s for r in base) for s in ("LIVE", "CROWNED", "KNOCKED_OUT")}
    w(f"\nEnded: {ends}.\n")
    w("Per token (average over runs):\n")
    w("| Token | Hearth % | Ember % | Gap loss $ | Ended |\n|---|---|---|---|---|")
    for t in paths:
        rs = [r for r in base if r["token"] == t]
        st = max(set(r["status"] for r in rs), key=lambda s: sum(r["status"] == s for r in rs))
        w(f"| {t} | {fmt(statistics.mean(r['hearth_pct'] for r in rs))} | "
          f"{fmt(statistics.mean(r['ember_pct'] for r in rs))} | "
          f"{fmt(statistics.mean(r['gap_loss'] for r in rs))} | {st} |")

    fill = scen_fill_coverage(paths)
    w("\n## 2. Attack: one buyer fills the whole pool at launch\n")
    w("| Token | Tokens bought | Pool money locked | Paid out at the end | Ember % | Hearth % | Violations |\n|---|---|---|---|---|---|---|")
    for r in fill:
        w(f"| {r['token']} | {r['tokens']:,.0f} | {r['coverage_used']:.0f}% | ${r['payout']:,.0f} | "
          f"{fmt(r['ember_pct'])} | {fmt(r['hearth_pct'])} | {r['violations']} |")

    for limit in (4.0, float("inf")):
        ch = scen_cheap_tickets(paths, limit)
        hit = [r for r in ch if r["spent"] > 0]
        w(f"\n## 3. Attack: buy cheap tickets near the stop-loss (mint limit {'4x' if limit < 99 else 'OFF'})\n")
        if not hit:
            w("No token got cheap enough in the data, or every buy was refused.\n")
        else:
            w("| Token | Spent | Got back | Ember % | Violations |\n|---|---|---|---|---|")
            for r in hit:
                w(f"| {r['token']} | ${r['spent']:,.0f} | ${r['got']:,.0f} | {fmt(r['ember_pct'])} | {r['violations']} |")

    run = scen_lp_run(paths)
    w("\n## 4. Attack: LP bank run (both pools pull out everything they can, every update)\n")
    a, lo, hi = agg(run, "violations")
    kinds = sorted(set(k for r in run for k in r['violation_kinds']))
    w(f"{len(run)} runs. Safety-rule violations: total {sum(r['violations'] for r in run)} {kinds}. "
      f"LP money pulled out (free capital only): average ${statistics.mean(r['pulled'] for r in run):,.0f}. "
      f"An unpaid holder sell would count as a violation.\n")

    for fn in (False, True):
        fs = scen_foresight(paths, fill_next=fn)
        w(f"\n## 5{'b' if fn else 'a'}. Attack: attacker knows the next price before it lands, "
          f"{'fills at the NEXT update (spec rule)' if fn else 'fills at the CURRENT price'}\n")
        w("| Token | Attacker profit | Ember % | Hearth % |\n|---|---|---|---|")
        for r in fs:
            w(f"| {r['token']} | ${r['attacker_pnl']:,.0f} | {fmt(r['ember_pct'])} | {fmt(r['hearth_pct'])} |")
        w(f"| **Total** | **${sum(r['attacker_pnl'] for r in fs):,.0f}** | | |")

    w("\n## 6. Stress: every price move made 2x and 3x bigger\n")
    w("| Move size | Violations | Knockouts | Crowns | Avg gap loss $ | Worst Hearth % | Worst Ember % |\n|---|---|---|---|---|---|---|")
    for mult in (1, 2, 3):
        gs = scen_gap_stress(paths, mult)
        w(f"| {mult}x | {sum(r['violations'] for r in gs)} | {sum(r['status']=='KNOCKED_OUT' for r in gs)} | "
          f"{sum(r['status']=='CROWNED' for r in gs)} | {fmt(statistics.mean(r['gap_loss'] for r in gs))} | "
          f"{fmt(min(r['hearth_pct'] for r in gs))} | {fmt(min(r['ember_pct'] for r in gs))} |")

    fz = scen_fuzz()
    w("\n## 7. Fuzz: 3,000 random jumpy markets, random buys, sells and LP withdrawals\n")
    w(f"{fz}\n")

    w("\n## 8. Capacity: our base vs LiquidV's vaults today\n")
    w("| Token | LiquidV vault today | Base needed for $10k of our tokens |\n|---|---|---|")
    for t in paths:
        w(f"| {t} | ${meta[t]['vault_usd']:,.0f} | ~$10,000 ({10_000 / max(meta[t]['vault_usd'], 1):,.0f}x their vault) |")

    open(REPORT, "w").write("\n".join(L) + "\n")
    print("\n".join(L))


if __name__ == "__main__":
    main()
