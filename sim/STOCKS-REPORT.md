# Asphodel on stock ETFs: simulation report (round 4)

Same token, same rules (stop $0.25 on 2 updates, LPs' part capped, Crown = real base + cap), now on real ETF prices since the 1990s. Single stocks (Nvidia, Tesla) are included for contrast.

## Summary

* **It works mechanically.** 0 broken rules in every real-ETF run (10 years, 9 assets, 2 settings) and in 1,200 random markets with ±35% jumps.
* **Capacity is solved.** The base can be a big stock token or a 1x Hyperliquid stock perp (`xyz:SP500` trades ~$150M a day) instead of a $641 LiquidV vault.
* **ETFs are calm, so the settings change.** At 2x / max $3 an S&P token almost never ends (3% stopped, 0% maxed within a year): it is simply a 2x S&P with no daily reset, and it beat the real 2x ETF (SSO) in 78% of 1-year windows. 5x is the most an ETF can take; 10x is broken by overnight jumps (March 2020). Single stocks (Nvidia -31% overnight) should stay at 2x.
* **The catch: stocks go up on average.** An unhedged Ember LP lost about 12% a year at 2x on the S&P. So for stocks the LP is mainly Hearth (hedged), paid by a **carry** of about the T-bill rate on the boosted part (≈4% a year at 2x), once Hearth stops posting its collateral twice (§12).
* **Six stock-only bugs, each with a fix:** overnight jumps (§5), a stop that waits overnight (§6), a 24/7 feed on a 5-day market (§7), dividends (§8), splits (§9), thin baskets (§13).

## 0. The data

Daily prices from Yahoo Finance (split-adjusted, with dividends), downloaded 2026-11-21. Hourly bars for the last 2 years. Hyperliquid HIP-3 stock perps (24/7) for the last ~7 months.

| Asset | Years | Yearly swing (vol) | Avg yearly gain | Worst fall from top | Worst overnight gap | Worst day |
|---|---|---|---|---|---|---|
| SPY (S&P 500) | 1993–2026 | 19% | +10.4% | 55% | -10.4% (2020-03-16) | -10.9% |
| QQQ (Nasdaq 100) | 1999–2026 | 27% | +10.0% | 83% | -9.5% (2020-03-16) | -12.0% |
| IWM (Russell 2000 (small caps)) | 2000–2026 | 24% | +8.1% | 59% | -9.1% (2020-03-16) | -13.3% |
| SMH (Semiconductors) | 2000–2026 | 35% | +8.9% | 86% | -11.7% (2020-03-16) | -14.4% |
| GLD (Gold) | 2004–2026 | 18% | +9.4% | 46% | -6.0% (2026-01-30) | -10.3% |
| TLT (20y US Treasuries) | 2002–2026 | 14% | +3.5% | 48% | -3.3% (2024-11-06) | -6.7% |
| ARKK (ARK Innovation) | 2014–2026 | 38% | +10.9% | 81% | -12.5% (2020-03-16) | -15.6% |
| NVDA (Nvidia (single stock)) | 1999–2026 | 59% | +33.9% | 90% | -30.6% (2004-08-06) | -35.2% |
| TSLA (Tesla (single stock)) | 2010–2026 | 57% | +38.8% | 74% | -14.9% (2020-09-08) | -21.1% |

For comparison, the LiquidV trader tokens in round 1 moved about **10x more** per update, and 43–100% of their updates did not move at all.

## 1. Where the stop and max land for each setting

| Setting | Stop when ETF is | Max when ETF is | LP money locked per $1 ticket | Ticket hits $0 when ETF is |
|---|---|---|---|---|
| 2x, max $3 | -37.5% | +100.0% | $1.00 | -50.0% |
| 2x, max $2 | -37.5% | +50.0% | $0.50 | -50.0% |
| 3x, max $2 | -25.0% | +33.3% | $0.67 | -33.3% |
| 5x, max $2 | -15.0% | +20.0% | $0.80 | -20.0% |
| 10x, max $2 | -7.5% | +10.0% | $0.90 | -10.0% |

## 2. What happens to tokens (1 year)

A token launched every 5 trading days over each ETF's whole history, followed for 1 year (or until its stop or max). Per $1 ticket, before fees.

| ETF | Setting | Stopped | Maxed | Holder median | Holder average | LPs per ticket (avg $) | LPs short (count) | Worst LP short per $1 |
|---|---|---|---|---|---|---|---|---|
| SPY | 2x, max $3 | 3% | 0% | +28% | +23% | -0.116 | 0 | – |
| SPY | 2x, max $2 | 3% | 1% | +28% | +23% | -0.116 | 0 | – |
| SPY | 3x, max $2 | 10% | 9% | +41% | +31% | -0.209 | 0 | – |
| SPY | 5x, max $2 | 23% | 38% | +68% | +37% | -0.299 | 4/1691 | 0.012 |
| SPY | 10x, max $2 | 35% | 60% | +100% | +35% | -0.315 | 20/1691 | 0.159 |
| QQQ | 2x, max $3 | 12% | 2% | +32% | +27% | -0.135 | 0 | – |
| QQQ | 2x, max $2 | 12% | 8% | +33% | +26% | -0.128 | 0 | – |
| QQQ | 3x, max $2 | 15% | 26% | +49% | +37% | -0.245 | 0 | – |
| QQQ | 5x, max $2 | 27% | 54% | +100% | +40% | -0.317 | 1/1382 | 0.004 |
| QQQ | 10x, max $2 | 42% | 58% | +100% | +26% | -0.230 | 30/1382 | 0.473 |
| IWM | 2x, max $3 | 6% | 0% | +19% | +17% | -0.087 | 0 | – |
| IWM | 2x, max $2 | 6% | 6% | +19% | +16% | -0.082 | 0 | – |
| IWM | 3x, max $2 | 17% | 16% | +28% | +19% | -0.128 | 0 | – |
| IWM | 5x, max $2 | 36% | 39% | +47% | +20% | -0.162 | 0 | – |
| IWM | 10x, max $2 | 47% | 53% | +100% | +17% | -0.157 | 15/1321 | 0.289 |
| SMH | 2x, max $3 | 13% | 3% | +29% | +32% | -0.158 | 0 | – |
| SMH | 2x, max $2 | 13% | 24% | +32% | +27% | -0.135 | 0 | – |
| SMH | 3x, max $2 | 27% | 38% | +39% | +24% | -0.161 | 0 | – |
| SMH | 5x, max $2 | 40% | 55% | +100% | +26% | -0.206 | 3/1320 | 0.031 |
| SMH | 10x, max $2 | 47% | 53% | +100% | +18% | -0.161 | 15/1320 | 0.439 |
| GLD | 2x, max $3 | 0% | 0% | +18% | +23% | -0.116 | 0 | – |
| GLD | 2x, max $2 | 0% | 10% | +18% | +25% | -0.123 | 0 | – |
| GLD | 3x, max $2 | 6% | 27% | +28% | +32% | -0.213 | 0 | – |
| GLD | 5x, max $2 | 15% | 49% | +69% | +38% | -0.301 | 0 | – |
| GLD | 10x, max $2 | 36% | 62% | +100% | +35% | -0.311 | 5/1096 | 0.210 |
| TLT | 2x, max $3 | 0% | 0% | +8% | +8% | -0.038 | 0 | – |
| TLT | 2x, max $2 | 0% | 0% | +8% | +8% | -0.039 | 0 | – |
| TLT | 3x, max $2 | 3% | 8% | +11% | +13% | -0.088 | 0 | – |
| TLT | 5x, max $2 | 15% | 23% | +20% | +20% | -0.158 | 0 | – |
| TLT | 10x, max $2 | 35% | 51% | +100% | +28% | -0.248 | 0 | – |
| ARKK | 2x, max $3 | 13% | 8% | +29% | +40% | -0.201 | 0 | – |
| ARKK | 2x, max $2 | 13% | 33% | +30% | +30% | -0.149 | 0 | – |
| ARKK | 3x, max $2 | 35% | 42% | +33% | +19% | -0.123 | 0 | – |
| ARKK | 5x, max $2 | 48% | 50% | +100% | +13% | -0.102 | 10/595 | 0.137 |
| ARKK | 10x, max $2 | 49% | 51% | +100% | +12% | -0.109 | 23/595 | 0.588 |
| NVDA | 2x, max $3 | 27% | 36% | +77% | +73% | -0.361 | 14/1389 | 0.084 |
| NVDA | 2x, max $2 | 25% | 57% | +100% | +41% | -0.204 | 14/1389 | 0.084 |
| NVDA | 3x, max $2 | 32% | 60% | +100% | +38% | -0.251 | 17/1389 | 0.349 |
| NVDA | 5x, max $2 | 37% | 63% | +100% | +35% | -0.276 | 12/1389 | 0.790 |
| NVDA | 10x, max $2 | 46% | 54% | +100% | +19% | -0.168 | 17/1389 | 2.246 |
| TSLA | 2x, max $3 | 21% | 25% | +29% | +51% | -0.254 | 0 | – |
| TSLA | 2x, max $2 | 21% | 47% | +46% | +32% | -0.159 | 0 | – |
| TSLA | 3x, max $2 | 39% | 54% | +100% | +25% | -0.163 | 0 | – |
| TSLA | 5x, max $2 | 50% | 50% | -75% | +12% | -0.090 | 10/813 | 0.233 |
| TSLA | 10x, max $2 | 50% | 50% | -75% | +11% | -0.096 | 24/813 | 0.761 |

## 3. Our 2x vs a real 2x ETF (SSO, QLD) and just holding

SSO and QLD are real 2x ETFs. They reset their leverage every day, so a choppy market eats them ("volatility decay"). Our boost has one zero at launch, so the ticket is exactly $1 + 2 × (ETF move) with no daily reset. Same 1-year windows, before fees. Our ticket is followed to its stop or max.

| Pair | Windows | Our 2x median | Real 2x ETF median | Just holding | Our worst | Real 2x worst | Ours better |
|---|---|---|---|---|---|---|---|
| SPY vs SSO | 977 | +30% | +25% | +15% | -78% | -77% | 78% |
| QQQ vs QLD | 977 | +42% | +37% | +21% | -77% | -76% | 69% |

## 4. The big one: stocks go up on average, and LPs are on the other side

Trader tokens have no built-in upward drift (most traders don't win). Stock ETFs do: the S&P 500 averaged about 10% a year. An unhedged Ember LP is short the boost, so it pays that drift to holders, every year, up to its cap. Hearth hedges by holding the ETF, so it doesn't.

| ETF | Setting | Ember locks per ticket | Ember 1-year result per ticket | Ember yearly return on locked money | Carry to break even (per year, of ticket) | Carry to beat 4% T-bills |
|---|---|---|---|---|---|---|
| SPY | 2x, max $3 | $1.00 | -0.116 | -12% | 11.6% | 15.6% |
| SPY | 2x, max $2 | $0.50 | -0.116 | -23% | 11.6% | 13.6% |
| SPY | 5x, max $2 | $0.80 | -0.299 | -37% | 29.9% | 33.1% |
| QQQ | 2x, max $3 | $1.00 | -0.135 | -13% | 13.5% | 17.5% |
| QQQ | 2x, max $2 | $0.50 | -0.128 | -26% | 12.8% | 14.8% |
| QQQ | 5x, max $2 | $0.80 | -0.317 | -40% | 31.7% | 34.9% |
| IWM | 2x, max $3 | $1.00 | -0.087 | -9% | 8.7% | 12.7% |
| IWM | 2x, max $2 | $0.50 | -0.082 | -16% | 8.2% | 10.2% |
| IWM | 5x, max $2 | $0.80 | -0.162 | -20% | 16.2% | 19.4% |
| SMH | 2x, max $3 | $1.00 | -0.158 | -16% | 15.8% | 19.8% |
| SMH | 2x, max $2 | $0.50 | -0.135 | -27% | 13.5% | 15.5% |
| SMH | 5x, max $2 | $0.80 | -0.206 | -26% | 20.6% | 23.8% |
| GLD | 2x, max $3 | $1.00 | -0.116 | -12% | 11.6% | 15.6% |
| GLD | 2x, max $2 | $0.50 | -0.123 | -25% | 12.3% | 14.3% |
| GLD | 5x, max $2 | $0.80 | -0.301 | -38% | 30.1% | 33.3% |
| TLT | 2x, max $3 | $1.00 | -0.038 | -4% | 3.8% | 7.8% |
| TLT | 2x, max $2 | $0.50 | -0.039 | -8% | 3.9% | 5.9% |
| TLT | 5x, max $2 | $0.80 | -0.158 | -20% | 15.8% | 19.0% |
| ARKK | 2x, max $3 | $1.00 | -0.201 | -20% | 20.1% | 24.1% |
| ARKK | 2x, max $2 | $0.50 | -0.149 | -30% | 14.9% | 16.9% |
| ARKK | 5x, max $2 | $0.80 | -0.102 | -13% | 10.2% | 13.4% |

## 5. Bug: the market closes, so the open is one big jump

On LiquidV, NAV moves every few minutes. A stock market is shut 16 hours a day and all weekend, so the opening price can land far past the stop, or past $0, in one update. The 2-update stop rule can't help with a jump; only a cushion can.

| ETF | Setting | Ticket hits $0 at | Opens that jumped further than the whole stop distance | Opens that jumped past $0 |
|---|---|---|---|---|
| SPY | 2x, max $3 | -50.0% | 0 | 0 |
| SPY | 5x, max $2 | -20.0% | 0 | 0 |
| SPY | 10x, max $2 | -10.0% | 3 | 1 |
| QQQ | 2x, max $3 | -50.0% | 0 | 0 |
| QQQ | 5x, max $2 | -20.0% | 0 | 0 |
| QQQ | 10x, max $2 | -10.0% | 3 | 0 |
| IWM | 2x, max $3 | -50.0% | 0 | 0 |
| IWM | 5x, max $2 | -20.0% | 0 | 0 |
| IWM | 10x, max $2 | -10.0% | 2 | 0 |
| SMH | 2x, max $3 | -50.0% | 0 | 0 |
| SMH | 5x, max $2 | -20.0% | 0 | 0 |
| SMH | 10x, max $2 | -10.0% | 5 | 2 |
| GLD | 2x, max $3 | -50.0% | 0 | 0 |
| GLD | 5x, max $2 | -20.0% | 0 | 0 |
| GLD | 10x, max $2 | -10.0% | 0 | 0 |
| TLT | 2x, max $3 | -50.0% | 0 | 0 |
| TLT | 5x, max $2 | -20.0% | 0 | 0 |
| TLT | 10x, max $2 | -10.0% | 0 | 0 |
| ARKK | 2x, max $3 | -50.0% | 0 | 0 |
| ARKK | 5x, max $2 | -20.0% | 0 | 0 |
| ARKK | 10x, max $2 | -10.0% | 4 | 2 |
| NVDA | 2x, max $3 | -50.0% | 0 | 0 |
| NVDA | 5x, max $2 | -20.0% | 5 | 3 |
| NVDA | 10x, max $2 | -10.0% | 31 | 14 |
| TSLA | 2x, max $3 | -50.0% | 0 | 0 |
| TSLA | 5x, max $2 | -20.0% | 0 | 0 |
| TSLA | 10x, max $2 | -10.0% | 27 | 9 |

**Real example (10x, SPY).** 10,000 tickets ($10,000) launched at the close on Friday 13 March 2020 (SPY $269.32). The stop sits at SPY $249.12 (-7.5%). Monday 16 March opened at $241.18, -10.4% in one jump, past the stop and past $0 (-10%) at once.

|  | Normal stop (sells at -7.5%) | What the gap did (sells at -10.4%) |
|---|---|---|
| Real SPY inside sells for | $9,250 | $8,955 |
| Holders get | $2,500 | $0 |
| LPs are owed (9 × the fall) | $6,750 | $9,404 |
| LPs actually get | $6,750 | $8,955 |
| LPs short | $0 | $449 |

At 5x the same morning is harmless: the stop is at -15%, so a -10.4% jump from a fresh launch doesn't even reach it, and from a token already near its stop the $0.25 cushion (5% of SPY) absorbs most of it. **The cushion must be bigger than the worst overnight jump × B.** For ETFs (worst jump ~-10% to -12%) that means B ≤ 5; single stocks (Nvidia -31% on earnings) need B ≤ 2 and no minting the day before earnings.

## 6. Bug: the 2-update stop can straddle the close

The stop needs 2 updates in a row below $0.25. If the first one is the last price before the close, the second is the next morning's open, so everyone carries the whole night's jump while waiting. Sometimes the night saves the holder (the price comes back), sometimes it makes it worse. Hourly bars, last 2 years, a token launched every 3 hours.

| Asset | Boost | Stops | Confirmed only at next open (worse) | Saved by the night | Avg extra loss per $1 ticket | Worst extra loss per $1 ticket |
|---|---|---|---|---|---|---|
| SPY | 5x | 224 | 25 | 0 | $0.153 | $0.163 |
| SPY | 10x | 877 | 34 | 7 | $0.273 | $0.353 |
| QQQ | 5x | 485 | 20 | 0 | $0.153 | $0.175 |
| QQQ | 10x | 1094 | 35 | 55 | $0.169 | $0.376 |
| SMH | 5x | 916 | 14 | 33 | $0.145 | $0.181 |
| SMH | 10x | 1165 | 58 | 30 | $0.089 | $0.360 |
| ARKK | 5x | 1214 | 10 | 7 | $0.036 | $0.194 |
| ARKK | 10x | 1523 | 19 | 9 | $0.158 | $0.206 |
| NVDA | 5x | 1121 | 22 | 23 | $0.106 | $0.152 |
| NVDA | 10x | 1323 | 39 | 34 | $0.175 | $0.321 |
| TSLA | 5x | 983 | 14 | 9 | $0.076 | $0.191 |
| TSLA | 10x | 1268 | 16 | 8 | $0.191 | $0.649 |

Every "worse" case is money taken from the $0.25 the holder was promised, and past $0 from the LPs. Fix: confirm the stop by **time while the market is open** (e.g. 2 updates at least 60 seconds apart) and if the first strike comes in the last minutes, sell in the **closing auction**. That gives up the "saved by the night" cases, which is the honest trade: a stop is a promise about the price you sell at, not a bet on tomorrow.

## 7. Bug: a 24/7 feed on a 5-day market

Hyperliquid's stock perps (HIP-3, e.g. `xyz:SP500`) trade all weekend while the real market is shut. If our feed is that perp, a thin weekend market sets the price that stops or maxes tokens. If our feed is the real exchange price, it is frozen all weekend while the perp already shows where Monday will open — free money for anyone who can still trade at Friday's price.

| Weekend fact (S&P 500) | Value |
|---|---|
| Weekends checked | 29 |
| Avg size of SPY's Monday open jump | 0.42% |
| How well the perp's Sunday-night price predicts it (correlation) | 0.91 |
| Perp guessed the direction right | 86% |
| Biggest weekend dip on the perp | -0.99% (weekend of 2026-06-05) |
| Biggest weekend rise on the perp | +2.03% (weekend of 2026-05-22) |
| Weekend share of the perp's trading volume | 7% |

**Example (5x, stale feed).** On Sunday night the perp says Monday will open up. A buyer buys $10,000 of 5x tickets at Friday's frozen price and sells at Monday's open. Averaged over every weekend, following the perp's direction makes +1.96% per weekend ($196 on $10,000), straight out of the LPs, with no risk worth the name. Fix: the fill rule from §4.3 again — orders placed while the market is shut fill at the next real price (the open), never at Friday's. And the stop/max should only fire on real-market prices, so a thin weekend perp can't knock tokens out.

## 8. Bug: dividends look like a price drop

On the day a dividend is paid out (ex-dividend day), the ETF's price falls by the dividend. Nothing was lost — the owner got the cash — but a price-only feed sees a fall, boosts it, and hands that part to the LPs.

| ETF | Boost | Dividends in the last year | Boost lost to LPs if the feed ignores them | Per $100 of tickets |
|---|---|---|---|---|
| SPY | 2x | 1.08% | 1.08% | $1.08 |
| SPY | 5x | 1.08% | 4.32% | $4.32 |
| QQQ | 2x | 0.47% | 0.47% | $0.47 |
| QQQ | 5x | 0.47% | 1.88% | $1.88 |
| IWM | 2x | 1.02% | 1.02% | $1.02 |
| IWM | 5x | 1.02% | 4.06% | $4.06 |
| TLT | 2x | 4.70% | 4.70% | $4.70 |
| TLT | 5x | 4.70% | 18.80% | $18.80 |

**Example.** SPY paid $1.89 a share on 2026-09-18 (SPY about $763, so 0.25%). A price-only feed sees a -0.25% drop; at 5x a $100 ticket drops $1.24, of which the holder's own real token only lost $0.25 and got it back as cash. The other $0.99 went to the LPs for nothing. A token sitting just above its stop can even be knocked out by a dividend.

Fix: price the token on **total return** (NAV includes dividends, as Yahoo's adjusted close does) and pass the base's dividends to the holder. If the base is a perp, there is no dividend — the perp's funding does the job instead (see §11).

## 9. Bug: a stock split looks like a 90% crash

Nvidia split 10-for-1 on 2024-06-10: one $1,209 share became ten $120 shares. A feed that reads "price per share" sees x = 0.10, a 90% fall, for good. Every Nvidia ticket is knocked out on two updates: a $100 ticket (2x) pays the holder $0, and the LPs take the holder's real stock, about $100. Tesla (5:1 in 2020, 3:1 in 2022), QQQ (2:1 in 2000) and SSO (2:1 four times) did the same.

Fix: NAV is **the value of the real token we hold** (units × price, with the issuer's split multiplier), never a raw share price. Tokenized-stock issuers (xStocks, Ondo) apply a multiplier on splits; the reader must use it, and halt the token for one update if the multiplier changes.

## 10. Full engine runs (fees, hedging, LPs, Series after each end)

`engine2` with the recommended rules, driven by each ETF's opens and closes over the last 10 years (each one a price update). A new token (Series) opens whenever one is stopped or maxed. Retail buys and sells every update; Hearth and Ember start with $25,000 each. Stock-token fees: 0.1% to mint or redeem the base (DEX spread), not LiquidV's 1%. No carry is charged here, so this shows the raw transfer between the two sides.

| ETF | Setting | Series | Maxed | Stopped | Holders net | Hearth net | Ember net | Broken rules |
|---|---|---|---|---|---|---|---|---|
| SPY | 2x, max $3 | 3 | 2 | 0 | $+3,616 | $+2,111 | $-1,220 | 0 |
| SPY | 5x, max $2 | 10 | 8 | 1 | $+23,140 | $+2,938 | $-11,605 | 0 |
| QQQ | 2x, max $3 | 3 | 2 | 0 | $+15,689 | $+1,692 | $-4,211 | 0 |
| QQQ | 5x, max $2 | 17 | 13 | 3 | $+35,006 | $+4,517 | $-16,417 | 0 |
| IWM | 2x, max $3 | 2 | 1 | 0 | $+12,427 | $+1,661 | $-3,565 | 0 |
| IWM | 5x, max $2 | 19 | 11 | 7 | $+12,912 | $+3,543 | $-7,608 | 0 |
| SMH | 2x, max $3 | 5 | 4 | 0 | $+27,782 | $+2,894 | $-7,264 | 0 |
| SMH | 5x, max $2 | 32 | 23 | 9 | $+35,478 | $+2,175 | $-16,073 | 0 |
| GLD | 2x, max $3 | 3 | 2 | 0 | $+1,240 | $+1,984 | $-605 | 0 |
| GLD | 5x, max $2 | 10 | 7 | 2 | $+19,857 | $+2,074 | $-10,423 | 0 |
| TLT | 2x, max $3 | 1 | 0 | 0 | $-7,727 | $+2,283 | $+1,473 | 0 |
| TLT | 5x, max $2 | 6 | 2 | 3 | $-8,281 | $+2,391 | $+600 | 0 |
| ARKK | 2x, max $3 | 6 | 3 | 2 | $+21,072 | $+1,828 | $-5,556 | 0 |
| ARKK | 5x, max $2 | 49 | 27 | 21 | $+37,421 | $+437 | $-17,128 | 0 |
| NVDA | 2x, max $3 | 11 | 8 | 2 | $+53,990 | $+2,002 | $-13,529 | 0 |
| NVDA | 5x, max $2 | 59 | 39 | 20 | $+61,117 | $+7,495 | $-24,814 | 0 |
| TSLA | 2x, max $3 | 11 | 7 | 3 | $+42,912 | $+2,987 | $-10,695 | 0 |
| TSLA | 5x, max $2 | 79 | 45 | 33 | $+45,449 | $+12,107 | $-18,481 | 0 |

## 11. If the base is a Hyperliquid stock perp

| Perp | History | Funding paid by longs (per year) |
|---|---|---|
| `xyz:SP500` | 205 days | +1.05% |
| `xyz:XYZ100` | 205 days | +4.91% |

LiquidV-style, the real token could be a vault holding a 1x long `xyz:SP500` perp. That is big and cheap: the S&P perp trades about $150M a day (vs the $641 vANSEM vault), so the capacity problem from round 1 disappears. The flip side: anyone can already get 2x–50x S&P on Hyperliquid for about 1–5% a year, so our carry (§4, §12) has to be paid for by what a perp doesn't give: no liquidation on a wick, no margin to watch, a known worst case (the stop), no daily reset (§3).

## 12. Fix found on the way: Hearth was posting its collateral twice

Until now Hearth had to hold the hedge **and** the full max-boost cash. But a hedged Hearth already owns the real token for its side: at the max price, that hedge is worth more than the max boost it owes. Example, 2x with max $3, one $1 ticket: Hearth's hedge is 1 extra unit of the ETF, bought for $1. The max boost is $1, paid when the ETF has doubled, and by then the hedge is worth $2. So the separate $1 of cash was never needed.

New rule (engine knob `hedge_credit`): Hearth's required cash = its share of the max boost minus what its hedge would sell for at the max price, less a 20% haircut. Hearth buys a ticket's hedge at the moment the ticket is minted and sells it when the ticket is sold.

| Setting | Hearth money per $1 ticket (before) | After | Carry to match 4% T-bills (before) | After |
|---|---|---|---|---|
| 2x, max $3 | $2.00 | $1.00 | 8.0% | 4.0% |
| 2x, max $2 | $1.50 | $1.00 | 6.0% | 4.0% |
| 3x, max $2 | $2.67 | $2.00 | 10.7% | 8.0% |
| 5x, max $2 | $4.80 | $4.00 | 19.2% | 16.0% |
| 10x, max $2 | $9.90 | $9.00 | 39.6% | 36.0% |

So a fully hedged Hearth is simply **lending the holder (B−1) dollars of the ETF**. A fair carry is then about the T-bill rate on that loan: about 4% a year for 2x, close to what a margin loan or a perp costs. This applies to the trader-token version too.

Same 10 years of real prices, Hearth alone with only $10,000 (no Ember), no carry, so the pool fills up. Hearth's earnings stay about the same (a bit up or down: each ticket's hedge is now bought and sold with it instead of in netted batches).

| ETF | Setting | Tickets bought (before) | After | Buys refused: pool full (before) | After | Hearth net (before) | After | Broken rules |
|---|---|---|---|---|---|---|---|---|
| SPY | 2x, max $3 | $825,726 | $968,999 | 101 | 4 | $+3,637 | $+3,534 | 0 |
| SPY | 5x, max $2 | $378,767 | $459,213 | 637 | 525 | $+1,495 | $+1,792 | 0 |
| QQQ | 2x, max $3 | $859,556 | $994,797 | 75 | 7 | $+3,291 | $+3,659 | 0 |
| QQQ | 5x, max $2 | $372,897 | $425,248 | 648 | 571 | $+3,695 | $+2,413 | 0 |
| SMH | 2x, max $3 | $810,531 | $975,934 | 141 | 18 | $+3,180 | $+3,768 | 0 |
| SMH | 5x, max $2 | $431,224 | $499,301 | 622 | 524 | $+4,712 | $+4,522 | 0 |
| GLD | 2x, max $3 | $781,669 | $919,465 | 114 | 8 | $+3,440 | $+3,498 | 0 |
| GLD | 5x, max $2 | $304,451 | $355,928 | 776 | 686 | $+2,482 | $+2,225 | 0 |
| ARKK | 2x, max $3 | $819,296 | $942,782 | 142 | 27 | $+3,808 | $+3,664 | 0 |
| ARKK | 5x, max $2 | $407,320 | $446,641 | 556 | 490 | $+6,344 | $+3,593 | 0 |
| NVDA | 2x, max $3 | $844,291 | $1,015,318 | 134 | 20 | $+3,727 | $+5,030 | 0 |
| NVDA | 5x, max $2 | $458,414 | $570,397 | 583 | 425 | $+8,393 | $+12,268 | 0 |

Random jumpy markets (jumps up to ±35% in one update, LPs pulling and adding money): **0 of 594** runs broke a rule when the base sells at the trigger (Elysium, no delay); **0 of 606** when the sale happens one update later. 

## 13. "ETFs of stock tokens": baskets built on-chain

Some Hyperliquid markets are already baskets of stocks (`vntl:MAG7`, `vntl:SEMIS`, `km:US500`). A basket is only as fresh as its last trade. Hourly bars from 30 April 2026:

| Market | Data we got | Weekday hours with no trade | Weekend hours with no trade |
|---|---|---|---|
| `xyz:SP500` | 2026-04-30 → 2026-11-21 | 0% | 0% |
| `xyz:SMH` | 2026-06-15 → 2026-11-21 | 0% | 8% |
| `km:US500` | 2026-04-30 → 2026-06-17 | 0% | 0% |
| `vntl:MAG7` | 2026-04-30 → 2026-06-19 | 30% | 57% |
| `vntl:SEMIS` | 2026-04-30 → 2026-06-18 | 38% | 70% |

The two `vntl` baskets went **30–38% of weekday hours and 57–70% of weekend hours without a single trade**, and their (and `km:US500`'s) candles stop in mid-June 2026. A basket like that is a stale feed: its last price is free money for whoever knows where the real stocks went (§7). If we build our own "ETF of stock tokens", its NAV must be computed from **each component's live price**, never the basket's own last trade, and it is frozen whenever a big component's market is shut. Simplest: back tokens with one big, liquid ETF token (S&P 500, Nasdaq 100) rather than a thin custom basket.
