# Asphodel v0.5, round 3: fairness bugs

Not attacks. Each test asks: does an honest holder or LP ever lose money they were owed, or get stopped from being paid, because of how the rules work? Engine `sim/engine2.py`, 18 real LiquidV histories.

## 1. Real LiquidV data: what the stop-loss and the max price take from each side

Launch a $1.00 ticket (B = 2, max $3, stop $0) at EVERY update of all 18 real LiquidV histories and follow it until it ends. At LiquidV's real update speed (every 7–23 minutes) the price can jump past either edge in one update:
- **Past the stop (gap):** the holder is floored at $0, so the LPs collect less than the stop promised them. Honest LPs lose.
- **Past the max (overshoot):** the real token inside is worth more than the edge. Who keeps the extra depends on the Crown rule: holders ('fixed boost') or LPs ('capped').

**Max price $3** (max hit when the real token is up 100% since launch):

| Token | Launch points | Hit stop | Hit max | Avg gap $/ticket | Worst gap | Avg overshoot $/ticket | Worst overshoot | Stop hits that bounced back next update |
|---|---|---|---|---|---|---|---|---|
| vSMARTEST | 720 | 258 | 0 | 0.01 | 0.05 | – | – | 125 |
| vFLOOD | 717 | 29 | 0 | 0.07 | 0.09 | – | – | 0 |

All tokens: 12,906 launch points, **287 stop hits** (average gap $0.016 per $1 ticket, worst $0.09), **0 max-price hits** (average overshoot $0.000, worst $0.00). 125 stop hits (44%) were back above the stop the very next update.

**Max price $2** (max hit when the real token is up 50% since launch):

| Token | Launch points | Hit stop | Hit max | Avg gap $/ticket | Worst gap | Avg overshoot $/ticket | Worst overshoot | Stop hits that bounced back next update |
|---|---|---|---|---|---|---|---|---|
| vSMARTEST | 720 | 258 | 3 | 0.01 | 0.05 | 0.02 | 0.02 | 125 |
| vANSEM | 720 | 0 | 377 | – | – | 0.04 | 0.18 | 0 |
| vFLOOD | 717 | 29 | 0 | 0.07 | 0.09 | – | – | 0 |
| vRTB2 | 719 | 0 | 437 | – | – | 0.34 | 0.38 | 0 |

All tokens: 12,906 launch points, **287 stop hits** (average gap $0.016 per $1 ticket, worst $0.09), **817 max-price hits** (average overshoot $0.201, worst $0.38). 125 stop hits (44%) were back above the stop the very next update.

## 7. The Crown and the stop, rule by rule: who is paid what they were promised

On the real histories, every launch point that ends (stop or max), with real-speed gaps, under each rule. 'Promised' = $3 at the max; at the stop, the LPs were promised the base at the stop level. All figures per $1 ticket, averaged over every ended ticket.

**Max price $3:**

No max-price hits in the real data at $3; 287 stop hits.

**Stop rules** (each stop has its own trigger; the LPs' promised take at the stop is the base minus what the holder keeps, at the trigger level):

| Stop rule | Stop hits | Saved by bouncing back | Holder keeps avg $ | best $ | LPs short of promised avg $ | worst $ |
|---|---|---|---|---|---|---|
| Stop $0.00, instant, sold the same update | 287 | 0 | 0.00 | 0.00 | 0.02 | 0.09 |
| Stop $0.00, needs 2 updates below | 287 | 125 | 0.00 | 0.00 | 0.03 | 0.09 |
| Stop $0.25, instant, sold the same update | 616 | 0 | 0.21 | 0.25 | 0.00 | 0.00 |
| Stop $0.25, needs 2 updates below | 616 | 170 | 0.18 | 0.25 | 0.00 | 0.00 |

**Max price $2:**

| Event | Holder gets: 'exactly $2' | Holder gets: 'fixed boost' | Holder gets: 'capped' | LP pays, worst: 'exactly $2' | LP pays, worst: 'fixed boost' | LP pays, worst: 'capped' |
|---|---|---|---|---|---|---|
| Max price, sold the same update | 2.00 | 2.20 | 2.00 | -0.50 | -0.50 | -0.50 |
| Max price, sold one update later | 2.00 | 2.20 | 2.00 | -0.56 | -0.50 | -0.50 |

817 max-price hits and 287 stop hits. LP coverage per ticket is $0.50. 'Exactly $2' with the sale one update late needs up to $0.56 per ticket — **more than the coverage locked, so somebody can't be paid.**

## 2. Can every holder AND every LP be paid in full, at any moment?

At 40 random moments in each real history (with random retail trading and LP deposits and withdrawals running), freeze a copy of the market and make **every holder sell everything**, then **every LP withdraw everything**. Checks: every holder gets exactly price × tokens minus the disclosed fees, no pool goes negative, and LPs get back their marked value.

**649 full-exit checks.** Holders short-changed: **0**. Pools negative or broken: **0**. LP value still stuck in the pool after every holder left and every LP asked to withdraw: max $0.00.

## 3. LPs: value you own but can't withdraw yet

An LP's share is marked to market, but only **free capital** can leave. Two things lock value: coverage for holders' possible winnings, and the LPs' own unrealized gains when holders are losing (that gain sits inside the real token in the vault, not in cash, until holders sell or are stopped out). Over normal trading on the real histories, how much of an LP's marked value could actually be withdrawn?

| Token | Hearth: avg withdrawable | Hearth: lowest | Ember: avg withdrawable | Ember: lowest |
|---|---|---|---|---|
| vGRANDNEBULA | 80% | 62% | 90% | 81% |
| vMACHI | 83% | 70% | 93% | 87% |
| vSMARTEST | 66% | 11% | 80% | 46% |
| vCALMPEAK | 74% | 42% | 87% | 70% |
| vJASPER | 80% | 49% | 90% | 73% |
| v2xRTB2 | 82% | 63% | 92% | 84% |
| vCEDARSHARK | 76% | 39% | 88% | 70% |
| vTHREAD | 77% | 45% | 88% | 71% |
| vLORACLE | 79% | 57% | 91% | 81% |
| vKOOL | 76% | 52% | 88% | 76% |
| vANSEM | 82% | 61% | 93% | 81% |
| vSTEELEAGLE | 85% | 67% | 94% | 87% |
| vVELVETMESA | 75% | 58% | 87% | 78% |
| vLUCKYQUAIL | 82% | 64% | 92% | 82% |
| vFLOOD | 91% | 73% | 95% | 87% |
| vWINTERMUTE | 77% | 50% | 89% | 75% |
| vONYXMANTA | 78% | 60% | 89% | 80% |
| vRTB2 | 81% | 45% | 93% | 73% |

## 4. Fees near the stop: is anyone charged for money that isn't theirs?

Near the stop, most of the real token inside a ticket belongs to the LPs, not the holder (the holder's share is the ticket price). Total cost of a $100 buy and of selling it straight back, as % of the money moved. v1 charged LiquidV's fees on the WHOLE base; v2 charges the holder only on their part.

| Ticket price | Live boost | Buy cost v1 | Buy cost v2 | Round trip v1 | Round trip v2 |
|---|---|---|---|---|---|
| $1.00 | 2.0x | 1.77% | 1.77% | 2.50% | 2.50% |
| $0.60 | 2.7x | 2.25% | 1.93% | 3.13% | 2.71% |
| $0.40 | 3.5x | 2.84% | 2.13% | 3.90% | 2.97% |
| $0.20 | 6.0x | 4.58% | 2.72% | 6.15% | 3.75% |
| $0.10 | 11.0x | 7.88% | 3.89% | 10.43% | 5.26% |
| $0.02 | 51.0x | 27.82% | 12.32% | 36.32% | 16.20% |

## 5. Ordinary LPs coming and going: who pays for it?

No attacker: a handful of normal Ember LPs deposit and withdraw a few thousand dollars at random (a few times a day). If the Hearth/Ember split follows pool capital, every change resizes Hearth's hedge, and **Hearth's LPs pay LiquidV's fee for other people's deposits**.

| Split | Extra Hearth hedge cost avg $ | worst $ | Hearth LPs Δ avg $ | worst $ |
|---|---|---|---|---|
| fixed | 0 | 0 | 0 | 0 |
| prorata | -114 | -1 | -134 | -194 |

## 6. Hearth LPs who leave fast vs LPs who stay, before a liquidation gap

Two equal Hearth LPs ($25,000 each). The hero drifts toward the stop; LP 'fast' withdraws when the price is within 15% of the stop (a public signal: the hero's liquidation price is visible). Then the hero is liquidated in one update. Withdrawals pay the **marked** value, and the mark doesn't price the risk of a gap, so whoever leaves first escapes the loss.

| Rule | 'Fast' LP $ | 'Stay' LP $ |
|---|---|---|
| plain mark | -2 | -9,590 |
| exit haircut near the stop | -914 | -8,677 |

## 8. 'Sells always open' vs the moment a ticket ends

Between the stop/max firing and the base actually being sold, nobody can sell (the final value isn't known yet). How long is that window, and how often would a holder hit it?

| Base sale delay (updates) | Sell attempts | Refused (ticket ending) |
|---|---|---|
| 0 | 6439 | 0 |
| 1 | 6439 | 1 |
| 3 | 6439 | 1 |

_Run time 2 s._
