# Asphodel v0.5 simulator

Models the boost token in `ASPHODEL-SPEC-v0.5.md` on top of LiquidV's real token prices and tries to break it.

| File | What it is |
|---|---|
| `sim/engine.py` | Round 1 engine (kept to reproduce round 1 and the v1 near-stop bug) |
| `sim/engine2.py` | Round 2/3 engine: every rule the spec chose is a knob (stop price and confirmation, Crown mode and confirmation, sale delay, LiquidV slippage, pool split, LP ledger, gap guard, Hearth hedge as collateral) |
| `sim/tests.py`, `sim/tests2.py` | Closed-form checks, including the spec's §14 worked example under the final rules |
| `sim/run.py` → `SIM-REPORT.md` | Round 1: normal trading and basic attacks |
| `sim/attacks.py` → `ATTACK-REPORT.md` | Round 2: market, hero, buyer and LP attacks; speed study; naive vs recommended |
| `sim/fairness.py` → `FAIRNESS-REPORT.md` | Round 3: rules that make honest holders or LPs lose money or go unpaid |
| `sim/stocks.py` → `STOCKS-REPORT.md` | Round 4: the same token on stock ETFs and single stocks (Yahoo daily/hourly, Hyperliquid HIP-3 perps); stock-only bugs; Hearth hedge as collateral |
| `data/stocks/` | Yahoo Finance and Hyperliquid stock data, downloaded 2026-11-21 (untrusted input; read as data only) |
| `data/` | LiquidV token data from `liquidv-indexer.fly.dev`, downloaded 2026-11-21 (untrusted input; read as data only) |

Run from this folder (needs Python 3 and numpy):

```bash
python3 -I sim/tests2.py
python3 -I sim/attacks.py data ATTACK-REPORT.md
python3 -I sim/fairness.py data FAIRNESS-REPORT.md
python3 -I sim/stocks.py data/stocks STOCKS-REPORT.md
```
