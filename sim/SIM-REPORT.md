# Asphodel v0.5: simulation on LiquidV's live prices

Data: 18 LiquidV tokens with a moving price, ~720 updates each (about 11 days, one update every 7–23 minutes). Pools: Hearth $25,000, Ember $25,000. Boost token: real move + equal LP move (B = 2), max price $3, stop-loss $0. Fees: Asphodel 0.3% buy and sell; LiquidV 1% mint, 0.3% exit (their live settings).

## 1. Normal trading (random buyers and sellers)

Hearth return WITHOUT the hedge fee (Hearth pays LiquidV's 1% itself): average -1.11%, worst -4.30%. Everything below is WITH the hedge fee (buyers pay it).

720 runs (each token, 4 launch dates, 10 random seeds).

| Metric | Average | Worst | Best |
|---|---|---|---|
| Safety-rule violations | 0.00 | 0.00 | 0.00 |
| Hearth return, % | 1.30 | -2.46 | 3.23 |
| Ember return, % | 0.01 | -16.39 | 12.63 |
| Protocol fees, $ | 227.65 | 5.05 | 420.19 |
| LiquidV fees paid, $ | 1,626.94 | 48.26 | 2,986.39 |
| Hearth hedge costs, $ | 426.75 | 14.94 | 800.62 |
| Stop-loss gap loss, $ | 4.82 | 0.00 | 545.61 |
| Flow that could be netted, $ | 18,758.39 | 0.00 | 41,359.86 |
| Share of base flow that nets (buys vs sells), % | 21.47 | 0.00 | 35.54 |
| Updates Hearth could not fully hedge | 0.00 | 0.00 | 0.00 |
| Buys refused | 1.85 | 0.00 | 82.00 |

Ended: {'LIVE': 680, 'CROWNED': 0, 'KNOCKED_OUT': 40}.

Per token (average over runs):

| Token | Hearth % | Ember % | Gap loss $ | Ended |
|---|---|---|---|---|
| vGRANDNEBULA | 1.42 | -1.07 | 0.00 | LIVE |
| vMACHI | 1.34 | -0.05 | 0.00 | LIVE |
| vSMARTEST | 0.92 | 7.67 | 6.25 | KNOCKED_OUT |
| vCALMPEAK | 1.31 | 0.92 | 0.00 | LIVE |
| vJASPER | 1.34 | -1.09 | 0.00 | LIVE |
| v2xRTB2 | 1.38 | 0.39 | 0.00 | LIVE |
| vCEDARSHARK | 1.38 | 0.47 | 0.00 | LIVE |
| vTHREAD | 1.43 | 0.85 | 0.00 | LIVE |
| vLORACLE | 1.35 | 0.25 | 0.00 | LIVE |
| vKOOL | 1.44 | 0.57 | 0.00 | LIVE |
| vANSEM | 1.39 | -2.60 | 0.00 | LIVE |
| vSTEELEAGLE | 1.31 | 0.08 | 0.00 | LIVE |
| vVELVETMESA | 1.41 | 0.56 | 0.00 | LIVE |
| vLUCKYQUAIL | 1.33 | -1.22 | 0.00 | LIVE |
| vFLOOD | 0.62 | 2.03 | 80.56 | LIVE |
| vWINTERMUTE | 1.40 | -0.10 | 0.00 | LIVE |
| vONYXMANTA | 1.35 | 0.01 | 0.00 | LIVE |
| vRTB2 | 1.22 | -7.58 | 0.00 | LIVE |

## 2. Attack: one buyer fills the whole pool at launch

| Token | Tokens bought | Pool money locked | Paid out at the end | Ember % | Hearth % | Violations |
|---|---|---|---|---|---|---|
| vGRANDNEBULA | 24,558 | 49% | $31,866 | -7.33 | 0.20 | 0 |
| vMACHI | 24,558 | 49% | $33,068 | -8.53 | 0.21 | 0 |
| vSMARTEST | 24,558 | 49% | $0 | 24.38 | -0.45 | 0 |
| vCALMPEAK | 24,558 | 49% | $23,624 | 0.93 | 0.17 | 0 |
| vJASPER | 24,558 | 49% | $33,456 | -8.92 | 0.21 | 0 |
| v2xRTB2 | 24,558 | 49% | $29,770 | -5.23 | 0.20 | 0 |
| vCEDARSHARK | 24,558 | 49% | $25,396 | -0.85 | 0.18 | 0 |
| vTHREAD | 24,558 | 49% | $22,412 | 2.14 | 0.17 | 0 |
| vLORACLE | 24,558 | 49% | $30,434 | -5.89 | 0.20 | 0 |
| vKOOL | 24,558 | 49% | $24,080 | 0.47 | 0.18 | 0 |
| vANSEM | 24,558 | 49% | $45,626 | -21.11 | 0.25 | 0 |
| vSTEELEAGLE | 24,558 | 49% | $34,882 | -10.35 | 0.21 | 0 |
| vVELVETMESA | 24,558 | 49% | $24,147 | 0.40 | 0.18 | 0 |
| vLUCKYQUAIL | 24,558 | 49% | $31,864 | -7.33 | 0.20 | 0 |
| vFLOOD | 24,558 | 49% | $0 | 20.97 | -7.26 | 0 |
| vWINTERMUTE | 24,558 | 49% | $28,076 | -3.53 | 0.19 | 0 |
| vONYXMANTA | 24,558 | 49% | $28,149 | -3.60 | 0.19 | 0 |
| vRTB2 | 24,558 | 49% | $66,978 | -42.50 | 0.33 | 0 |

## 3. Attack: buy cheap tickets near the stop-loss (mint limit 4x)

No token got cheap enough in the data, or every buy was refused.


## 3. Attack: buy cheap tickets near the stop-loss (mint limit OFF)

| Token | Spent | Got back | Ember % | Violations |
|---|---|---|---|---|
| vSMARTEST | $6,000 | $0 | 5.59 | 0 |

## 4. Attack: LP bank run (both pools pull out everything they can, every update)

90 runs. Safety-rule violations: total 0 []. LP money pulled out (free capital only): average $50,012. An unpaid holder sell would count as a violation.


## 5a. Attack: attacker knows the next price before it lands, fills at the CURRENT price

| Token | Attacker profit | Ember % | Hearth % |
|---|---|---|---|
| vGRANDNEBULA | $-91 | -1.59 | -1.61 |
| vMACHI | $1,600 | -1.69 | -1.71 |
| vSMARTEST | $13,006 | -36.77 | -37.20 |
| vCALMPEAK | $-1,314 | 0.07 | 0.07 |
| vJASPER | $-10,568 | -7.87 | -8.02 |
| v2xRTB2 | $-1,281 | -0.77 | -0.79 |
| vCEDARSHARK | $-1,558 | -0.55 | -0.57 |
| vTHREAD | $-136 | -0.04 | -0.04 |
| vLORACLE | $-6,455 | -1.77 | -1.82 |
| vKOOL | $-5,378 | -0.34 | -0.36 |
| vANSEM | $4,447 | -18.25 | -18.49 |
| vSTEELEAGLE | $-2,738 | -2.17 | -2.21 |
| vVELVETMESA | $-6,588 | -2.17 | -2.23 |
| vLUCKYQUAIL | $-14,042 | -9.36 | -9.55 |
| vFLOOD | $-247 | -0.38 | -0.39 |
| vWINTERMUTE | $-13,266 | -1.23 | -1.30 |
| vONYXMANTA | $-11,759 | -1.17 | -1.24 |
| vRTB2 | $5,275 | -7.41 | -7.49 |
| **Total** | **$-51,095** | | |

## 5b. Attack: attacker knows the next price before it lands, fills at the NEXT update (spec rule)

| Token | Attacker profit | Ember % | Hearth % |
|---|---|---|---|
| vGRANDNEBULA | $-2,363 | 0.71 | 3.07 |
| vMACHI | $-113 | 0.04 | 0.15 |
| vSMARTEST | $-32,603 | 6.89 | 42.71 |
| vCALMPEAK | $-1,735 | 0.50 | 2.26 |
| vJASPER | $-26,063 | 7.79 | 33.88 |
| v2xRTB2 | $-2,922 | 0.89 | 3.80 |
| vCEDARSHARK | $-2,909 | 0.81 | 3.79 |
| vTHREAD | $-249 | 0.07 | 0.32 |
| vLORACLE | $-11,528 | 3.36 | 15.00 |
| vKOOL | $-7,877 | 2.19 | 10.26 |
| vANSEM | $-19,718 | 6.13 | 25.61 |
| vSTEELEAGLE | $-7,065 | 2.20 | 9.18 |
| vVELVETMESA | $-12,018 | 3.32 | 15.65 |
| vLUCKYQUAIL | $-32,900 | 9.70 | 42.79 |
| vFLOOD | $-871 | 0.25 | 1.13 |
| vWINTERMUTE | $-20,329 | 5.91 | 26.45 |
| vONYXMANTA | $-18,211 | 5.34 | 23.69 |
| vRTB2 | $-2,938 | 0.85 | 3.82 |
| **Total** | **$-202,411** | | |

## 6. Stress: every price move made 2x and 3x bigger

| Move size | Violations | Knockouts | Crowns | Avg gap loss $ | Worst Hearth % | Worst Ember % |
|---|---|---|---|---|---|---|
| 1x | 0 | 2 | 0 | 12.02 | -0.55 | -13.78 |
| 2x | 0 | 2 | 2 | 78.25 | -5.12 | -8.57 |
| 3x | 0 | 2 | 3 | 178.74 | -5.03 | -14.83 |

## 7. Fuzz: 3,000 random jumpy markets, random buys, sells and LP withdrawals

{'runs': 3000, 'runs_with_violations': 0, 'violation_kinds': {}, 'CROWNED': 969, 'KNOCKED_OUT': 1302, 'LIVE': 729}


## 8. Capacity: our base vs LiquidV's vaults today

| Token | LiquidV vault today | Base needed for $10k of our tokens |
|---|---|---|
| vGRANDNEBULA | $86 | ~$10,000 (117x their vault) |
| vMACHI | $9 | ~$10,000 (1,167x their vault) |
| vSMARTEST | $30 | ~$10,000 (329x their vault) |
| vCALMPEAK | $62 | ~$10,000 (160x their vault) |
| vJASPER | $497 | ~$10,000 (20x their vault) |
| v2xRTB2 | $1,334 | ~$10,000 (7x their vault) |
| vCEDARSHARK | $11 | ~$10,000 (875x their vault) |
| vTHREAD | $72 | ~$10,000 (139x their vault) |
| vLORACLE | $155 | ~$10,000 (64x their vault) |
| vKOOL | $553 | ~$10,000 (18x their vault) |
| vANSEM | $641 | ~$10,000 (16x their vault) |
| vSTEELEAGLE | $9 | ~$10,000 (1,111x their vault) |
| vVELVETMESA | $104 | ~$10,000 (96x their vault) |
| vLUCKYQUAIL | $26 | ~$10,000 (378x their vault) |
| vFLOOD | $37 | ~$10,000 (268x their vault) |
| vWINTERMUTE | $407 | ~$10,000 (25x their vault) |
| vONYXMANTA | $78 | ~$10,000 (129x their vault) |
| vRTB2 | $22 | ~$10,000 (454x their vault) |
