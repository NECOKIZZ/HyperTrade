# Open problem: flash dumps and fast LP exits

Status: **documented, not implemented.** Nothing in the contracts handles this yet beyond what's listed
under "What already helps". Don't build a fix until the design below is agreed.

---

## The problem in one sentence

A stop can only act on prices it sees. If the trader's token **jumps** past the stop in one update
(a flash dump, a liquidation), there is no price in between to sell at. Someone takes the loss beyond
the stop, and if an LP left just before, the LPs who stayed take more than their share.

## Part 1: a flash dump past the stop

Settings: 2x, stop $0.25 (trader's token −37.5%), Hearth is the only pool.
Alice holds $100 of tickets. Hearth backs her with $100 of real `$vANSEM` (the hedge) and $100 locked cash.

**Normal stop** (the token slides down through −37.5%):

| | Amount |
|---|---|
| Alice's real token sells for | $62.50 |
| Alice gets (what's left above the stop) | $25.00 |
| Hearth gets | $37.50 |
| Hearth's hedge lost | −$37.50 |
| **Hearth overall** | **$0 (hedged)** |

**Flash dump** (the token goes from −30% straight to −60% in one update):

| | Amount |
|---|---|
| Alice's real token sells for | $40.00 |
| Alice's ticket math says | 1 + 2 × (−0.60) = −$0.20, so she gets **$0** |
| Hearth gets all of it | $40.00 |
| Hearth's hedge lost | −$60.00 |
| **Hearth overall** | **−$20** |

The $0.25 cushion absorbs jumps up to the zero line (−50% at 2x). Past that, the loss lands on the LPs.

**How often does it happen?** In LiquidV's real data, vFLOOD fell 58.7% in a single update. In the
simulation, a trader liquidated in one update from far above the stop cost Hearth about **$4,300 per
event**, under any stop rule. With the $0.25 stop, ordinary gaps cost LPs $0.00 on real data; the
damage comes from rare, very large jumps (liquidations).

## Part 2: an LP who leaves just before

LP withdrawals are priced at the pool's value **at that moment**. That value counts what holders owe
the pool at today's price, but not the chance that the next update jumps through the stop.

Real simulation result (round 3):
- Two Hearth LPs, identical positions. The trader's token drifts close to the stop.
- One LP withdraws. His loss: **−$2**.
- The trader is then liquidated in one update. The LP who stayed loses **−$9,590**.

The leaver didn't break a rule; he left at the fair price of that moment. But the risk he was paid to
carry (fees while the tickets were alive) was handed to the LP who stayed, right when it was about to
hit.

## What already helps (built)

| Defence | What it does | What it doesn't do |
|---|---|---|
| $0.25 stop cushion | Jumps up to the zero line come out of the holder's $0.25, not the LPs | Jumps past zero |
| 2 updates in a row | One wick doesn't end a ticket | Nothing for real crashes |
| Gap guard | No new tickets when the distance to the stop is smaller than the trader's biggest recent move | Existing tickets |
| Mint limit | No new tickets once the live boost is above 4x (after a big fall) | Existing tickets |
| Locked coverage | LPs can't withdraw the money that backs live tickets | The gap risk on top of it |
| Next-update fills | No LP or buyer can act on a price they've already seen | An LP who acts on a *prediction* |

## Ideas for a fix (not built, to discuss)

1. **Gap holdback on LP exits.** While any ticket in a pool is within a set distance of its stop, a
   withdrawal leaves part of the money behind until those tickets end or move away from the stop.
   Example: Bob withdraws $25,000 while a ticket sits near its stop; $X stays held. If the stop is then
   hit with a gap, Bob's held part pays his share; if not, it's released. The rough version tried in the
   simulator only cut the stayer's loss from $9,590 to $8,677, so the size of "X" and the "near the stop"
   distance need real design.
2. **Exit notice.** Withdrawals from a pool take effect after N updates, so a leaver still carries the
   next few updates' risk. Simple, but every LP waits, not only the fast ones.
3. **Listing rules on the trader.** Hyperliquid shows each trader's leverage and liquidation price
   on-chain. Don't list (or lower the boost of) traders who can be liquidated in one jump from far above
   the stop.
4. **A gap reserve.** A slice of fees goes into a buffer that pays gap losses first, before the LPs.
5. **Pricing it in.** Charge higher fees on traders with a history of big jumps.

These can be combined. Open questions for the decision:
- Which is fairer to LPs: holdback (only fast leavers wait) or exit notice (everyone waits)?
- How much can an LP be asked to leave behind before LPing stops being attractive?
- Should listing rules be automatic (read from HyperCore) or manual at launch?

## Why it needs live traders to prove

The simulator runs on 11 days of LiquidV history across 19 tokens, which held no one-update
liquidation. The right holdback size, notice length or reserve size depends on how often real traders
gap, how big the gaps are, and how LPs actually behave. A small capped pilot (low limits per token)
with real traders would answer that.
