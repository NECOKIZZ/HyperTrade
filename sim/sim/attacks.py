"""Round 2: try to break Asphodel v0.5 as the market, the hero, the buyer and the LP.

Usage: python3 -I sim/attacks.py <data_dir> <report_path>
"""
import sys, os, json, glob, random, statistics, zlib, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from engine2 import Market, Params, Refused, INF

DATA, REPORT = sys.argv[1], sys.argv[2]
POOL = 25_000.0
OUT = []
w = OUT.append
FIND = []        # (severity, title, detail)


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


def mk(nav0, **kw):
    return Market(nav0=nav0, p=Params(**kw), cash_H=POOL, cash_E=POOL)


def try_buy(m, usd):
    try:
        return m.buy(usd)
    except Refused:
        return 0.0


def try_sell(m, q):
    try:
        return m.sell(q)
    except Refused:
        return None


class Wallet:
    """A token holder's cash flows."""
    def __init__(self):
        self.tokens = 0.0
        self.spent = 0.0
        self.got = 0.0

    def buy(self, m, usd):
        q = try_buy(m, usd)
        if q:
            self.tokens += q
            self.spent += usd
        return q

    def sell(self, m, frac=1.0):
        q = self.tokens * frac
        if q <= 0:
            return 0.0
        r = try_sell(m, q)
        if r is None:
            return None
        self.tokens -= q
        self.got += r
        return r

    def value(self, m):
        return self.tokens * m.price()

    def pnl(self, m):
        return self.got + self.value(m) - self.spent


def retail(m, rng, wal, buy_p=0.4, sell_p=0.3, size=300):
    if m.status == "LIVE" and rng.random() < buy_p:
        wal.buy(m, size * rng.lognormvariate(0, 1))
    if rng.random() < sell_p and wal.tokens > 0:
        wal.sell(m, 0.10)


def settle(m, wallets, extra_steps=20):
    """Let any pending Crown/knockout sale complete, then everyone sells."""
    k = 0
    while m.status == "ENDING" and k < extra_steps:
        m.update(m.nav)
        k += 1
    for wl in wallets:
        wl.sell(m, 1.0)


def pool_pnl(m, pool):
    """Passive LP P&L in that pool."""
    sh = m.shares[pool].get("passive", 0.0)
    return sh * m.eq_per_share(pool) - POOL + max(0.0, -m.lp_flow.get("passive", 0.0) if False else 0.0)


def flag(m):
    return len(m.violations)


def table(header, rows):
    w("| " + " | ".join(header) + " |")
    w("|" + "---|" * len(header))
    for r in rows:
        w("| " + " | ".join(str(c) for c in r) + " |")
    w("")


def f0(x):
    return f"{x:,.0f}"


def f1(x):
    return f"{x:,.1f}"


def pct(x):
    return f"{x:+.1f}%"


# ======================================================================= scenarios
def run_path(path, params, seed, inject=None, loyal=5000.0, stale=None, lp_actions=None,
             insiders=None, whale=None):
    """Generic driver. inject(i, nav) -> nav; stale = set of step indices with a stale feed."""
    m = mk(path[0], **params)
    rng = rng_for("retail", seed)
    crowd, loyal_w = Wallet(), Wallet()
    if loyal:
        loyal_w.buy(m, loyal)
    if whale:
        whale.setup(m)
    for i, nav in enumerate(path):
        if inject:
            nav = inject(i, nav)
        if lp_actions:
            lp_actions(m, i)
        retail(m, rng, crowd)
        if insiders:
            insiders(m, i)
        if whale:
            whale.step(m, i, nav)
        m.update(nav, fresh=not (stale and i in stale))
    if whale:
        whale.finish(m)
    settle(m, [crowd, loyal_w] + ([whale.w] if whale else []))
    return m, crowd, loyal_w


RULES = {
    "A: stop $0, instant": dict(),
    "B: stop $0, confirm 2": dict(ko_confirm=2),
    "C: stop $0.25, instant": dict(stop_price=0.25),
    "D: stop $0.25, confirm 2": dict(stop_price=0.25, ko_confirm=2),
    "E: stop $0.25, confirm 3": dict(stop_price=0.25, ko_confirm=3),
}


def s1_flash_wicks(paths):
    w("## 1. Market: flash wicks (one-update crash, full recovery the next update)\n")
    w("Every token, 3 random times, 3 seeds: the NAV crashes by the wick depth for ONE update and "
      "is back to normal the next. A $5,000 'loyal holder' bought at launch and never sells. "
      "Compared with the same run without the wick.\n")
    rows = []
    worst = {}
    for depth in (0.3, 0.5, 0.7, 0.9):
        for rname, rp in RULES.items():
            kos = n = 0
            dl, dh, de = [], [], []
            viol = 0
            for t, h in paths.items():
                for k in range(3):
                    r = rng_for("wick", t, k)
                    at = r.randrange(20, len(h) - 5)
                    for s in range(3):
                        base, _, lw0 = run_path(h, rp, (t, k, s))
                        mm, _, lw = run_path(h, rp, (t, k, s),
                                             inject=lambda i, nav, at=at: nav * (1 - depth) if i == at else nav)
                        n += 1
                        kos += mm.status == "KNOCKED_OUT" and base.status != "KNOCKED_OUT"
                        dl.append(lw.pnl(mm) - lw0.pnl(base))
                        dh.append(pool_pnl(mm, "H") - pool_pnl(base, "H"))
                        de.append(pool_pnl(mm, "E") - pool_pnl(base, "E"))
                        viol += flag(mm)
            rows.append((f"{int(depth*100)}%", rname, f"{100*kos/n:.0f}%", f0(statistics.mean(dl)),
                         f0(min(dl)), f0(statistics.mean(dh)), f0(min(dh)), f0(statistics.mean(de)), viol))
            worst[(depth, rname)] = (kos / n, statistics.mean(dl), min(dh))
    table(["Wick", "Stop rule", "Holders wiped by the wick", "Loyal holder Δ avg $", "worst $",
           "Hearth Δ avg $", "worst $", "Ember Δ avg $", "Violations"], rows)
    a = worst[(0.7, "A: stop $0, instant")]
    d = worst[(0.7, "D: stop $0.25, confirm 2")]
    FIND.append(("HIGH", "A one-update wick permanently knocks out holders",
                 f"With an instant stop at $0, a 70% one-update wick wiped holders in {a[0]*100:.0f}% of runs "
                 f"(loyal holder −${-a[1]:,.0f} on average) even though the price was back the next update. "
                 f"Requiring 2 updates below the stop cut that to {d[0]*100:.0f}%."))


def s2_liquidation(paths):
    w("## 2. Market: the hero is liquidated (NAV → 2% of its value in one update, no recovery)\n")
    rows = []
    for rname, rp in [("stop $0, sold at once", dict()),
                      ("stop $0, base sale 1 update late", dict(sale_delay=1)),
                      ("stop $0.25", dict(stop_price=0.25)),
                      ("stop $0.50", dict(stop_price=0.5))]:
        dh, de, dl, viol = [], [], [], 0
        for t, h in paths.items():
            for k in range(3):
                at = rng_for("liq", t, k).randrange(30, len(h) - 5)
                base, _, lw0 = run_path(h, rp, (t, k))
                mm, _, lw = run_path(h, rp, (t, k), inject=lambda i, nav, at=at: nav * 0.02 if i >= at else nav)
                dh.append(pool_pnl(mm, "H") - pool_pnl(base, "H"))
                de.append(pool_pnl(mm, "E") - pool_pnl(base, "E"))
                dl.append(lw.pnl(mm) - lw0.pnl(base))
                viol += flag(mm)
        rows.append((rname, f0(statistics.mean(dl)), f0(statistics.mean(dh)), f0(min(dh)),
                     f0(statistics.mean(de)), f0(min(de)), viol))
    table(["Rule", "Loyal holder Δ $", "Hearth Δ avg $", "Hearth worst $", "Ember Δ avg $", "Ember worst $",
           "Violations"], rows)
    FIND.append(("HIGH", "Liquidation gaps land on Hearth, not on holders",
                 f"When a hero is liquidated in one update, the stop-loss can't fire in time. Holders lose their "
                 f"stake (expected) but Hearth also loses: its hedge is long `$vTRADER` and only protects it "
                 f"between the stop and the max. Hearth's average hit: ${-float(rows[0][2].replace(',','')):,.0f} "
                 f"per run with a $0 stop. A higher stop price shifts more of the remaining value to holders "
                 f"and doesn't save Hearth: only limiting gap size (heroes' leverage) or charging for it does."))


def s3_gambler():
    w("## 3. Hero as attacker: the 'coin-flip gambler'\n")
    w("The hero (or a friend he tips off) buys $5,000 of every new Series, then makes his account a fair "
      "coin flip: every update it moves up or down by `m`. Zero expected return for the hero's own account, "
      "so any profit on our token is pure extraction from LPs. 400 Series per row; pools carry over between "
      "Series. The guard rows use the hero's own trading history (his past moves) as the gap estimate.\n")
    rows = []
    res = {}
    configs = [("no guard", dict()),
               ("stop $0.25", dict(stop_price=0.25)),
               ("gap guard (k=1)", dict(gap_guard=1.0)),
               ("capped Crown", dict(crown_mode="capped")),
               ("capped Crown + gap guard", dict(crown_mode="capped", gap_guard=1.0)),
               ("capped Crown + gap guard + stop $0.25", dict(crown_mode="capped", gap_guard=1.0, stop_price=0.25))]
    for mv in (0.05, 0.15, 0.30, 0.50, 0.80):
        for cname, cp in configs:
            r = rng_for("flip", mv, cname)
            cashH, cashE = POOL, POOL
            spent = got = 0.0
            series = refused = 0
            viol = 0
            for sidx in range(400):
                m = Market(nav0=1.0, p=Params(**cp), cash_H=cashH, cash_E=cashE)
                m.moves.extend([mv] * 10)   # the hero's history is public
                q = try_buy(m, 5000.0)
                if q == 0:
                    refused += 1
                else:
                    spent += 5000.0
                nav = 1.0
                for _ in range(60):
                    nav = max(nav * (1 + (mv if r.random() < 0.5 else -mv)), 1e-9)
                    m.update(nav)
                    if m.status != "LIVE":
                        break
                k = 0
                while m.status == "ENDING" and k < 10:
                    m.update(m.nav); k += 1
                if q:
                    got += m.sell(q) or 0.0
                viol += flag(m)
                cashH, cashE = m.cash_H + m.hedge_units * m.nav * (1 - m.p.lv_exit), m.cash_E
                series += 1
            att = got - spent
            res[(mv, cname)] = (att / spent if spent else 0.0, cashH - POOL, cashE - POOL)
            rows.append((f"±{int(mv*100)}%", cname, f"{100*refused/series:.0f}%",
                         pct(100 * att / spent) if spent else "n/a", f0(att), f0(cashH - POOL), f0(cashE - POOL), viol))
    table(["Hero move per update", "Guard", "Buys refused", "Attacker return", "Attacker $",
           "Hearth $", "Ember $", "Violations"], rows)
    GAMBLER.update(res)


GAMBLER = {}


def s4_crown_pump(paths):
    w("## 4. Holder as attacker: one-update pump to the max price\n")
    w("The attacker buys as much as the pool allows at launch, then pushes the hero's NAV above the max "
      "price for ONE update (e.g. a thin-market squeeze); it is back to normal the next update. "
      "Manipulation cost is not counted, so this is the attacker's gross prize.\n")
    rows = []
    for mode in ("fixed_C", "fixed_boost", "capped"):
        for conf in (1, 2):
            for delay in (0, 1):
                prof, lp, viol, crowns = [], [], 0, 0
                for t, h in paths.items():
                    at = rng_for("pump", t).randrange(20, len(h) - 5)
                    m = mk(h[0], crown_mode=mode, crown_confirm=conf, sale_delay=delay)
                    att = Wallet()
                    while att.buy(m, 2000.0):
                        pass
                    for i, nav in enumerate(h):
                        if i == at:
                            nav = m.nav0 * m.p.x_ceiling * 1.05
                        m.update(nav)
                    settle(m, [att])
                    prof.append(att.pnl(m))
                    lp.append(pool_pnl(m, "H") + pool_pnl(m, "E"))
                    viol += flag(m)
                    crowns += m.end_kind == "CROWN"
                rows.append((mode, conf, delay, f"{crowns}/{len(paths)}", f0(statistics.mean(prof)),
                             f0(max(prof)), f0(statistics.mean(lp)), viol))
    table(["Crown pays", "Updates above max needed", "Base sale delay", "Crowned", "Attacker avg $",
           "Attacker best $", "LPs avg $", "Violations"], rows)
    FIND.append(("CRITICAL", "Promising exactly $3 at a Crown breaks coverage when the base sells late",
                 "If the Crown promises holders exactly C and the base can only be sold an update later, a "
                 "one-update spike crowns the token, the price falls back, and the Meadow must pay far more than "
                 "the coverage it locked: violations above. Fix: at a Crown the Meadow's payment is fixed at the "
                 "covered boost and holders get the base's actual sale proceeds on top ('fixed_boost'), and a Crown "
                 "needs 2 updates above the max. Then the spike prize goes to ~0 and coverage always holds."))


def s5_lp_wick_ko(paths):
    w("## 5. LP as attacker: push the price through the stop for one update\n")
    w("An Ember LP deposits $75,000 at launch (so he owns most of Ember), lets retail buy for a while, "
      "then pushes the NAV just below the stop for ONE update to knock everyone out, and withdraws.\n")
    rows = []
    for rname, rp in [("stop $0, instant", dict()), ("stop $0, confirm 2", dict(ko_confirm=2)),
                      ("stop $0.25, instant", dict(stop_price=0.25)),
                      ("stop $0.25, confirm 2", dict(stop_price=0.25, ko_confirm=2))]:
        gains, holders, kos = [], [], 0
        for t, h in paths.items():
            at = rng_for("lpko", t).randrange(100, len(h) - 5)
            m = mk(h[0], **rp)
            m.deposit("E", 75_000.0, "attacker")
            m.update(h[0])
            crowd = Wallet()
            rng = rng_for("lpko-r", t)
            for i, nav in enumerate(h):
                if i == at:
                    nav = m.nav0 * m.p.x_stop * 0.97
                    m.withdraw("E", "attacker")
                retail(m, rng, crowd)
                m.update(nav)
            settle(m, [crowd])
            m.withdraw("E", "attacker")
            m.update(m.nav)
            gains.append(m.lp_pnl("attacker"))
            holders.append(crowd.pnl(m))
            kos += m.end_kind == "KNOCKOUT"
        rows.append((rname, f"{kos}/{len(paths)}", f0(statistics.mean(gains)), f0(max(gains)),
                     f0(statistics.mean(holders))))
    table(["Rule", "Knocked out", "Attacker LP avg $", "Attacker best $", "Retail holders avg $"], rows)


class WhaleExit:
    """Buys as much as allowed at launch, sells everything in one go at the best NAV seen in hindsight."""
    def __init__(self, path, budget=2000.0):
        self.w = Wallet()
        self.peak = max(range(len(path)), key=lambda i: path[i])

    def setup(self, m):
        while self.w.buy(m, 2000.0):
            pass

    def step(self, m, i, nav):
        if i == self.peak + 1:
            self.w.sell(m, 1.0)

    def finish(self, m):
        pass


def s6_mass_exit(paths):
    w("## 6. Holder as attacker: mass exit through a thin LiquidV vault\n")
    w("One holder buys the whole pool's capacity at launch and dumps it all in one update at the best "
      "moment. LiquidV redemptions have slippage (a redemption of N dollars costs N ÷ depth extra). "
      "Who pays the slippage: the seller ('transactor'), or the Meadow because we promised the index price.\n")
    rows = []
    for depth in (INF, 250_000.0, 50_000.0):
        for payer in ("transactor", "meadow"):
            if depth == INF and payer == "meadow":
                continue
            lp, wh, imp = [], [], []
            for t, h in paths.items():
                wx = WhaleExit(h)
                m, crowd, lw = run_path(h, dict(impact_depth=depth, impact_payer=payer), t, loyal=0, whale=wx)
                lp.append(pool_pnl(m, "H") + pool_pnl(m, "E"))
                wh.append(wx.w.pnl(m))
                imp.append(m.impact_meadow)
            rows.append(("none" if depth == INF else f"${depth:,.0f}", payer, f0(statistics.mean(wh)),
                         f0(statistics.mean(lp)), f0(min(lp)), f0(statistics.mean(imp))))
    table(["LiquidV depth", "Slippage paid by", "Whale avg $", "LPs avg $", "LPs worst $",
           "Slippage eaten by LPs avg $"], rows)
    FIND.append(("HIGH", "Never promise the index price on the base part of a fill",
                 "If our fills pay the index price while LiquidV's redemption actually slips, LPs eat the "
                 "difference on every large exit (table above). Sells must pass the base's real redemption "
                 "proceeds to the seller (LiquidV does the same: large exits settle at what positions close for)."))


def s7_sale_delay(paths):
    w("## 7. Market + plumbing: the hero keeps crashing while our base sale is delayed\n")
    w("Synthetic crash: from launch the NAV falls 8% every update for 12 updates. The stop fires "
      "around −50%, but the base (and Hearth's hedge) can only be sold `delay` updates later "
      "(slow LiquidV redemption, bridge, custody).\n")
    rows = []
    for delay in (0, 1, 3, 6):
        for rname, rp in [("stop $0", dict()), ("stop $0.25", dict(stop_price=0.25))]:
            path = [1.0] * 5 + [0.92 ** i for i in range(1, 13)] + [0.92 ** 12] * 20
            m, crowd, lw = run_path(path, dict(sale_delay=delay, **rp), ("crash", delay), loyal=5000.0)
            rows.append((delay, rname, f0(lw.pnl(m)), f0(pool_pnl(m, "H")), f0(pool_pnl(m, "E")),
                         f0(m.gap_loss), flag(m), m.refused.get("ending: waiting for base sale", 0)))
    table(["Sale delay (updates)", "Stop", "Loyal holder $", "Hearth $", "Ember $", "Gap loss $",
           "Violations", "Sells refused while waiting"], rows)


def s8_stale_crash(paths):
    w("## 8. Market + plumbing: the price feed goes stale during a crash\n")
    w("Same crash, but the feed is stale for `k` updates starting as it begins. Sells pause on stale data "
      "(spec rule), so holders are stuck; when the feed comes back the price has gapped.\n")
    rows = []
    path = [1.0] * 5 + [0.92 ** i for i in range(1, 13)] + [0.92 ** 12] * 20
    for k in (0, 3, 6, 9):
        stale = set(range(5, 5 + k))
        m, crowd, lw = run_path(path, dict(), ("stale", k), loyal=5000.0, stale=stale)
        rows.append((k, f0(lw.pnl(m)), f0(crowd.pnl(m)), f0(pool_pnl(m, "H")), f0(pool_pnl(m, "E")),
                     f0(m.gap_loss), sum(v for kk, v in m.refused.items() if "stale" in kk)))
    table(["Stale updates", "Loyal holder $", "Crowd $", "Hearth $", "Ember $", "Gap loss $",
           "Trades refused (stale)"], rows)


def s9_jit_lp(paths):
    w("## 9. LP as attacker: jump into Ember just before a knockout you can see coming\n")
    w("Hyperliquid is public: a hero's liquidation price is visible. The attacker deposits $100,000 "
      "into Ember `N` updates before the knockout and pulls out right after. Synthetic path: a slow "
      "slide through the stop with retail buying on the way down.\n")
    rows = []
    path = [1.0] * 40 + [1.0 - 0.012 * i for i in range(1, 50)] + [0.4] * 30
    ko_at = next(i for i, v in enumerate(path) if v <= 0.5)
    for lock in (0, 72, 504):
        for N in (1, 3, 12):
            def lp_actions(m, i, N=N):
                if i == ko_at - N:
                    m.deposit("E", 100_000.0, "attacker")
                if i == ko_at + 1:
                    m.withdraw("E", "attacker")
            m, crowd, lw = run_path(path, dict(deposit_lock=lock), ("jit", lock, N), loyal=5000.0,
                                    lp_actions=lp_actions)
            for _ in range(lock + 2):
                m.update(m.nav)
            m.withdraw("E", "attacker")
            m.update(m.nav)
            base, _, _ = run_path(path, dict(deposit_lock=lock), ("jit", lock, N), loyal=5000.0)
            rows.append((f"{lock} upd" if lock else "none", N, f0(m.lp_pnl("attacker")),
                         f0(pool_pnl(m, "E")), f0(pool_pnl(base, "E"))))
    table(["Deposit lock", "Deposit N updates before KO", "Attacker $", "Passive Ember $ (with attacker)",
           "Passive Ember $ (without)"], rows)


def s10_grief(paths):
    w("## 10. LP as attacker: grief Hearth by flipping Ember capital (pro-rata pools)\n")
    w("If the Hearth/Ember split follows pool capital (spec §7.3 says 'pro-rata, by capital'), an attacker "
      "can deposit and withdraw $25,000 into Ember every other update. Each change moves Hearth's share, "
      "so Hearth resizes its hedge and pays LiquidV's 1% each time.\n")
    rows = []
    for mode in ("fixed", "prorata"):
        hh, hc, at = [], [], []
        for t, h in paths.items():
            def lp_actions(m, i):
                if i % 4 == 0:
                    m.deposit("E", 25_000.0, "attacker")
                elif i % 4 == 2:
                    m.withdraw("E", "attacker")
            base, _, _ = run_path(h, dict(share_mode=mode), t)
            m, _, _ = run_path(h, dict(share_mode=mode), t, lp_actions=lp_actions)
            hh.append(pool_pnl(m, "H") - pool_pnl(base, "H"))
            hc.append(m.hedge_costs - base.hedge_costs)
            at.append(m.lp_pnl("attacker"))
        rows.append((mode, f0(statistics.mean(hc)), f0(statistics.mean(hh)), f0(min(hh)), f0(statistics.mean(at))))
    table(["Split", "Extra Hearth hedge costs $", "Hearth Δ avg $", "Hearth Δ worst $", "Attacker $"], rows)


def s11_profit_pull(paths):
    w("## 11. LPs: everyone pulls every dollar of profit, every update\n")
    w("Both pools' LPs withdraw all free capital every update, while holders keep trading and a whale "
      "holds to the end. Question: does any holder go unpaid, and what happens to capacity?\n")
    rows = []
    for t in ("vRTB2", "vANSEM", "vSMARTEST", "vFLOOD"):
        if t not in paths:
            continue
        h = paths[t]
        def lp_actions(m, i):
            if i > 5:
                m.withdraw("H", "passive")
                m.withdraw("E", "passive")
        m, crowd, lw = run_path(h, dict(), t, lp_actions=lp_actions)
        rows.append((t, flag(m), f0(-m.lp_flow.get("passive", 0.0)), f0(lw.pnl(m)), f0(crowd.pnl(m)),
                     sum(v for k, v in m.refused.items() if "coverage" in k)))
    table(["Token", "Violations", "LPs pulled out $", "Loyal holder $", "Crowd $", "Buys refused (no capacity)"], rows)


def s12_insiders(paths):
    w("## 12. Buyers with inside information\n")
    w("Some buyers know where the NAV will be `H` updates from now (the hero's friend, or someone "
      "reading the hero's open orders). They buy $3,000 only when it will be up by >2%, and sell at "
      "that point. With next-update fills, knowing ONE update ahead is worthless; knowing further ahead isn't.\n")
    rows = []
    for H in (1, 3, 12, 72):
        ins, dh, de = [], [], []
        for t, h in paths.items():
            iw = Wallet()
            sells = {}
            def insiders(m, i, h=h, iw=iw, sells=sells):
                if i in sells:
                    iw.sell(m, 1.0)
                if i + H < len(h) and h[i + H] > h[min(i + 1, len(h) - 1)] * 1.02 and m.status == "LIVE" \
                        and iw.tokens == 0:
                    if iw.buy(m, 3000.0):
                        sells[i + H] = True
            base, _, _ = run_path(h, dict(), t)
            m, _, _ = run_path(h, dict(), t, insiders=insiders)
            settle(m, [iw])
            ins.append(iw.pnl(m))
            dh.append(pool_pnl(m, "H") - pool_pnl(base, "H"))
            de.append(pool_pnl(m, "E") - pool_pnl(base, "E"))
        rows.append((H, f0(sum(ins)), f0(statistics.mean(dh)), f0(statistics.mean(de)), f0(min(de))))
    table(["Knows H updates ahead", "Insiders total $", "Hearth Δ avg $", "Ember Δ avg $", "Ember Δ worst $"], rows)


def s13_liquidv_failure(paths):
    w("## 13. Partner failure: LiquidV is hacked or freezes\n")
    rows = []
    h = paths.get("vANSEM")
    for name, inj, stale in [
        ("LiquidV hacked: NAV → 0", lambda i, nav: nav * 1e-6 if i >= 300 else nav, None),
        ("LiquidV frozen 72 updates, NAV −40% when it returns",
         lambda i, nav: nav * 0.6 if i >= 372 else nav, set(range(300, 372))),
    ]:
        m, crowd, lw = run_path(h, dict(), "lv", inject=inj, stale=stale, loyal=5000.0)
        rows.append((name, f0(lw.pnl(m)), f0(crowd.pnl(m)), f0(pool_pnl(m, "H")), f0(pool_pnl(m, "E")), flag(m)))
    table(["Event (on vANSEM's real path)", "Loyal holder $", "Crowd $", "Hearth $", "Ember $", "Violations"], rows)


def s14_correlated(paths):
    w("## 14. Market: correlated crash across every hero at once\n")
    w("All 18 heroes are long the same thing. At the same moment every NAV drops by the crash size "
      "in one update. Each hero has its own $50,000 slice of the Meadow (coverage is per token, so "
      "slices can't contaminate each other); the table sums the whole Meadow.\n")
    rows = []
    for drop, recover in ((0.3, False), (0.6, False), (0.6, True), (0.9, False)):
        tot_h = tot_e = tot_hold = 0.0
        viol = kos = 0
        for t, h in paths.items():
            at = int(len(h) * 0.6)
            inj = (lambda i, nav, at=at: nav * (1 - drop) if (i == at if recover else i >= at) else nav)
            base, _, lw0 = run_path(h, dict(stop_price=0.25, ko_confirm=2), t)
            m, crowd, lw = run_path(h, dict(stop_price=0.25, ko_confirm=2), t, inject=inj)
            tot_h += pool_pnl(m, "H") - pool_pnl(base, "H")
            tot_e += pool_pnl(m, "E") - pool_pnl(base, "E")
            tot_hold += lw.pnl(m) - lw0.pnl(base)
            viol += flag(m)
            kos += m.end_kind == "KNOCKOUT"
        cap = 2 * POOL * len(paths)
        rows.append((f"−{int(drop*100)}%" + (" then back" if recover else ""), f"{kos}/{len(paths)}",
                     f0(tot_hold), f0(tot_h), f0(tot_e), f"{100*(tot_h+tot_e)/cap:+.2f}%", viol))
    table(["Crash", "Knocked out", "Loyal holders Δ $", "Hearth Δ $", "Ember Δ $", "Meadow Δ (% of $900k)",
           "Violations"], rows)


def s15_dormant(paths):
    w("## 15. Hero closes everything and goes quiet\n")
    w("When a hero has no positions, the NAV doesn't move, so the token is frozen, but LP coverage stays "
      "locked and earns only what holders pay to trade. Share of updates where each LiquidV NAV didn't "
      "move at all, in the real data:\n")
    rows = []
    for t, h in paths.items():
        flat = sum(1 for a, b in zip(h, h[1:]) if a == b) / (len(h) - 1)
        rows.append((t, f"{100*flat:.0f}%"))
    rows.sort(key=lambda r: -float(r[1][:-1]))
    table(["Token", "Updates with no NAV change"], rows[:10])


def s16_fuzz():
    w("## 16. Fuzz: 4,000 chaotic markets with every knob randomized\n")
    w("Random boost, max price, stop, confirmations, sale delay, slippage depth and payer, pool split mode, "
      "LP deposits/withdrawals, stale feeds, wicks, pumps and liquidations, random buyers and sellers.\n")
    kinds = {}
    bad = 0
    ends = {}
    for k in range(4000):
        r = rng_for("fuzz", k)
        p = dict(B=r.choice([1.5, 2, 3]), C=r.choice([2, 3, 5]), hearth_share=r.random(),
                 stop_price=r.choice([0, 0, 0.1, 0.25, 0.5]), ko_confirm=r.choice([1, 1, 2, 3]),
                 crown_confirm=r.choice([1, 2]), crown_mode=r.choice(["fixed_boost", "capped"]),
                 sale_delay=r.choice([0, 0, 1, 3]), impact_depth=r.choice([INF, 1e5, 2e4]),
                 impact_payer="transactor", share_mode=r.choice(["fixed", "prorata"]),
                 gap_guard=r.choice([0, 0, 1.0]), gap_fee=r.choice([0, 0.5]))
        m = Market(nav0=1.0, p=Params(**p), cash_H=r.uniform(1e3, 6e4), cash_E=r.uniform(1e3, 6e4))
        wl = Wallet()
        nav = 1.0
        for i in range(400):
            a = r.random()
            if a < 0.35:
                wl.buy(m, r.uniform(1, 8000))
            elif a < 0.6:
                wl.sell(m, r.random())
            elif a < 0.65:
                m.deposit(r.choice("HE"), r.uniform(0, 3e4), f"lp{r.randrange(3)}")
            elif a < 0.72:
                m.withdraw(r.choice("HE"), r.choice(["passive", "lp0", "lp1", "lp2"]), r.random())
            ev = r.random()
            if ev < 0.01:
                nav *= r.choice([0.02, 0.3, 0.5])          # liquidation / crash
            elif ev < 0.02:
                nav *= r.choice([1.8, 2.5, 4.0])           # squeeze
            else:
                nav *= 1 + r.gauss(0, 0.04)
            nav = max(nav, 1e-9)
            m.update(nav, fresh=r.random() > 0.03)
        settle(m, [wl])
        if m.violations:
            bad += 1
            for v in set(x.split(":")[0].split(" H=")[0] for x in m.violations):
                kinds[v] = kinds.get(v, 0) + 1
        ends[m.status] = ends.get(m.status, 0) + 1
    w(f"Runs with any violation: **{bad} / 4000**. Kinds: {kinds or 'none'}. Ended: {ends}.\n")
    return bad, kinds



def s17_speed():
    """How update speed changes what LPs are short of at the stop. Pure gap study."""
    import numpy as np
    w("## 17. Speed: how much do LPs lose to gaps at different update speeds?\n")
    w("A synthetic hero trades one crypto asset (80% yearly volatility) at constant leverage L for 7 days, "
      "simulated every 0.5 s, 6 paths each. With 'jumps', the asset also has sudden candles (about 50 a year, "
      "typical size ±4%) inside one oracle tick. If one update takes the hero below maintenance margin he is "
      "liquidated (NAV → 2%). Our token reads the NAV every `cadence`. Per stop hit, how much were the LPs short "
      "of what the stop promised them (per $1 ticket)? With a $0.25 stop the holder's remaining $0.25 absorbs "
      "gaps first. (At the max price LPs always pay exactly the covered boost, so only the stop matters.)\n")
    YEAR = 365 * 24 * 3600
    dt, T = 0.5, 7 * 24 * 3600
    n = int(T / dt)
    B, C = 2.0, 3.0
    xc = 1 + (C - 1) / B
    mmr = 0.0125
    rows = []
    for L in (3, 10, 25):
        for jumps in (False, True):
            navs = []
            liqs = 0
            for pth in range(6):
                g = np.random.default_rng(zlib.crc32(f"speed|{L}|{jumps}|{pth}".encode()))
                r = g.normal(0, 0.8 * np.sqrt(dt / YEAR), n)
                if jumps:
                    r = r + (g.random(n) < 50 * dt / YEAR) * g.normal(0, 0.04, n)
                f = 1 + L * r
                liq = f <= L * mmr
                liqs += int(liq.sum())
                navs.append(np.cumprod(np.where(liq, 0.02, f)))
            for cad in (0.5, 3, 60, 1200):
                step = int(cad / dt)
                res = {}
                for stop in (0.0, 0.25):
                    xk = 1 + (stop - 1) / B
                    promised = xk - stop
                    shorts, hits = [], 0
                    for nav in navs:
                        xsamp = nav[::step]
                        i = 0
                        while i < len(xsamp) - 1:
                            rel = xsamp[i + 1:] / xsamp[i]
                            hit = (rel >= xc) | (rel <= xk)
                            if not hit.any():
                                break
                            j = int(np.argmax(hit))
                            xs = float(rel[j])
                            if xs <= xk:
                                hv = max(0.0, 1 + B * (xs - 1))
                                shorts.append(max(0.0, promised - (xs - hv)))
                                hits += 1
                            i = i + 1 + j + 1
                    res[stop] = (hits, statistics.mean(shorts) if shorts else 0.0, max(shorts) if shorts else 0.0)
                rows.append((L, "yes" if jumps else "no", f"{cad:g} s", liqs,
                             res[0.0][0], f"{res[0.0][1]:.4f}", f"{res[0.0][2]:.3f}",
                             res[0.25][0], f"{res[0.25][1]:.4f}", f"{res[0.25][2]:.3f}"))
    table(["Hero leverage", "Jumps", "Cadence", "Liquidations", "Stop $0: hits", "LP short avg $", "worst $",
           "Stop $0.25: hits", "LP short avg $", "worst $"], rows)
    SPEED.extend(rows)


SPEED = []


def compact(paths, P):
    """Key attacks under one parameter set. Returns a dict of headline numbers."""
    out = {}
    # baseline normal trading
    hp, ep, ref, tried = [], [], 0, 0
    for t, h in paths.items():
        for sd in range(3):
            m, crowd, lw = run_path(h, P, ("hh", t, sd))
            hp.append(100 * pool_pnl(m, "H") / POOL)
            ep.append(100 * pool_pnl(m, "E") / POOL)
            ref += sum(v for k, v in m.refused.items() if k in ("gap guard", "mint limit"))
    out["normal: Hearth %"] = statistics.mean(hp)
    out["normal: Ember %"] = statistics.mean(ep)
    out["normal: buys refused by guards"] = ref / (len(paths) * 3)
    # 70% wick
    kos, dl = 0, []
    for t, h in paths.items():
        at = rng_for("wick", t, 0).randrange(20, len(h) - 5)
        b, _, l0 = run_path(h, P, ("w", t))
        m, _, l1 = run_path(h, P, ("w", t), inject=lambda i, nav, at=at: nav * 0.3 if i == at else nav)
        kos += m.status == "KNOCKED_OUT" and b.status != "KNOCKED_OUT"
        dl.append(l1.pnl(m) - l0.pnl(b))
    out["70% wick: holders wiped"] = 100 * kos / len(paths)
    out["70% wick: loyal holder Δ $"] = statistics.mean(dl)
    # liquidation
    dh = []
    for t, h in paths.items():
        at = rng_for("liq", t, 0).randrange(30, len(h) - 5)
        b, _, _ = run_path(h, P, ("l", t))
        m, _, _ = run_path(h, P, ("l", t), inject=lambda i, nav, at=at: nav * 0.02 if i >= at else nav)
        dh.append(pool_pnl(m, "H") - pool_pnl(b, "H"))
    out["liquidation: Hearth Δ $"] = statistics.mean(dh)
    # gambler
    for mv in (0.3, 0.5):
        r = rng_for("flip2", mv)
        cashH = cashE = POOL
        spent = got = 0.0
        for _ in range(300):
            m = Market(nav0=1.0, p=Params(**P), cash_H=cashH, cash_E=cashE)
            m.moves.extend([mv] * 10)
            q = try_buy(m, 5000.0)
            spent += 5000.0 if q else 0.0
            nav = 1.0
            for _ in range(60):
                nav = max(nav * (1 + (mv if r.random() < 0.5 else -mv)), 1e-9)
                m.update(nav)
                if m.status != "LIVE":
                    break
            k = 0
            while m.status == "ENDING" and k < 10:
                m.update(m.nav); k += 1
            if q:
                got += m.sell(q) or 0.0
            cashH, cashE = m.cash_H + m.hedge_units * m.nav * (1 - m.p.lv_exit), m.cash_E
        out[f"gambler ±{int(mv*100)}%: attacker return %"] = 100 * (got - spent) / spent if spent else 0.0
        out[f"gambler ±{int(mv*100)}%: LPs $"] = cashH + cashE - 2 * POOL
    # pump to Crown
    prof, viol = [], 0
    for t, h in paths.items():
        at = rng_for("pump", t).randrange(20, len(h) - 5)
        m = mk(h[0], **{**P, "sale_delay": 1})
        att = Wallet()
        while att.buy(m, 2000.0):
            pass
        for i, nav in enumerate(h):
            if i == at:
                nav = m.nav0 * m.p.x_ceiling * 1.05
            m.update(nav)
        settle(m, [att])
        prof.append(att.pnl(m))
        viol += flag(m)
    out["1-update pump: attacker avg $"] = statistics.mean(prof)
    out["1-update pump: violations"] = viol
    # LP pushes through the stop
    hold = []
    for t, h in paths.items():
        at = rng_for("lpko", t).randrange(100, len(h) - 5)
        m = mk(h[0], **P)
        crowd = Wallet()
        rng = rng_for("lpko-r", t)
        for i, nav in enumerate(h):
            if i == at:
                nav = m.nav0 * m.p.x_stop * 0.97
            retail(m, rng, crowd)
            m.update(nav)
        settle(m, [crowd])
        hold.append(crowd.pnl(m))
    out["LP stop-push: retail holders avg $"] = statistics.mean(hold)
    # mass exit through thin vault
    lp = []
    for t, h in paths.items():
        wx = WhaleExit(h)
        m, _, _ = run_path(h, {**P, "impact_depth": 50_000.0}, t, loyal=0, whale=wx)
        lp.append(pool_pnl(m, "H") + pool_pnl(m, "E"))
    out["mass exit ($50k depth): LPs avg $"] = statistics.mean(lp)
    # griefing
    gh = []
    for t, h in paths.items():
        def lp_actions(m, i):
            if i % 4 == 0:
                m.deposit("E", 25_000.0, "attacker")
            elif i % 4 == 2:
                m.withdraw("E", "attacker")
        b, _, _ = run_path(h, P, t)
        m, _, _ = run_path(h, P, t, lp_actions=lp_actions)
        gh.append(pool_pnl(m, "H") - pool_pnl(b, "H"))
    out["Ember flipping: Hearth Δ $"] = statistics.mean(gh)
    return out


def s18_head_to_head(paths):
    w("## 18. Head to head: naive settings vs recommended settings\n")
    naive = dict(stop_price=0.0, ko_confirm=1, crown_mode="fixed_C", crown_confirm=1, share_mode="prorata",
                 impact_payer="meadow", impact_depth=250_000.0, gap_guard=0.0)
    rec = dict(stop_price=0.25, ko_confirm=2, crown_mode="fixed_boost", crown_confirm=2, share_mode="fixed",
               impact_payer="transactor", impact_depth=250_000.0, gap_guard=1.0)
    w("- **Naive:** stop at $0 and instant; Crown promises exactly $3 and fires instantly; Hearth/Ember split "
      "follows capital; we pay the index price and eat LiquidV slippage; no gap guard.")
    w("- **Recommended:** stop at $0.25 (holders get what's left), needs 2 updates below; at the max the Meadow "
      "pays exactly the covered boost and the holder keeps their whole real token, needs 2 updates above; split "
      "fixed when tokens are minted; sellers get the base's real redemption; mints refused when the hero's "
      "recent moves could jump the stop.\n")
    a, b = compact(paths, naive), compact(paths, rec)
    rows = []
    for k in a:
        fa, fb_ = a[k], b[k]
        fmt = (lambda v: f"{v:+.2f}") if "%" in k and "$" not in k else (lambda v: f"{v:,.0f}")
        rows.append((k, fmt(fa), fmt(fb_)))
    table(["Test", "Naive", "Recommended"], rows)
    H2H.update(dict(naive=a, rec=b))


H2H = {}

def main():
    t0 = time.time()
    paths = load()
    w("# Asphodel v0.5, round 2: trying to break it\n")
    w(f"Engine: `sim/engine2.py`. Data: {len(paths)} live LiquidV tokens (about 720 updates each). Each "
      f"hero's token: $1.00 start, real gain + equal LP gain (B = 2), max price $3. Hearth ${POOL:,.0f}, "
      f"Ember ${POOL:,.0f}. Fees: Asphodel 0.3%/0.3%, LiquidV 1% mint and 0.3% exit, plus the hedge fee. "
      "Unless a section says otherwise: stop at $0, instant, Crown pays fixed boost + base proceeds.\n")
    s1_flash_wicks(paths)
    s2_liquidation(paths)
    s3_gambler()
    s4_crown_pump(paths)
    s5_lp_wick_ko(paths)
    s6_mass_exit(paths)
    s7_sale_delay(paths)
    s8_stale_crash(paths)
    s9_jit_lp(paths)
    s10_grief(paths)
    s11_profit_pull(paths)
    s12_insiders(paths)
    s13_liquidv_failure(paths)
    s14_correlated(paths)
    s15_dormant(paths)
    bad, kinds = s16_fuzz()
    s17_speed()
    s18_head_to_head(paths)
    w(f"\n_Run time {time.time()-t0:.0f} s._\n")
    head = ["# Findings (auto-collected; see sections for numbers)\n"]
    for sev, title, detail in FIND:
        head.append(f"- **{sev}: {title}.** {detail}")
    text = "\n".join(OUT[:2] + head + [""] + OUT[2:])
    open(REPORT, "w").write(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
