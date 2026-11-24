"""Load stock / ETF price data (Yahoo daily + hourly, Hyperliquid HIP-3 hourly). Data is untrusted: parsed as numbers only."""
import json, os, datetime as dt
import numpy as np


def _f(v):
    return np.array([np.nan if a is None else float(a) for a in v], dtype=float)


def daily(d, sym):
    """Daily bars. Prices are split-adjusted. 'tr' scales each bar to total return (dividends reinvested)."""
    r = json.load(open(os.path.join(d, f"d_{sym}.json")))["chart"]["result"][0]
    q = r["indicators"]["quote"][0]
    t = np.array(r["timestamp"], dtype=np.int64)
    o, h, l, c = _f(q["open"]), _f(q["high"]), _f(q["low"]), _f(q["close"])
    ac = _f(r["indicators"]["adjclose"][0]["adjclose"])
    ok = ~(np.isnan(o) | np.isnan(h) | np.isnan(l) | np.isnan(c) | np.isnan(ac)) & (o > 0) & (c > 0)
    t, o, h, l, c, ac = t[ok], o[ok], h[ok], l[ok], c[ok], ac[ok]
    ev = r.get("events", {})
    divs = {int(v["date"]): float(v["amount"]) for v in ev.get("dividends", {}).values()}
    splits = []
    for v in ev.get("splits", {}).values():
        a, b = str(v["splitRatio"]).split(":")
        splits.append((int(v["date"]), float(a) / float(b)))
    return dict(sym=sym, t=t, o=o, h=h, l=l, c=c, ac=ac, divs=divs, splits=sorted(splits))


def hourly(d, sym):
    r = json.load(open(os.path.join(d, f"h_{sym}.json")))["chart"]["result"][0]
    q = r["indicators"]["quote"][0]
    t = np.array(r["timestamp"], dtype=np.int64)
    o, h, l, c = _f(q["open"]), _f(q["high"]), _f(q["low"]), _f(q["close"])
    ok = ~(np.isnan(o) | np.isnan(c) | np.isnan(h) | np.isnan(l))
    t, o, h, l, c = t[ok], o[ok], h[ok], l[ok], c[ok]
    # a new session starts when the gap to the previous bar is > 2 hours
    new = np.r_[True, np.diff(t) > 7200]
    return dict(sym=sym, t=t, o=o, h=h, l=l, c=c, new=new)


def hl(d, coin):
    f = os.path.join(d, "hl_" + coin.replace(":", "_") + ".json")
    rows = json.load(open(f))
    t = np.array([int(x["t"]) // 1000 for x in rows], dtype=np.int64)
    o = np.array([float(x["o"]) for x in rows]); c = np.array([float(x["c"]) for x in rows])
    h = np.array([float(x["h"]) for x in rows]); l = np.array([float(x["l"]) for x in rows])
    v = np.array([float(x["v"]) for x in rows])
    return dict(coin=coin, t=t, o=o, h=h, l=l, c=c, v=v)


def day(ts):
    return dt.datetime.fromtimestamp(int(ts), dt.timezone.utc).strftime("%Y-%m-%d")


def stamp(ts):
    return dt.datetime.fromtimestamp(int(ts), dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
