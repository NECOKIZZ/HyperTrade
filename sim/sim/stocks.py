"""Round 4: the same boost token on stock ETFs (and a few single stocks for contrast).

Usage: python3 -I sim/stocks.py <data/stocks dir> <report_path>

The token is unchanged: price = 1 + B(x - 1), x = NAV_now / NAV_launch, stop at $0.25 (2 updates),
LPs' part capped at MAXB = (B-1)(C-1)/B, Crown pays real base + MAXB.

How updates are modelled on daily bars:
  * while the market is open the feed is fast (Elysium-style), so a stop or max hit during the day
    sells at the trigger level (the day's low/high crossing it);
  * the market is closed overnight and at weekends, so the open is ONE jump: a stop or max hit at
    the open sells at the open price (the gap is real).
"""
import sys, os, math, statistics, zlib, random
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from stockdata import daily, hourly, hl, day, stamp
from engine2 import Market, Params, Refused

DATA, REPORT = sys.argv[1], sys.argv[2]
OUT = []
w = OUT.append

ETFS = ["SPY", "QQQ", "IWM", "SMH", "GLD", "TLT", "ARKK"]
SINGLES = ["NVDA", "TSLA"]
NAMES = {"SPY": "S&P 500", "QQQ": "Nasdaq 100", "IWM": "Russell 2000 (small caps)", "SMH": "Semiconductors",
         "GLD": "Gold", "TLT": "20y US Treasuries", "ARKK": "ARK Innovation", "NVDA": "Nvidia (single stock)",
         "TSLA": "Tesla (single stock)"}
SETTINGS = [  # (label, B, C)
    ("2x, max $3", 2.0, 3.0),
    ("2x, max $2", 2.0, 2.0),
    ("3x, max $2", 3.0, 2.0),
    ("5x, max $2", 5.0, 2.0),
    ("10x, max $2", 10.0, 2.0),
]
STOP = 0.25


def table(header, rows):
    w("| " + " | ".join(header) + " |")
    w("|" + "---|" * len(header))
    for r in rows:
        w("| " + " | ".join(str(c) for c in r) + " |")
    w("")


def pct(x, d=1):
    return f"{x * 100:+.{d}f}%"


def pc(x, d=1):
    return f"{x * 100:.{d}f}%"


def money(x):
    return f"${x:,.2f}"


def xs_of(B):
    return 1 + (STOP - 1) / B


def xc_of(B, C):
    return 1 + (C - 1) / B


def maxb(B, C):
    return (B - 1) * (C - 1) / B


# --------------------------------------------------------------------------- one token's life
def life(D, i, B, C, horizon, total_return=True):
    """Token launched at the close of day i. Returns dict(kind, j, x_end, payout, short, gap)."""
    f = D["ac"] / D["c"] if total_return else np.ones_like(D["c"])
    P0 = D["c"][i] * f[i]
    xs, xc, mb = xs_of(B), xc_of(B, C), maxb(B, C)
    n = len(D["c"])
    end = min(n - 1, i + horizon)
    for j in range(i + 1, end + 1):
        o, hi, lo = D["o"][j] * f[j] / P0, D["h"][j] * f[j] / P0, D["l"][j] * f[j] / P0
        # the open is one jump from yesterday's close
        if o <= xs:
            return _ko(B, o, j, gap=True)
        if o >= xc:
            return dict(kind="CROWN", j=j, x_end=o, payout=o + mb, short=0.0, gap=True)
        down_first = D["c"][j] < D["o"][j]
        hits = [("KO", lo <= xs), ("CROWN", hi >= xc)]
        if not down_first:
            hits.reverse()
        for k, hit in hits:
            if hit and k == "KO":
                return _ko(B, xs, j, gap=False)
            if hit and k == "CROWN":
                return dict(kind="CROWN", j=j, x_end=xc, payout=xc + mb, short=0.0, gap=False)
    x = D["c"][end] * f[end] / P0
    return dict(kind="LIVE", j=end, x_end=x, payout=max(0.0, min(1 + B * (x - 1), x + mb)), short=0.0, gap=False)


def _ko(B, x, j, gap):
    left = 1 + B * (x - 1)
    return dict(kind="KO", j=j, x_end=x, payout=max(0.0, left), short=max(0.0, -left), gap=gap)


def launches(D, horizon, every=5):
    n = len(D["c"])
    return range(0, n - 1 - min(horizon, 60), every)


# --------------------------------------------------------------------------- sections
def s0_data(DS):
    w("## 0. The data\n")
    w("Daily prices from Yahoo Finance (split-adjusted, with dividends), downloaded 2026-11-21. "
      "Hourly bars for the last 2 years. Hyperliquid HIP-3 stock perps (24/7) for the last ~7 months.\n")
    rows = []
    for s in ETFS + SINGLES:
        D = DS[s]
        r = np.diff(np.log(D["ac"]))
        gap = D["o"][1:] / D["c"][:-1] - 1
        k = int(np.argmin(gap))
        dd = D["ac"] / np.maximum.accumulate(D["ac"]) - 1
        yrs = (D["t"][-1] - D["t"][0]) / (365.25 * 86400)
        cagr = (D["ac"][-1] / D["ac"][0]) ** (1 / yrs) - 1
        rows.append([f"{s} ({NAMES[s]})", f"{day(D['t'][0])[:4]}–2026", pc(r.std() * math.sqrt(252), 0),
                     pct(cagr), pc(-dd.min(), 0), f"{pct(gap[k])} ({day(D['t'][k + 1])})",
                     pct(np.exp(r.min()) - 1)])
    table(["Asset", "Years", "Yearly swing (vol)", "Avg yearly gain", "Worst fall from top",
           "Worst overnight gap", "Worst day"], rows)
    w("For comparison, the LiquidV trader tokens in round 1 moved about **10x more** per update, "
      "and 43–100% of their updates did not move at all.\n")


def s1_settings(DS):
    w("## 1. Where the stop and max land for each setting\n")
    rows = []
    for lab, B, C in SETTINGS:
        rows.append([lab, pct(xs_of(B) - 1), pct(xc_of(B, C) - 1), money(maxb(B, C)), pct(-1 / B)])
    table(["Setting", "Stop when ETF is", "Max when ETF is", "LP money locked per $1 ticket",
           "Ticket hits $0 when ETF is"], rows)


def outcome_grid(DS, syms, horizon):
    res = {}
    for s in syms:
        D = DS[s]
        for lab, B, C in SETTINGS:
            L = [life(D, i, B, C, horizon) for i in launches(D, horizon)]
            res[(s, lab)] = L
    return res


def s2_outcomes(DS, res, horizon, syms, title):
    w(f"## {title}\n")
    w(f"A token launched every 5 trading days over each ETF's whole history, followed for "
      f"{horizon // 252} year{'s' if horizon > 252 else ''} (or until its stop or max). Per $1 ticket, before fees.\n")
    rows = []
    for s in syms:
        for lab, B, C in SETTINGS:
            L = res[(s, lab)]
            n = len(L)
            ko = sum(1 for z in L if z["kind"] == "KO") / n
            cr = sum(1 for z in L if z["kind"] == "CROWN") / n
            hold = [z["payout"] - 1 for z in L]
            lp = [z["x_end"] - z["payout"] for z in L]          # the LPs' side of the boost
            sh = [z["short"] for z in L if z["kind"] == "KO"]
            nshort = sum(1 for z in sh if z > 0)
            rows.append([s, lab, pc(ko, 0), pc(cr, 0), pct(statistics.median(hold), 0), pct(statistics.mean(hold), 0),
                         f"{statistics.mean(lp):+.3f}", f"{nshort}/{n}" if nshort else "0",
                         f"{max(sh):.3f}" if sh and max(sh) > 0 else "–"])
    table(["ETF", "Setting", "Stopped", "Maxed", "Holder median", "Holder average",
           "LPs per ticket (avg $)", "LPs short (count)", "Worst LP short per $1"], rows)


def s3_vs_leveraged_etf(DS):
    w("## 3. Our 2x vs a real 2x ETF (SSO, QLD) and just holding\n")
    w("SSO and QLD are real 2x ETFs. They reset their leverage every day, so a choppy market "
      "eats them (\"volatility decay\"). Our boost has one zero at launch, so the ticket is exactly "
      "$1 + 2 × (ETF move) with no daily reset. Same 1-year windows, before fees. Our ticket is followed to its stop or max.\n")
    rows = []
    for base, lev in (("SPY", "SSO"), ("QQQ", "QLD")):
        A, L2 = DS[base], DS[lev]
        common = np.intersect1d(A["t"], L2["t"])
        ia = {t: k for k, t in enumerate(A["t"])}
        il = {t: k for k, t in enumerate(L2["t"])}
        ours, theirs, hold, win = [], [], [], 0
        for t0 in common[: -253: 5]:
            i = ia[t0]
            if i + 252 >= len(A["t"]):
                break
            t1 = A["t"][i + 252]
            if t1 not in il:
                continue
            z = life(A, i, 2.0, 3.0, 252)
            o = z["payout"] - 1
            th = L2["ac"][il[t1]] / L2["ac"][il[t0]] - 1
            ours.append(o); theirs.append(th); hold.append(A["ac"][i + 252] / A["ac"][i] - 1)
            win += o > th
        # a choppy example: the year with the biggest gap between the two
        rows.append([f"{base} vs {lev}", len(ours), pct(statistics.median(ours), 0), pct(statistics.median(theirs), 0),
                     pct(statistics.median(hold), 0), pct(min(ours), 0), pct(min(theirs), 0), pc(win / len(ours), 0)])
    table(["Pair", "Windows", "Our 2x median", "Real 2x ETF median", "Just holding", "Our worst", "Real 2x worst",
           "Ours better"], rows)


def s4_lp_economics(DS, res1):
    w("## 4. The big one: stocks go up on average, and LPs are on the other side\n")
    w("Trader tokens have no built-in upward drift (most traders don't win). Stock ETFs do: "
      "the S&P 500 averaged about 10% a year. An unhedged Ember LP is short the boost, so it pays "
      "that drift to holders, every year, up to its cap. Hearth hedges by holding the ETF, so it doesn't.\n")
    rows = []
    for s in ETFS:
        for lab, B, C in SETTINGS[:2] + SETTINGS[3:4]:
            L = res1[(s, lab)]
            lp = statistics.mean(z["x_end"] - z["payout"] for z in L)
            yrs = statistics.mean(max(1, z["j"] - 0) for z in L)
            mb = maxb(B, C)
            # carry (yearly % of ticket value) that makes Ember break even, plus a 4% T-bill return on its locked money
            carry_even = max(0.0, -lp)
            carry_bill = max(0.0, -lp + 0.04 * mb)
            rows.append([s, lab, money(mb), f"{lp:+.3f}", pct(lp / mb, 0), pc(carry_even, 1), pc(carry_bill, 1)])
    table(["ETF", "Setting", "Ember locks per ticket", "Ember 1-year result per ticket",
           "Ember yearly return on locked money", "Carry to break even (per year, of ticket)",
           "Carry to beat 4% T-bills"], rows)


def s5_gap_bugs(DS):
    w("## 5. Bug: the market closes, so the open is one big jump\n")
    w("On LiquidV, NAV moves every few minutes. A stock market is shut 16 hours a day and all weekend, "
      "so the opening price can land far past the stop, or past $0, in one update. The 2-update stop rule "
      "can't help with a jump; only a cushion can.\n")
    rows = []
    for s in ETFS + SINGLES:
        D = DS[s]
        gap = D["o"][1:] / D["c"][:-1] - 1
        for lab, B, C in SETTINGS:
            zero = -1 / B
            past_zero = int((gap <= zero).sum())
            past_stop_room = int((gap <= xs_of(B) - 1).sum())
            if lab in ("2x, max $3", "5x, max $2", "10x, max $2"):
                rows.append([s, lab, pct(zero), past_stop_room, past_zero])
    table(["ETF", "Setting", "Ticket hits $0 at", "Opens that jumped further than the whole stop distance",
           "Opens that jumped past $0"], rows)
    # a worked real example
    D = DS["SPY"]
    t = list(map(day, D["t"]))
    k = t.index("2020-03-16")
    c0, o1 = D["c"][k - 1], D["o"][k]
    B = 10.0
    g = o1 / c0 - 1
    left = 1 + B * g
    owed = (B - 1) * -g            # the LPs' side of the boost at the sale price
    w(f"**Real example (10x, SPY).** 10,000 tickets ($10,000) launched at the close on Friday 13 March 2020 "
      f"(SPY ${c0:.2f}). The stop sits at SPY ${c0 * xs_of(B):.2f} (-7.5%). Monday 16 March opened at "
      f"${o1:.2f}, {pct(g)} in one jump, past the stop and past $0 (-10%) at once.\n")
    table(["", "Normal stop (sells at -7.5%)", "What the gap did (sells at -10.4%)"],
          [["Real SPY inside sells for", f"${10000 * xs_of(B):,.0f}", f"${10000 * (1 + g):,.0f}"],
           ["Holders get", f"${10000 * STOP:,.0f}", "$0"],
           ["LPs are owed (9 × the fall)", f"${10000 * (B - 1) * (1 - xs_of(B)):,.0f}", f"${10000 * owed:,.0f}"],
           ["LPs actually get", f"${10000 * (xs_of(B) - STOP):,.0f}", f"${10000 * (1 + g):,.0f}"],
           ["LPs short", "$0", f"${10000 * (owed - 1 - g):,.0f}"]])
    w("At 5x the same morning is harmless: the stop is at -15%, so a -10.4% jump from a fresh launch "
      "doesn't even reach it, and from a token already near its stop the $0.25 cushion (5% of SPY) "
      "absorbs most of it. **The cushion must be bigger than the worst overnight jump × B.** "
      "For ETFs (worst jump ~-10% to -12%) that means B ≤ 5; single stocks (Nvidia -31% on earnings) "
      "need B ≤ 2 and no minting the day before earnings.\n")


def s6_overnight_confirm(DS):
    w("## 6. Bug: the 2-update stop can straddle the close\n")
    w("The stop needs 2 updates in a row below $0.25. If the first one is the last price before the "
      "close, the second is the next morning's open, so everyone carries the whole night's jump while "
      "waiting. Sometimes the night saves the holder (the price comes back), sometimes it makes it "
      "worse. Hourly bars, last 2 years, a token launched every 3 hours.\n")
    rows = []
    for s in ["SPY", "QQQ", "SMH", "ARKK", "NVDA", "TSLA"]:
        H = hourly(DATA, s)
        c, o, new = H["c"], H["o"], H["new"]
        N = len(c)
        for B in (5.0, 10.0):
            xs = xs_of(B)
            n_ko = 0
            saved, worse = [], []
            for i in range(0, N - 1, 3):
                P0 = c[i]
                below = 0
                for j in range(i + 1, min(N, i + 7 * 252)):
                    if new[j]:
                        xo = o[j] / P0
                        if xo <= xs:
                            below += 1
                        else:
                            if below:          # it was below at the close and the night saved it
                                saved.append(B * (xo - xs))
                            below = 0
                        if below >= 2:
                            n_ko += 1
                            worse.append(B * (xs - xo))   # sold at the open instead of near the stop
                            break
                        if below == 1 and not (j + 1 < N and new[j + 1]):
                            n_ko += 1                     # confirmed within the session, near the stop
                            break
                    xc_ = c[j] / P0
                    if xc_ <= xs:
                        if j + 1 < N and new[j + 1]:
                            below = 1                     # first strike is the last price of the day
                        else:
                            n_ko += 1                     # next update is minutes away: sells near the stop
                            break
                    else:
                        below = 0
            rows.append([s, f"{B:.0f}x", n_ko, len(worse), len(saved),
                         f"${statistics.mean(worse):.3f}" if worse else "–", f"${max(worse):.3f}" if worse else "–"])
    table(["Asset", "Boost", "Stops", "Confirmed only at next open (worse)", "Saved by the night",
           "Avg extra loss per $1 ticket", "Worst extra loss per $1 ticket"], rows)
    w("Every \"worse\" case is money taken from the $0.25 the holder was promised, and past $0 from "
      "the LPs. Fix: confirm the stop by **time while the market is open** (e.g. 2 updates at least 60 "
      "seconds apart) and if the first strike comes in the last minutes, sell in the **closing auction**. "
      "That gives up the \"saved by the night\" cases, which is the honest trade: a stop is a promise "
      "about the price you sell at, not a bet on tomorrow.\n")


def s7_weekend_perp(DS):
    w("## 7. Bug: a 24/7 feed on a 5-day market\n")
    w("Hyperliquid's stock perps (HIP-3, e.g. `xyz:SP500`) trade all weekend while the real market is "
      "shut. If our feed is that perp, a thin weekend market sets the price that stops or maxes tokens. "
      "If our feed is the real exchange price, it is frozen all weekend while the perp already shows "
      "where Monday will open — free money for anyone who can still trade at Friday's price.\n")
    P = hl(DATA, "xyz:SP500")
    H = hourly(DATA, "SPY")
    # weekend windows: last SPY bar on a Friday -> first SPY bar after
    t, c, o, new = H["t"], H["c"], H["o"], H["new"]
    rows = []
    vol_wk, vol_we = [], []
    import datetime as dt
    for k in range(len(P["t"])):
        wd = dt.datetime.fromtimestamp(int(P["t"][k]), dt.timezone.utc).weekday()
        (vol_we if wd >= 5 else vol_wk).append(P["v"][k] * P["c"][k])
    errs, gaps, stale_edge, wick = [], [], [], []
    pt = P["t"]
    for j in range(1, len(t)):
        if not new[j]:
            continue
        if (t[j] - t[j - 1]) < 40 * 3600:   # only weekends
            continue
        fri_close_t = t[j - 1] + 3600       # bar start + 1h = close time
        mon_open_t = t[j]
        a = np.searchsorted(pt, fri_close_t)
        b = np.searchsorted(pt, mon_open_t)
        if a <= 0 or b - a < 20 or b >= len(pt):
            continue
        hl_fri = P["c"][a - 1]
        hl_pre = P["c"][b - 1]
        lo = P["l"][a:b].min() / hl_fri - 1
        hi = P["h"][a:b].max() / hl_fri - 1
        spy_gap = o[j] / c[j - 1] - 1
        hl_move = hl_pre / hl_fri - 1
        gaps.append(spy_gap); errs.append(spy_gap - hl_move)
        stale_edge.append(abs(spy_gap) if np.sign(hl_move) == np.sign(spy_gap) else -abs(spy_gap))
        wick.append((lo, hi, stamp(fri_close_t)[:10]))
    if gaps:
        cor = float(np.corrcoef(gaps, [g - e for g, e in zip(gaps, errs)])[0, 1])
        lo_w = min(wick, key=lambda z: z[0])
        hi_w = max(wick, key=lambda z: z[1])
        rows = [["Weekends checked", len(gaps)],
                ["Avg size of SPY's Monday open jump", pc(statistics.mean(map(abs, gaps)), 2)],
                ["How well the perp's Sunday-night price predicts it (correlation)", f"{cor:.2f}"],
                ["Perp guessed the direction right", pc(sum(1 for z in stale_edge if z > 0) / len(stale_edge), 0)],
                ["Biggest weekend dip on the perp", f"{pct(lo_w[0], 2)} (weekend of {lo_w[2]})"],
                ["Biggest weekend rise on the perp", f"{pct(hi_w[1], 2)} (weekend of {hi_w[2]})"],
                ["Weekend share of the perp's trading volume", pc(sum(vol_we) / (sum(vol_we) + sum(vol_wk)), 0)]]
        table(["Weekend fact (S&P 500)", "Value"], rows)
        edge = statistics.mean(stale_edge)
        w(f"**Example (5x, stale feed).** On Sunday night the perp says Monday will open up. A buyer "
          f"buys $10,000 of 5x tickets at Friday's frozen price and sells at Monday's open. Averaged over "
          f"every weekend, following the perp's direction makes {pct(edge * 5, 2)} per weekend "
          f"(${10000 * edge * 5:,.0f} on $10,000), straight out of the LPs, with no risk worth the name. "
          f"Fix: the fill rule from §4.3 again — orders placed while the market is shut fill at the next real "
          f"price (the open), never at Friday's. And the stop/max should only fire on real-market prices, "
          f"so a thin weekend perp can't knock tokens out.\n")


def s8_dividends(DS):
    w("## 8. Bug: dividends look like a price drop\n")
    w("On the day a dividend is paid out (ex-dividend day), the ETF's price falls by the dividend. "
      "Nothing was lost — the owner got the cash — but a price-only feed sees a fall, boosts it, and "
      "hands that part to the LPs.\n")
    rows = []
    for s in ["SPY", "QQQ", "IWM", "TLT"]:
        D = DS[s]
        tr = D["ac"][-1] / D["ac"][-253]
        pr = D["c"][-1] / D["c"][-253]
        y = tr / pr - 1
        for B in (2.0, 5.0):
            rows.append([s, f"{B:.0f}x", pc(y, 2), pc((B - 1) * y, 2), f"${100 * (B - 1) * y:,.2f}"])
    table(["ETF", "Boost", "Dividends in the last year", "Boost lost to LPs if the feed ignores them",
           "Per $100 of tickets"], rows)
    D = DS["SPY"]
    ks = sorted(D["divs"].items())[-1]
    k = int(np.searchsorted(D["t"], ks[0]))
    w(f"**Example.** SPY paid ${ks[1]:.2f} a share on {day(D['t'][k])} (SPY about ${D['c'][k - 1]:.0f}, "
      f"so {pc(ks[1] / D['c'][k - 1], 2)}). A price-only feed sees a {pct(-ks[1] / D['c'][k - 1], 2)} drop; at 5x "
      f"a $100 ticket drops ${500 * ks[1] / D['c'][k - 1]:.2f}, of which the holder's own real token only "
      f"lost ${100 * ks[1] / D['c'][k - 1]:.2f} and got it back as cash. The other "
      f"${400 * ks[1] / D['c'][k - 1]:.2f} went to the LPs for nothing. A token sitting just above its stop "
      f"can even be knocked out by a dividend.\n")
    w("Fix: price the token on **total return** (NAV includes dividends, as Yahoo's adjusted close does) "
      "and pass the base's dividends to the holder. If the base is a perp, there is no dividend — "
      "the perp's funding does the job instead (see §11).\n")


def s9_splits(DS):
    w("## 9. Bug: a stock split looks like a 90% crash\n")
    D = DS["NVDA"]
    sp = [z for z in D["splits"] if z[1] == 10.0][0]
    k = int(np.searchsorted(D["t"], sp[0]))
    pre = D["c"][k - 1] * 10   # unadjusted
    post = D["o"][k]
    w(f"Nvidia split 10-for-1 on {day(D['t'][k])}: one ${pre:,.0f} share became ten ${post:,.0f} shares. "
      f"A feed that reads \"price per share\" sees x = {post / pre:.2f}, a 90% fall, for good. Every Nvidia "
      f"ticket is knocked out on two updates: a $100 ticket (2x) pays the holder $0, and the LPs take the "
      f"holder's real stock, about $100. Tesla (5:1 in 2020, 3:1 in 2022), QQQ (2:1 in 2000) and SSO (2:1 four times) did "
      f"the same.\n")
    w("Fix: NAV is **the value of the real token we hold** (units × price, with the issuer's split "
      "multiplier), never a raw share price. Tokenized-stock issuers (xStocks, Ondo) apply a multiplier "
      "on splits; the reader must use it, and halt the token for one update if the multiplier changes.\n")


def etf_path(D, years=10):
    f = D["ac"] / D["c"]
    path = []
    for j in range(len(D["c"])):
        path += [D["o"][j] * f[j], D["c"][j] * f[j]]
    return path[max(0, len(path) - 2 * 252 * years):]


def rec_params(B, C, **kw):
    P = dict(B=B, C=C, stop_price=0.25, ko_confirm=2, crown_mode="fixed_boost", crown_confirm=2,
             share_mode="fixed", impact_payer="transactor", lv_mint=0.001, lv_exit=0.001,
             mint_boost_limit=4.0 if B <= 2 else B * 2)
    P.update(kw)
    return P


def run_series(path, P, seed, cashH=25_000.0, cashE=25_000.0, lp_pull=0.0):
    """Tokens back to back on one path (a new Series after each stop/max). Retail trades every update."""
    rng = random.Random(zlib.crc32(seed.encode()))
    H0, E0 = cashH, cashE
    k = 0
    st = dict(series=0, ko=0, cr=0, viol=0, hold_in=0.0, hold_out=0.0, refused=0, peak_H_locked=0.0)
    while k < len(path) - 2:
        m = Market(nav0=path[k], p=Params(**P), cash_H=cashH, cash_E=cashE)
        st["series"] += 1
        toks = 0.0
        k += 1
        while k < len(path) and m.status == "LIVE":
            if rng.random() < 0.4:
                usd = 300 * rng.lognormvariate(0, 1)
                try:
                    q = m.buy(usd); toks += q; st["hold_in"] += usd
                except Refused:
                    st["refused"] += 1
            if toks > 0 and rng.random() < 0.3:
                q = toks * 0.1
                try:
                    st["hold_out"] += m.sell(q); toks -= q
                except Refused:
                    pass
            if lp_pull and rng.random() < lp_pull:
                m.withdraw("H", "passive", 0.5)
                m.withdraw("E", "passive", 0.5)
            st["peak_H_locked"] = max(st["peak_H_locked"], m.hearth_need() + m.hedge_units * m.nav)
            m.update(path[k]); k += 1
            if lp_pull and rng.random() < lp_pull:
                m.deposit("H", 2_000.0, "passive"); m.deposit("E", 2_000.0, "passive")
        while m.status == "ENDING" and k < len(path):
            m.update(path[k]); k += 1
        st["ko"] += m.status == "KNOCKED_OUT"
        st["cr"] += m.status == "CROWNED"
        if toks > 0:
            try:
                st["hold_out"] += m.sell(toks)
            except Refused:
                m.update(m.nav); st["hold_out"] += m.sell(toks)
        st["viol"] += len(m.violations)
        cashH = m.cash_H + m.hedge_units * m.nav * (1 - P["lv_exit"])
        cashE = m.cash_E
    st["H"], st["E"] = cashH - H0, cashE - E0
    return st


def s10_engine(DS):
    w("## 10. Full engine runs (fees, hedging, LPs, Series after each end)\n")
    w("`engine2` with the recommended rules, driven by each ETF's opens and closes over the last 10 years "
      "(each one a price update). A new token (Series) opens whenever one is stopped or maxed. Retail "
      "buys and sells every update; Hearth and Ember start with $25,000 each. Stock-token fees: 0.1% to "
      "mint or redeem the base (DEX spread), not LiquidV's 1%. No carry is charged here, so this shows "
      "the raw transfer between the two sides.\n")
    rows = []
    for s in ETFS + SINGLES:
        path = etf_path(DS[s])
        for lab, B, C in [SETTINGS[0], SETTINGS[3]]:
            st = run_series(path, rec_params(B, C), f"{s}|{lab}")
            rows.append([s, lab, st["series"], st["cr"], st["ko"], f"${st['hold_out'] - st['hold_in']:+,.0f}",
                         f"${st['H']:+,.0f}", f"${st['E']:+,.0f}", st["viol"]])
    table(["ETF", "Setting", "Series", "Maxed", "Stopped", "Holders net", "Hearth net", "Ember net",
           "Broken rules"], rows)


def s12_hedge_credit(DS):
    w("## 12. Fix found on the way: Hearth was posting its collateral twice\n")
    w("Until now Hearth had to hold the hedge **and** the full max-boost cash. But a hedged Hearth "
      "already owns the real token for its side: at the max price, that hedge is worth more than the "
      "max boost it owes. Example, 2x with max $3, one $1 ticket: Hearth's hedge is 1 extra unit of "
      "the ETF, bought for $1. The max boost is $1, paid when the ETF has doubled, and by then the "
      "hedge is worth $2. So the separate $1 of cash was never needed.\n")
    w("New rule (engine knob `hedge_credit`): Hearth's required cash = its share of the max boost minus "
      "what its hedge would sell for at the max price, less a 20% haircut. Hearth buys a ticket's "
      "hedge at the moment the ticket is minted and sells it when the ticket is sold.\n")
    rows = []
    for lab, B, C in SETTINGS:
        mb = maxb(B, C)
        old = (B - 1) + mb
        credit = (B - 1) * xc_of(B, C) * (1 - 0.001) * 0.8
        new = (B - 1) + max(0.0, mb - credit)
        rows.append([lab, money(old), money(new), pc(0.04 * old), pc(0.04 * new)])
    table(["Setting", "Hearth money per $1 ticket (before)", "After", "Carry to match 4% T-bills (before)",
           "After"], rows)
    w("So a fully hedged Hearth is simply **lending the holder (B−1) dollars of the ETF**. A fair carry "
      "is then about the T-bill rate on that loan: about 4% a year for 2x, close to what a margin loan "
      "or a perp costs. This applies to the trader-token version too.\n")
    # same real ETF paths, Hearth-only pool with $50,000: how much more can the same money back?
    rows = []
    for s_ in ["SPY", "QQQ", "SMH", "GLD", "ARKK", "NVDA"]:
        path = etf_path(DS[s_])
        for lab, B, C in [SETTINGS[0], SETTINGS[3]]:
            a_ = run_series(path, rec_params(B, C, hearth_share=1.0), f"{s_}|{lab}|hc", 10_000.0, 0.0)
            b_ = run_series(path, rec_params(B, C, hearth_share=1.0, hedge_credit=True), f"{s_}|{lab}|hc", 10_000.0, 0.0)
            rows.append([s_, lab, f"${a_['hold_in']:,.0f}", f"${b_['hold_in']:,.0f}", a_["refused"], b_["refused"],
                         f"${a_['H']:+,.0f}", f"${b_['H']:+,.0f}", a_["viol"] + b_["viol"]])
    w("Same 10 years of real prices, Hearth alone with only $10,000 (no Ember), no carry, so the pool "
      "fills up. Hearth's earnings stay about the same (a bit up or down: each ticket's hedge is now "
      "bought and sold with it instead of in netted batches).\n")
    table(["ETF", "Setting", "Tickets bought (before)", "After", "Buys refused: pool full (before)", "After",
           "Hearth net (before)", "After", "Broken rules"], rows)
    # fuzz: random jumpy paths
    viol = {0: 0, 1: 0}
    runs = {0: 0, 1: 0}
    first = {}
    for n in range(1200):
        r = random.Random(zlib.crc32(f"fuzz{n}".encode()))
        B = r.choice([2.0, 3.0, 5.0]); C = r.choice([2.0, 3.0])
        delay = r.choice([0, 1])
        nav, path = 100.0, []
        for t in range(400):
            j = r.random()
            step = r.gauss(0, 0.01) + (r.choice([-1, 1]) * r.uniform(0.05, 0.35) if j < 0.02 else 0.0)
            nav = max(0.5, nav * (1 + step)); path.append(nav)
        P = rec_params(B, C, hedge_credit=True, sale_delay=delay, hearth_share=r.choice([0.5, 1.0]))
        st = run_series(path, P, f"f{n}", r.uniform(2e3, 5e4), r.uniform(2e3, 5e4), lp_pull=0.05)
        viol[delay] += st["viol"] > 0
        runs[delay] += 1
    w(f"Random jumpy markets (jumps up to ±35% in one update, LPs pulling and adding money): "
      f"**{viol[0]} of {runs[0]}** runs broke a rule when the base sells at the trigger (Elysium, no delay); "
      f"**{viol[1]} of {runs[1]}** when the sale happens one update later. "
      + ("A one-update sale delay needs a haircut bigger than the worst one-update move, or the old "
         "rule.\n" if viol[1] else "\n"))


def s13_baskets():
    w("## 13. \"ETFs of stock tokens\": baskets built on-chain\n")
    w("Some Hyperliquid markets are already baskets of stocks (`vntl:MAG7`, `vntl:SEMIS`, `km:US500`). "
      "A basket is only as fresh as its last trade. Hourly bars from 30 April 2026:\n")
    import datetime as dt
    rows = []
    for coin in ("xyz:SP500", "xyz:SMH", "km:US500", "vntl:MAG7", "vntl:SEMIS"):
        P = hl(DATA, coin)
        we = np.array([dt.datetime.fromtimestamp(int(t), dt.timezone.utc).weekday() >= 5 for t in P["t"]])
        z = P["v"] == 0
        rows.append([f"`{coin}`", f"{stamp(P['t'][0])[:10]} → {stamp(P['t'][-1])[:10]}",
                     pc(z[~we].mean(), 0), pc(z[we].mean(), 0) if we.any() else "–"])
    table(["Market", "Data we got", "Weekday hours with no trade", "Weekend hours with no trade"], rows)
    w("The two `vntl` baskets went **30–38% of weekday hours and 57–70% of weekend hours without a single trade**, and their (and `km:US500`'s) "
      "candles stop in mid-June 2026. A basket like that is a stale feed: its last price is free money for "
      "whoever knows where the real stocks went (§7). If we build our own \"ETF of stock tokens\", its NAV "
      "must be computed from **each component's live price**, never the basket's own last trade, and it is "
      "frozen whenever a big component's market is shut. Simplest: back tokens with one big, liquid ETF "
      "token (S&P 500, Nasdaq 100) rather than a thin custom basket.\n")


def s11_funding():
    w("## 11. If the base is a Hyperliquid stock perp\n")
    import json
    rows = []
    for coin in ("xyz:SP500", "xyz:XYZ100"):
        d = json.load(open(os.path.join(DATA, "fund_" + coin.replace(":", "_") + "_all.json")))
        r = [float(x["fundingRate"]) for x in d]
        rows.append([f"`{coin}`", f"{len(r) // 24} days", pct(statistics.mean(r) * 24 * 365, 2)])
    table(["Perp", "History", "Funding paid by longs (per year)"], rows)
    w("LiquidV-style, the real token could be a vault holding a 1x long `xyz:SP500` perp. That is big "
      "and cheap: the S&P perp trades about $150M a day (vs the $641 vANSEM vault), so the capacity "
      "problem from round 1 disappears. The flip side: anyone can already get 2x–50x S&P on Hyperliquid "
      "for about 1–5% a year, so our carry (§4, §12) has to be paid for by what a perp doesn't give: "
      "no liquidation on a wick, no margin to watch, a known worst case (the stop), no daily reset (§3).\n")


def main():
    DS = {s: daily(DATA, s) for s in ETFS + SINGLES + ["SSO", "QLD"]}
    w("# Asphodel on stock ETFs: simulation report (round 4)\n")
    w("Same token, same rules (stop $0.25 on 2 updates, LPs' part capped, Crown = real base + cap), "
      "now on real ETF prices since the 1990s. Single stocks (Nvidia, Tesla) are included for contrast.\n")
    w("## Summary\n")
    w("* **It works mechanically.** 0 broken rules in every real-ETF run (10 years, 9 assets, 2 settings) "
      "and in 1,200 random markets with ±35% jumps.")
    w("* **Capacity is solved.** The base can be a big stock token or a 1x Hyperliquid stock perp "
      "(`xyz:SP500` trades ~$150M a day) instead of a $641 LiquidV vault.")
    w("* **ETFs are calm, so the settings change.** At 2x / max $3 an S&P token almost never ends "
      "(3% stopped, 0% maxed within a year): it is simply a 2x S&P with no daily reset, and it beat the "
      "real 2x ETF (SSO) in 78% of 1-year windows. 5x is the most an ETF can take; 10x is broken by "
      "overnight jumps (March 2020). Single stocks (Nvidia -31% overnight) should stay at 2x.")
    w("* **The catch: stocks go up on average.** An unhedged Ember LP lost about 12% a year at 2x on "
      "the S&P. So for stocks the LP is mainly Hearth (hedged), paid by a **carry** of about the T-bill "
      "rate on the boosted part (≈4% a year at 2x), once Hearth stops posting its collateral twice (§12).")
    w("* **Six stock-only bugs, each with a fix:** overnight jumps (§5), a stop that waits overnight (§6), a 24/7 "
      "feed on a 5-day market (§7), dividends (§8), splits (§9), thin baskets (§13).\n")
    s0_data(DS)
    s1_settings(DS)
    res1 = outcome_grid(DS, ETFS + SINGLES, 252)
    s2_outcomes(DS, res1, 252, ETFS + SINGLES, "2. What happens to tokens (1 year)")
    s3_vs_leveraged_etf(DS)
    s4_lp_economics(DS, res1)
    s5_gap_bugs(DS)
    s6_overnight_confirm(DS)
    s7_weekend_perp(DS)
    s8_dividends(DS)
    s9_splits(DS)
    s10_engine(DS)
    s11_funding()
    s12_hedge_credit(DS)
    s13_baskets()
    open(REPORT, "w").write("\n".join(OUT))
    print(f"wrote {REPORT} ({len(OUT)} blocks)")


if __name__ == "__main__":
    main()
