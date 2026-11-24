# Asphodel: Stocks section (baskets of tokenized stocks on Hyperliquid)

Status: **idea, for if Asphodel expands to stocks**. Companion to the Asphodel spec v0.5 · Draft v0.1 · Author: engineering · Target chain: Elysium (Kinetiq's L2 for Hyperliquid)

| Version | Change |
|---|---|
| **v0.1** | Asphodel's "real base, synthetic boost" with a **basket of stock tokens** (an "ETF") as the base instead of a trader token. Same rules: $1 start, one common zero at launch, stop $0.25 on 2 updates, LPs' part capped, Crown, Hearth/Ember. Adds what stocks change: market hours, weekends, dividends, splits, funding, the market's oracle. Numbers from real prices (§11) |

> This doc adds to the main spec; it doesn't change it. Anything not mentioned here works as in the main spec.

---

## 1. The idea in one example

In the main spec, Alice's money buys `$vANSEM`, a real token that follows a trader, and the Meadow backs the second gain.

Here the real token follows a **basket of stocks** instead of a trader. Call it `$vETF`.

**Example:** a basket called **AI Kings** holds NVDA 25%, TSLA 20%, PLTR 20%, COIN 15%, MSTR 10% and BTC 10%. Alice buys **$100 of AI Kings 2x**.

- Her $100 buys **$100 of `$vETF`**: $25 of NVDA, $20 of TSLA, and so on. That's her base, and it's real.
- The **Meadow** backs the extra gain, the same gain again.

| AI Kings since launch | Alice's real basket | From/to the Meadow | Alice has |
|---|---|---|---|
| +10% | $110 | Meadow pays her $10 | **$120** |
| −10% | $90 | she pays the Meadow $10 | **$80** |
| −37.5% (stop) | $62.50 | Meadow takes $37.50 | **$25** |
| +100% (max) | $200 | Meadow pays its max, $100 | **$300** (Crowned) |

Exactly the main spec's table, with "0xWhale's PnL" replaced by "the basket's value".

---

## 2. What the basket is

| | Trader token (main spec) | Stock basket (this doc) |
|---|---|---|
| Real token (base) | `$vTRADER`: LiquidV vault copying a trader | `$vETF`: a vault holding the basket's stocks |
| What moves it | The trader's PnL | The stocks' prices |
| Who picks it | The trader trades | A **curator** picks stocks and weights, once at launch |
| Price read from | HyperCore via the precompile | HyperCore via the precompile (the stock markets' prices) |
| Hours | 24/7 | The stocks' real market: weekdays; weekends are special (§5) |

**Three kinds of basket, in order of safety:**

1. **Index:** S&P 500 or Nasdaq-100. Hyperliquid already lists them as single markets (`xyz:SP500`, `xyz:XYZ100`), so the base is one position.
2. **Sector baskets** made by us: chips, AI, energy, and so on.
3. **Curator baskets:** anyone builds one, and the curator earns a fee, as a trader does in the main spec. Basket rules (same as Kickoff Stocks uses):
   - 3–10 stocks, each at most 50%;
   - BTC/ETH up to 20% together;
   - weights fixed at launch; a basket with the same stocks and weights (to 1%) as an existing one joins it instead of launching a copy.

**The base on Hyperliquid:**
- The stocks trade there as perps (HIP-3 markets), not shares. So `$vETF` is a vault holding **1x long perps** in the basket's weights.
- At 1x, a position is only liquidated if a stock goes almost to zero.
- LiquidV already tokenizes perp positions, so it could run `$vETF` vaults and keep Asphodel's role the same as in the main spec.

---

## 3. Pricing: unchanged

```
x      = $vETF NAV now / $vETF NAV at launch
base   = x
boost  = (B − 1) × (x − 1), capped at MAXB    where MAXB = (B − 1) × (C − 1) / B
price  = max(0, base + boost)                 = 1 + B × (x − 1) until the max
```

- **One common zero:** each basket token starts at **$1.00** at its launch and keeps that zero until a Crown or stop. A new Series opens only after a Crown or stop, as in the main spec.
- **Late buyers** buy at the current price and see their live boost (B × x / price).
- **Stop:** $0.25 on 2 updates. **Crown:** the Meadow pays exactly MAXB, and the holder gets the base's real sale value + MAXB.

---

## 4. Settings: stocks are calmer than traders

Over one year, followed from launch to its stop, its max or 12 months:

| Basket | Setting | Stopped | Maxed | Holder median | Meadow short |
|---|---|---|---|---|---|
| S&P 500 | 2x, max $3 | 0% | 0% | +29% | never |
| S&P 500 | 3x, max $2 | 1% | 6% | +44% | never |
| S&P 500 | 5x, max $2 | 25% | 40% | +70% | never |
| Chips (NVDA 40, AMD 30, SPY 30) | 2x, max $3 | 10% | 29% | +73% | never |
| Chips | 3x, max $2 | 30% | 63% | +100% | never |
| AI Kings | 2x, max $3 | 20% | 41% | +52% | never |
| AI Kings | 3x, max $2 | 36% | 55% | +100% | never |
| AI Kings | 5x, max $2 | 46% | 54% | +100% | 1 in 270 |

These are real prices from April 2021 to November 2026, with a token launched every week.

The **S&P since 1993** (from the round-4 simulation) tells the same story:
- 2x was stopped in 3% of years and never maxed.
- It beat the real 2x S&P ETF (SSO), which resets daily, in 78% of 1-year windows.
- **10x broke:** on 16 March 2020 the S&P opened −10.4%, past $0 in one jump.

**What sets the safe boost: the biggest jump while the market is shut.** The $0.25 left at the stop is a cushion worth 0.25 ÷ B of basket move (12.5% at 2x, 8.3% at 3x, 5% at 5x). Biggest jumps (Friday close → Monday open, 5 August 2024):

| Basket | Worst jump |
|---|---|
| S&P 500 | −4.0% |
| Chips | −9.2% |
| AI Kings | −14.5% |
| Nvidia alone (any time since 1999, on earnings) | −31% |

**Recommended maximum boost:**

| Basket | Max boost |
|---|---|
| S&P 500 / Nasdaq-100 | 5x (2x default) |
| Sector baskets | 3x |
| Curator baskets with hot stocks or crypto | 2x |
| Single stocks | 2x, and no new tokens before earnings |
| Any basket | Never 10x |

The main spec's **gap guard** does the rest: it refuses mints when the distance to the stop is smaller than k × B × the basket's biggest recent jump.

---

## 5. Market hours: the big new problem

Traders trade all the time. Stocks only really trade **Monday to Friday**. Hyperliquid's stock perps keep trading at weekends, but thinly: only about **7%** of the S&P perp's volume is at weekends. So there are two prices:
- the perp's price, which is what the base really sells at;
- the real market's price, which is frozen.

**Rules**

| When | Mints | Sells | Stop / Max |
|---|---|---|---|
| US market open | Open | Open | Live |
| Weeknights (perp trades, market shut) | Open, with the gap guard | Open | Live, confirmed by time (2 updates ≥ 60 s apart) |
| Weekend and holidays | **Closed** | Open: the base sells at its real price, and the Meadow's boost part uses a 1-hour average price | **Paused** until Monday's open |
| A stock halted, or its market paused | Closed for baskets holding it | Waits | Paused |

**Why each rule:**

1. **Mints closed at weekends.** In 29 weekends, the Sunday-night S&P perp called the direction of Monday's real open **86%** of the time. Buying a 5x token at a stale price would make about **+2% a weekend** from the Meadow. (The fill rule from the main spec already says never fill at an old price; this is the same rule applied to weekends.)
2. **Stop/max paused at weekends.** A thin weekend market shouldn't knock out or Crown a token that the real market would reprice on Monday.
3. **Boost part on an average at weekends.** It makes pushing the thin weekend perp up or down to cash out against the Meadow expensive.

**The cost:** the Monday open is one jump for paused tokens. That's why the boost limits in §4 use the Friday-to-Monday jump.

**A stop that waits overnight.** If the first update below the stop is the last one before the market shuts, the second is the next morning, and the holder carries the whole night's jump. In the round-4 test, that cost up to $0.35 extra per $1 ticket at 10x. Fix: confirm by time while the market is open; never carry a half-confirmed stop into a close.

---

## 6. Dividends, splits, funding

1. **Dividends.**
   - Perps don't pay dividends, so `$vETF` trails holding the real stocks by the dividend yield (about 1% a year on the S&P). Disclose it.
   - The boost is read from `$vETF`'s own NAV, so holders and the Meadow are treated the same.
   - If the base is ever real stock tokens that pay dividends, the price must include dividends (total return) and pass them to holders. Otherwise, at 5x, about $4.32 per $100 a year goes to the Meadow for nothing.
2. **Splits.**
   - Read with a raw share price, a split looks like a crash: Nvidia's 10-for-1 in June 2024 reads as −90% and would knock out every token.
   - The NAV must be the **vault's value**, never a raw share price.
   - Each HIP-3 market's split rule must be checked before listing.
   - Any one-update move over 30% in a single stock pauses that basket until checked against a second price source.
3. **Funding.**
   - Longs pay funding on Hyperliquid. Measured over 205 days to November 2026: **+1.05% a year on `xyz:SP500`** and **+4.91% on `xyz:XYZ100`**.
   - It's paid by `$vETF` (the base), so it's the holder's cost on their own part. Show it on the token page.
   - When a stock's funding is above a limit, stop minting baskets that hold it.

---

## 7. LPs: stocks go up on average

Trader tokens have no built-in upward drift, because most traders lose. Stocks do.

| Basket | Setting | Meadow result over a year (avg per $1 ticket) |
|---|---|---|
| S&P 500 | 2x | **−11.5¢** |
| AI Kings | 2x | **−33¢** |

So for stocks:
- **Hearth is the main pool.** It holds the same basket (long perps) as its hedge, so it's neutral and earns fees.
- **Ember is optional,** for people who want to bet against a basket with a capped loss. It needs its own capacity cap.
- **Carry:** holders pay Hearth about the T-bill rate on the boosted part: **~4% a year at 2x**, charged as a slow carry on the price (the main spec's "× carry").

**Hearth's hedge counts as its collateral.** At the max price, Hearth's hedge is worth more than the max boost it owes.
- Example (2x, max $3): the hedge is $1 of basket per ticket. It's worth $2 when the basket has doubled, and Hearth owes $1.
- So Hearth's required cash = its share of MAXB **minus** the hedge's value at the max, less a 20% haircut.
- Hearth's money per $1 ticket falls from **$2.00 to $1.00** at 2x.
- Tested with the simulator's `hedge_credit` option: 0 broken rules on 10 years of real ETF prices and 1,200 random markets with ±35% jumps.
- On Hyperliquid, Hearth's long perps only need margin, so its money per ticket falls further. The hedge still counts only after a haircut for liquidation and funding.

Everything else is as in the main spec:
- coverage per pool;
- withdrawals from free capital only;
- the Hearth/Ember split fixed at mint;
- the hedge fee;
- sellers get the base's real sale value.

---

## 8. Hyperliquid's stock markets

HIP-3 markets that list stocks: `xyz` has 130+ markets; `km`, `flx`, `cash` and `vntl` have more. A day's trading (21 November 2026):

| Market | Volume that day | | Market | Volume that day |
|---|---|---|---|---|
| `xyz:XYZ100` | ~$300M | | `xyz:COIN` | ~$17M |
| `xyz:SP500` | ~$151M | | `xyz:AAPL` | ~$17M |
| `xyz:NVDA` | ~$141M | | `xyz:META` | ~$16M |
| `xyz:MU` | ~$44M | | `xyz:AMD` | ~$9M |
| `xyz:GOOGL` | ~$35M | | `xyz:TSLA` | ~$8M |
| `xyz:MSTR` | ~$18M | | `xyz:PLTR` | ~$2M |

That's hundreds to thousands of times deeper than LiquidV's trader vaults ($9–$1,334), so the main spec's capacity blocker doesn't apply here.

**Hyperliquid-only bugs and fixes**

1. **Dead or thin markets.**
   - Example: `vntl:MAG7` and `vntl:SEMIS` are ready-made baskets. They had **no trade in 30–38% of weekday hours and 57–70% of weekend hours**, and their data (and `km:US500`'s) stops in mid-June 2026.
   - Fix: list only markets above a minimum daily volume and open interest. Build baskets from single-stock perps, not from basket perps. Pause a basket when any component goes quiet.
2. **The market's deployer runs its oracle.** A HIP-3 deployer can halt a market or set its price.
   - Fix: list only established deployers, and cap how much of the Meadow one deployer's markets can back. A halt pauses the basket.
3. **Open-interest caps.** Each market has a cap on open interest (e.g. on `xyz:NVDA`).
   - Fix: count the `$vETF` vaults' and Hearth's positions against each cap, and stop minting well before it.
4. **Funding spikes** (§6).

---

## 9. Guardrails added for stocks

On top of the main spec's guardrails:

- A boost limit per basket kind (§4). Never 10x.
- No new tokens holding a stock in the hour before its earnings.
- Weekends: mints closed, stop/max paused, sells open with the boost part on a 1-hour average.
- The stop confirms by time while the market is open, and never carries half-confirmed into a close.
- NAV = the `$vETF` vault's value, never a raw share price.
- Pause on a single-stock move over 30% in one update until checked against a second source.
- Pause on a halted, quiet or paused component.
- Listing minimums for each market (volume, open interest, deployer).
- Mint limits from open-interest caps and funding.
- Hearth's hedge counts as collateral, after a haircut.
- Carry about the T-bill rate on the boosted part.

---

## 10. Open questions

1. **Who runs `$vETF`:** LiquidV (partner) or our own vaults?
2. **Weekend sells:** is a 1-hour average enough, or should sells also close at weekends?
3. **Ember for stocks:** on at launch, or Hearth only?
4. **Curator baskets:** what fee for curators, and a minimum size before boosted tokens open?
5. **Which HIP-3 deployers** to list, and how each handles splits and halts.
6. **Rolling to real stock tokens** (e.g. tokenized stocks bridged to Elysium) later: these need dividends passed through and a total-return price.
7. **Legal:** boosted exposure to stocks may be treated differently from trader tokens, depending on the region.

---

## 11. Data behind the numbers

- **Yahoo Finance daily prices** (split- and dividend-adjusted):
  - S&P 500, Nasdaq-100, small caps, semiconductors, gold, Treasuries and ARKK since the 1990s/2000s;
  - NVDA, TSLA, PLTR, COIN, MSTR, AMD and BTC from April 2021.
  - Limits: daily bars, with stops/maxes during the day assumed to fill at their level; 2021–2026 is a mostly rising market.
- **Hourly prices**, last 2 years, for the overnight-stop test.
- **Hyperliquid API** (21 November 2026):
  - HIP-3 market list and daily volume;
  - hourly candles since 30 April 2026 (weekend tests);
  - funding history for `xyz:SP500` and `xyz:XYZ100`.
- **Asphodel simulator, round 4:** `asphodel-sim/sim/stocks.py` → `asphodel-sim/STOCKS-REPORT.md`, plus the `hedge_credit` option in `asphodel-sim/sim/engine2.py`.
