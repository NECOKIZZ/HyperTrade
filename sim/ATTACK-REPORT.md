# Asphodel v0.5, round 2: trying to break it

Engine: `sim/engine2.py`. Data: 18 live LiquidV tokens (about 720 updates each). Each hero's token: $1.00 start, real gain + equal LP gain (B = 2), max price $3. Hearth $25,000, Ember $25,000. Fees: Asphodel 0.3%/0.3%, LiquidV 1% mint and 0.3% exit, plus the hedge fee. Unless a section says otherwise: stop at $0, instant, Crown pays fixed boost + base proceeds.

# Findings (auto-collected; see sections for numbers)

- **HIGH: A one-update wick permanently knocks out holders.** With an instant stop at $0, a 70% one-update wick wiped holders in 85% of runs (loyal holder −$5,213 on average) even though the price was back the next update. Requiring 2 updates below the stop cut that to 0%.
- **HIGH: Liquidation gaps land on Hearth, not on holders.** When a hero is liquidated in one update, the stop-loss can't fire in time. Holders lose their stake (expected) but Hearth also loses: its hedge is long `$vTRADER` and only protects it between the stop and the max. Hearth's average hit: $4,804 per run with a $0 stop. A higher stop price shifts more of the remaining value to holders and doesn't save Hearth: only limiting gap size (heroes' leverage) or charging for it does.
- **CRITICAL: Promising exactly $3 at a Crown breaks coverage when the base sells late.** If the Crown promises holders exactly C and the base can only be sold an update later, a one-update spike crowns the token, the price falls back, and the Meadow must pay far more than the coverage it locked: violations above. Fix: at a Crown the Meadow's payment is fixed at the covered boost and holders get the base's actual sale proceeds on top ('fixed_boost'), and a Crown needs 2 updates above the max. Then the spike prize goes to ~0 and coverage always holds.
- **HIGH: Never promise the index price on the base part of a fill.** If our fills pay the index price while LiquidV's redemption actually slips, LPs eat the difference on every large exit (table above). Sells must pass the base's real redemption proceeds to the seller (LiquidV does the same: large exits settle at what positions close for).

## 1. Market: flash wicks (one-update crash, full recovery the next update)

Every token, 3 random times, 3 seeds: the NAV crashes by the wick depth for ONE update and is back to normal the next. A $5,000 'loyal holder' bought at launch and never sells. Compared with the same run without the wick.

| Wick | Stop rule | Holders wiped by the wick | Loyal holder Δ avg $ | worst $ | Hearth Δ avg $ | worst $ | Ember Δ avg $ | Violations |
|---|---|---|---|---|---|---|---|---|
| 30% | A: stop $0, instant | 0% | -0 | -0 | -47 | -1,016 | -43 | 0 |
| 30% | B: stop $0, confirm 2 | 0% | -0 | -0 | -37 | -1,016 | -31 | 0 |
| 30% | C: stop $0.25, instant | 0% | -0 | -0 | -37 | -1,016 | -31 | 0 |
| 30% | D: stop $0.25, confirm 2 | 0% | -0 | -0 | -37 | -1,016 | -31 | 0 |
| 30% | E: stop $0.25, confirm 3 | 0% | -0 | -0 | -37 | -1,016 | -31 | 0 |
| 50% | A: stop $0, instant | 28% | -1,340 | -5,615 | -130 | -1,712 | 760 | 0 |
| 50% | B: stop $0, confirm 2 | 0% | 0 | -0 | 26 | -452 | 36 | 0 |
| 50% | C: stop $0.25, instant | 85% | -4,961 | -13,203 | -299 | -1,023 | 2,585 | 0 |
| 50% | D: stop $0.25, confirm 2 | 0% | 0 | -0 | 26 | -452 | 37 | 0 |
| 50% | E: stop $0.25, confirm 3 | 0% | 0 | -0 | 26 | -452 | 37 | 0 |
| 70% | A: stop $0, instant | 85% | -5,213 | -13,396 | -2,042 | -4,517 | 1,823 | 0 |
| 70% | B: stop $0, confirm 2 | 0% | -0 | -0 | 15 | -350 | 30 | 0 |
| 70% | C: stop $0.25, instant | 89% | -5,708 | -13,396 | -1,999 | -4,517 | 2,054 | 0 |
| 70% | D: stop $0.25, confirm 2 | 0% | -0 | -0 | 16 | -350 | 30 | 0 |
| 70% | E: stop $0.25, confirm 3 | 0% | -0 | -0 | 16 | -350 | 30 | 0 |
| 90% | A: stop $0, instant | 89% | -5,709 | -13,396 | -4,128 | -8,160 | 967 | 0 |
| 90% | B: stop $0, confirm 2 | 0% | -0 | -0 | -4 | -449 | 14 | 0 |
| 90% | C: stop $0.25, instant | 89% | -5,731 | -13,396 | -4,057 | -8,160 | 1,036 | 0 |
| 90% | D: stop $0.25, confirm 2 | 0% | -0 | -0 | -3 | -449 | 14 | 0 |
| 90% | E: stop $0.25, confirm 3 | 0% | -0 | -0 | -3 | -449 | 14 | 0 |

## 2. Market: the hero is liquidated (NAV → 2% of its value in one update, no recovery)

| Rule | Loyal holder Δ $ | Hearth Δ avg $ | Hearth worst $ | Ember Δ avg $ | Ember worst $ | Violations |
|---|---|---|---|---|---|---|
| stop $0, sold at once | -5,709 | -4,804 | -8,391 | 574 | -3,630 | 0 |
| stop $0, base sale 1 update late | -5,709 | -4,800 | -8,274 | 577 | -3,573 | 0 |
| stop $0.25 | -5,709 | -4,521 | -7,574 | 705 | -258 | 0 |
| stop $0.50 | -5,709 | -4,521 | -7,574 | 705 | -258 | 0 |

## 3. Hero as attacker: the 'coin-flip gambler'

The hero (or a friend he tips off) buys $5,000 of every new Series, then makes his account a fair coin flip: every update it moves up or down by `m`. Zero expected return for the hero's own account, so any profit on our token is pure extraction from LPs. 400 Series per row; pools carry over between Series. The guard rows use the hero's own trading history (his past moves) as the gap estimate.

| Hero move per update | Guard | Buys refused | Attacker return | Attacker $ | Hearth $ | Ember $ | Violations |
|---|---|---|---|---|---|---|---|
| ±5% | no guard | 0% | -2.1% | -41,554 | 1,022 | 1,650 | 0 |
| ±5% | stop $0.25 | 0% | -5.8% | -115,405 | 3,951 | 20,546 | 0 |
| ±5% | gap guard (k=1) | 0% | -6.9% | -137,856 | -997 | 24,740 | 0 |
| ±5% | capped Crown | 60% | +10.0% | 79,422 | 5,254 | -22,571 | 0 |
| ±5% | capped Crown + gap guard | 0% | -3.9% | -78,710 | 2,891 | 11,275 | 0 |
| ±5% | capped Crown + gap guard + stop $0.25 | 0% | -0.6% | -11,234 | 8,119 | -3,013 | 0 |
| ±15% | no guard | 0% | -9.2% | -184,314 | -8,782 | 32,675 | 0 |
| ±15% | stop $0.25 | 0% | +0.9% | 17,129 | 33,196 | 2,213 | 0 |
| ±15% | gap guard (k=1) | 0% | -10.9% | -218,375 | -4,804 | 40,618 | 0 |
| ±15% | capped Crown | 81% | +29.1% | 109,310 | 10,727 | -22,690 | 0 |
| ±15% | capped Crown + gap guard | 0% | -15.4% | -307,843 | 23,011 | 77,997 | 0 |
| ±15% | capped Crown + gap guard + stop $0.25 | 0% | -11.2% | -224,681 | 38,349 | 75,018 | 0 |
| ±30% | no guard | 20% | +7.2% | 114,953 | 5,551 | -23,128 | 0 |
| ±30% | stop $0.25 | 0% | -6.3% | -126,914 | 63,239 | 54,828 | 0 |
| ±30% | gap guard (k=1) | 88% | +44.9% | 110,013 | 5,692 | -23,878 | 0 |
| ±30% | capped Crown | 0% | -15.5% | -310,584 | 112,262 | 122,336 | 0 |
| ±30% | capped Crown + gap guard | 0% | -1.6% | -31,464 | 119,229 | 57,443 | 0 |
| ±30% | capped Crown + gap guard + stop $0.25 | 0% | -23.4% | -467,325 | 172,509 | 173,833 | 0 |
| ±50% | no guard | 69% | +17.5% | 109,679 | -7,571 | -22,554 | 0 |
| ±50% | stop $0.25 | 0% | -7.9% | -158,904 | 53,073 | 52,411 | 0 |
| ±50% | gap guard (k=1) | 0% | -3.3% | -66,129 | 18,185 | 22,979 | 0 |
| ±50% | capped Crown | 0% | -13.3% | -266,513 | 105,207 | 112,902 | 0 |
| ±50% | capped Crown + gap guard | 0% | -20.7% | -413,418 | 115,845 | 145,006 | 0 |
| ±50% | capped Crown + gap guard + stop $0.25 | 100% | n/a | 0 | 0 | 0 | 0 |
| ±80% | no guard | 94% | +8.1% | 9,290 | -20,833 | -1,887 | 0 |
| ±80% | stop $0.25 | 81% | +25.4% | 96,447 | 809 | -23,496 | 0 |
| ±80% | gap guard (k=1) | 100% | n/a | 0 | 0 | 0 | 0 |
| ±80% | capped Crown | 0% | -34.6% | -692,539 | 204,926 | 244,747 | 0 |
| ±80% | capped Crown + gap guard | 100% | n/a | 0 | 0 | 0 | 0 |
| ±80% | capped Crown + gap guard + stop $0.25 | 100% | n/a | 0 | 0 | 0 | 0 |

## 4. Holder as attacker: one-update pump to the max price

The attacker buys as much as the pool allows at launch, then pushes the hero's NAV above the max price for ONE update (e.g. a thin-market squeeze); it is back to normal the next update. Manipulation cost is not counted, so this is the attacker's gross prize.

| Crown pays | Updates above max needed | Base sale delay | Crowned | Attacker avg $ | Attacker best $ | LPs avg $ | Violations |
|---|---|---|---|---|---|---|---|
| fixed_C | 1 | 0 | 17/18 | 42,597 | 46,515 | -7,660 | 0 |
| fixed_C | 1 | 1 | 17/18 | 42,597 | 46,515 | -41,548 | 542 |
| fixed_C | 2 | 0 | 0/18 | 3,404 | 40,299 | -1,071 | 0 |
| fixed_C | 2 | 1 | 0/18 | 3,404 | 40,299 | -1,104 | 0 |
| fixed_boost | 1 | 0 | 17/18 | 44,677 | 48,717 | -9,743 | 0 |
| fixed_boost | 1 | 1 | 17/18 | 22,150 | 43,374 | -21,076 | 0 |
| fixed_boost | 2 | 0 | 0/18 | 3,404 | 40,299 | -1,071 | 0 |
| fixed_boost | 2 | 1 | 0/18 | 3,404 | 40,299 | -1,104 | 0 |
| capped | 1 | 0 | 17/18 | 42,597 | 46,515 | -7,660 | 0 |
| capped | 1 | 1 | 17/18 | 22,150 | 43,374 | -21,076 | 0 |
| capped | 2 | 0 | 0/18 | 3,404 | 40,299 | -1,071 | 0 |
| capped | 2 | 1 | 0/18 | 3,404 | 40,299 | -1,104 | 0 |

## 5. LP as attacker: push the price through the stop for one update

An Ember LP deposits $75,000 at launch (so he owns most of Ember), lets retail buy for a while, then pushes the NAV just below the stop for ONE update to knock everyone out, and withdraws.

| Rule | Knocked out | Attacker LP avg $ | Attacker best $ | Retail holders avg $ |
|---|---|---|---|---|
| stop $0, instant | 18/18 | 1,373 | 2,426 | -9,105 |
| stop $0, confirm 2 | 2/18 | 1,377 | 2,434 | -3,003 |
| stop $0.25, instant | 18/18 | 1,108 | 1,940 | -7,383 |
| stop $0.25, confirm 2 | 2/18 | 1,115 | 1,949 | -2,576 |

## 6. Holder as attacker: mass exit through a thin LiquidV vault

One holder buys the whole pool's capacity at launch and dumps it all in one update at the best moment. LiquidV redemptions have slippage (a redemption of N dollars costs N ÷ depth extra). Who pays the slippage: the seller ('transactor'), or the Meadow because we promised the index price.

| LiquidV depth | Slippage paid by | Whale avg $ | LPs avg $ | LPs worst $ | Slippage eaten by LPs avg $ |
|---|---|---|---|---|---|
| none | transactor | 9,144 | -2,005 | -10,805 | 0 |
| $250,000 | transactor | 5,567 | -3,452 | -13,001 | 0 |
| $250,000 | meadow | 9,144 | -7,591 | -20,974 | 4,126 |
| $50,000 | transactor | -6,250 | -8,328 | -21,972 | 0 |
| $50,000 | meadow | 9,144 | -25,118 | -44,501 | 17,147 |

## 7. Market + plumbing: the hero keeps crashing while our base sale is delayed

Synthetic crash: from launch the NAV falls 8% every update for 12 updates. The stop fires around −50%, but the base (and Hearth's hedge) can only be sold `delay` updates later (slow LiquidV redemption, bridge, custody).

| Sale delay (updates) | Stop | Loyal holder $ | Hearth $ | Ember $ | Gap loss $ | Violations | Sells refused while waiting |
|---|---|---|---|---|---|---|---|
| 0 | stop $0 | -5,000 | -148 | 1,345 | 156 | 0 | 0 |
| 0 | stop $0.25 | -3,958 | 20 | 1,119 | 108 | 0 | 0 |
| 1 | stop $0 | -5,000 | -527 | 1,694 | 511 | 0 | 0 |
| 1 | stop $0.25 | -4,433 | -27 | 1,724 | 523 | 0 | 1 |
| 3 | stop $0 | -5,000 | -757 | 1,027 | 800 | 0 | 2 |
| 3 | stop $0.25 | -5,000 | -127 | 1,342 | 924 | 0 | 0 |
| 6 | stop $0 | -5,000 | -915 | 1,270 | 936 | 0 | 2 |
| 6 | stop $0.25 | -5,000 | -915 | 1,270 | 1,821 | 0 | 3 |

## 8. Market + plumbing: the price feed goes stale during a crash

Same crash, but the feed is stale for `k` updates starting as it begins. Sells pause on stale data (spec rule), so holders are stuck; when the feed comes back the price has gapped.

| Stale updates | Loyal holder $ | Crowd $ | Hearth $ | Ember $ | Gap loss $ | Trades refused (stale) |
|---|---|---|---|---|---|---|
| 0 | -5,000 | -1,689 | -147 | 1,540 | 197 | 0 |
| 3 | -5,000 | -964 | -114 | 1,376 | 174 | 1 |
| 6 | -5,000 | -496 | -182 | 1,276 | 149 | 4 |
| 9 | -5,000 | -1,967 | -473 | 1,486 | 448 | 7 |

## 9. LP as attacker: jump into Ember just before a knockout you can see coming

Hyperliquid is public: a hero's liquidation price is visible. The attacker deposits $100,000 into Ember `N` updates before the knockout and pulls out right after. Synthetic path: a slow slide through the stop with retail buying on the way down.

| Deposit lock | Deposit N updates before KO | Attacker $ | Passive Ember $ (with attacker) | Passive Ember $ (without) |
|---|---|---|---|---|
| none | 1 | 8 | 2,448 | 2,456 |
| none | 3 | 85 | 2,001 | 2,085 |
| none | 12 | 679 | 2,504 | 3,183 |
| 72 upd | 1 | 8 | 2,048 | 2,056 |
| 72 upd | 3 | 112 | 2,370 | 2,483 |
| 72 upd | 12 | 483 | 1,935 | 2,417 |
| 504 upd | 1 | 7 | 2,408 | 2,416 |
| 504 upd | 3 | 102 | 3,186 | 3,289 |
| 504 upd | 12 | 591 | 2,302 | 2,893 |

## 10. LP as attacker: grief Hearth by flipping Ember capital (pro-rata pools)

If the Hearth/Ember split follows pool capital (spec §7.3 says 'pro-rata, by capital'), an attacker can deposit and withdraw $25,000 into Ember every other update. Each change moves Hearth's share, so Hearth resizes its hedge and pays LiquidV's 1% each time.

| Split | Extra Hearth hedge costs $ | Hearth Δ avg $ | Hearth Δ worst $ | Attacker $ |
|---|---|---|---|---|
| fixed | 0 | 0 | 0 | -87 |
| prorata | 3,648 | -3,843 | -4,877 | -111 |

## 11. LPs: everyone pulls every dollar of profit, every update

Both pools' LPs withdraw all free capital every update, while holders keep trading and a whale holds to the end. Question: does any holder go unpaid, and what happens to capacity?

| Token | Violations | LPs pulled out $ | Loyal holder $ | Crowd $ | Buys refused (no capacity) |
|---|---|---|---|---|---|
| vRTB2 | 0 | 42,636 | 8,396 | -24 | 287 |
| vANSEM | 0 | 42,531 | 4,125 | -59 | 313 |
| vSMARTEST | 0 | 51,182 | -5,000 | -36 | 173 |
| vFLOOD | 0 | 50,727 | -5,000 | -541 | 7 |

## 12. Buyers with inside information

Some buyers know where the NAV will be `H` updates from now (the hero's friend, or someone reading the hero's open orders). They buy $3,000 only when it will be up by >2%, and sell at that point. With next-update fills, knowing ONE update ahead is worthless; knowing further ahead isn't.

| Knows H updates ahead | Insiders total $ | Hearth Δ avg $ | Ember Δ avg $ | Ember Δ worst $ |
|---|---|---|---|---|
| 1 | 0 | 0 | 0 | 0 |
| 3 | -7,772 | 500 | -20 | -455 |
| 12 | -1,473 | 299 | -87 | -517 |
| 72 | 3,343 | 153 | -91 | -794 |

## 13. Partner failure: LiquidV is hacked or freezes

| Event (on vANSEM's real path) | Loyal holder $ | Crowd $ | Hearth $ | Ember $ | Violations |
|---|---|---|---|---|---|
| LiquidV hacked: NAV → 0 | -5,000 | -3,587 | -4,215 | -166 | 0 |
| LiquidV frozen 72 updates, NAV −40% when it returns | -1,482 | -4,199 | 199 | 639 | 0 |

## 14. Market: correlated crash across every hero at once

All 18 heroes are long the same thing. At the same moment every NAV drops by the crash size in one update. Each hero has its own $50,000 slice of the Meadow (coverage is per token, so slices can't contaminate each other); the table sums the whole Meadow.

| Crash | Knocked out | Loyal holders Δ $ | Hearth Δ $ | Ember Δ $ | Meadow Δ (% of $900k) | Violations |
|---|---|---|---|---|---|---|
| −30% | 2/18 | -54,286 | -2,481 | 21,486 | +2.11% | 0 |
| −60% | 18/18 | -101,720 | -16,023 | 41,518 | +2.83% | 0 |
| −60% then back | 2/18 | 0 | 298 | 675 | +0.11% | 0 |
| −90% | 18/18 | -102,767 | -63,116 | 18,507 | -4.96% | 0 |

## 15. Hero closes everything and goes quiet

When a hero has no positions, the NAV doesn't move, so the token is frozen, but LP coverage stays locked and earns only what holders pay to trade. Share of updates where each LiquidV NAV didn't move at all, in the real data:

| Token | Updates with no NAV change |
|---|---|
| vMACHI | 100% |
| vTHREAD | 98% |
| vGRANDNEBULA | 96% |
| vCEDARSHARK | 89% |
| vSTEELEAGLE | 73% |
| v2xRTB2 | 61% |
| vVELVETMESA | 59% |
| vLORACLE | 57% |
| vKOOL | 46% |
| vANSEM | 43% |

## 16. Fuzz: 4,000 chaotic markets with every knob randomized

Random boost, max price, stop, confirmations, sale delay, slippage depth and payer, pool split mode, LP deposits/withdrawals, stale feeds, wicks, pumps and liquidations, random buyers and sellers.

Runs with any violation: **0 / 4000**. Kinds: none. Ended: {'CROWNED': 1746, 'KNOCKED_OUT': 2251, 'LIVE': 3}.

## 17. Speed: how much do LPs lose to gaps at different update speeds?

A synthetic hero trades one crypto asset (80% yearly volatility) at constant leverage L for 7 days, simulated every 0.5 s, 6 paths each. With 'jumps', the asset also has sudden candles (about 50 a year, typical size ±4%) inside one oracle tick. If one update takes the hero below maintenance margin he is liquidated (NAV → 2%). Our token reads the NAV every `cadence`. Per stop hit, how much were the LPs short of what the stop promised them (per $1 ticket)? With a $0.25 stop the holder's remaining $0.25 absorbs gaps first. (At the max price LPs always pay exactly the covered boost, so only the stop matters.)

| Hero leverage | Jumps | Cadence | Liquidations | Stop $0: hits | LP short avg $ | worst $ | Stop $0.25: hits | LP short avg $ | worst $ |
|---|---|---|---|---|---|---|---|---|---|
| 3 | no | 0.5 s | 0 | 0 | 0.0000 | 0.000 | 1 | 0.0000 | 0.000 |
| 3 | no | 3 s | 0 | 0 | 0.0000 | 0.000 | 1 | 0.0000 | 0.000 |
| 3 | no | 60 s | 0 | 0 | 0.0000 | 0.000 | 1 | 0.0000 | 0.000 |
| 3 | no | 1200 s | 0 | 0 | 0.0000 | 0.000 | 1 | 0.0000 | 0.000 |
| 3 | yes | 0.5 s | 0 | 1 | 0.0000 | 0.000 | 4 | 0.0000 | 0.000 |
| 3 | yes | 3 s | 0 | 1 | 0.0004 | 0.000 | 4 | 0.0000 | 0.000 |
| 3 | yes | 60 s | 0 | 1 | 0.0013 | 0.001 | 4 | 0.0000 | 0.000 |
| 3 | yes | 1200 s | 0 | 1 | 0.0117 | 0.012 | 4 | 0.0000 | 0.000 |
| 10 | no | 0.5 s | 0 | 9 | 0.0002 | 0.000 | 17 | 0.0000 | 0.000 |
| 10 | no | 3 s | 0 | 9 | 0.0006 | 0.002 | 18 | 0.0000 | 0.000 |
| 10 | no | 60 s | 0 | 9 | 0.0022 | 0.008 | 18 | 0.0000 | 0.000 |
| 10 | no | 1200 s | 0 | 9 | 0.0149 | 0.033 | 17 | 0.0000 | 0.000 |
| 10 | yes | 0.5 s | 0 | 10 | 0.0004 | 0.002 | 17 | 0.0000 | 0.000 |
| 10 | yes | 3 s | 0 | 10 | 0.0005 | 0.002 | 17 | 0.0000 | 0.000 |
| 10 | yes | 60 s | 0 | 10 | 0.0044 | 0.010 | 19 | 0.0000 | 0.000 |
| 10 | yes | 1200 s | 0 | 8 | 0.0168 | 0.041 | 17 | 0.0000 | 0.000 |
| 25 | no | 0.5 s | 0 | 71 | 0.0006 | 0.002 | 124 | 0.0000 | 0.000 |
| 25 | no | 3 s | 0 | 73 | 0.0020 | 0.007 | 119 | 0.0000 | 0.000 |
| 25 | no | 60 s | 0 | 69 | 0.0083 | 0.035 | 108 | 0.0000 | 0.000 |
| 25 | no | 1200 s | 0 | 60 | 0.0423 | 0.127 | 90 | 0.0000 | 0.000 |
| 25 | yes | 0.5 s | 0 | 80 | 0.0007 | 0.003 | 127 | 0.0000 | 0.000 |
| 25 | yes | 3 s | 0 | 77 | 0.0015 | 0.005 | 130 | 0.0000 | 0.000 |
| 25 | yes | 60 s | 0 | 75 | 0.0077 | 0.024 | 118 | 0.0000 | 0.000 |
| 25 | yes | 1200 s | 0 | 64 | 0.0410 | 0.203 | 100 | 0.0000 | 0.000 |

## 18. Head to head: naive settings vs recommended settings

- **Naive:** stop at $0 and instant; Crown promises exactly $3 and fires instantly; Hearth/Ember split follows capital; we pay the index price and eat LiquidV slippage; no gap guard.
- **Recommended:** stop at $0.25 (holders get what's left), needs 2 updates below; at the max the Meadow pays exactly the covered boost and the holder keeps their whole real token, needs 2 updates above; split fixed when tokens are minted; sellers get the base's real redemption; mints refused when the hero's recent moves could jump the stop.

| Test | Naive | Recommended |
|---|---|---|
| normal: Hearth % | -1.41 | +1.23 |
| normal: Ember % | -3.70 | -1.42 |
| normal: buys refused by guards | 4 | 2 |
| 70% wick: holders wiped | +83.33 | +0.00 |
| 70% wick: loyal holder Δ $ | -4,965 | 0 |
| liquidation: Hearth Δ $ | -4,518 | -4,319 |
| gambler ±30%: attacker return % | -15.77 | -23.37 |
| gambler ±30%: LPs $ | 80,764 | 78,047 |
| gambler ±50%: attacker return % | +1.20 | +0.00 |
| gambler ±50%: LPs $ | -19,316 | 0 |
| 1-update pump: attacker avg $ | 42,597 | 664 |
| 1-update pump: violations | 4,365 | 0 |
| LP stop-push: retail holders avg $ | -9,105 | -3,231 |
| mass exit ($50k depth): LPs avg $ | -25,288 | -8,231 |
| Ember flipping: Hearth Δ $ | -7,977 | 0 |


_Run time 41 s._

