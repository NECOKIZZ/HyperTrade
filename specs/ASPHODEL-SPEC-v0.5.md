# Asphodel

### Boosted trader tokens for Elysium

> **Ride the traders you believe in, boosted. Real backing underneath, a known worst case on top.**
> Every boost token is built on a real trader token. The pool only backs the boost.

Status: **parked** (focus is Cloak). Draft spec v0.5 · Author: engineering · Target chain: Elysium (Kinetiq's L2 for Hyperliquid)

| Version | Change |
|---|---|
| v0.2 | Positions became ordinary tokens; LPs see an APR |
| v0.3 | One token per trader; a hedged LP pool that copies the trader on Hyperliquid |
| v0.4 | Lessons from LiquidV and Bounce: history replay, wallet groups, permissionless breaker, seed pot, partner hedges |
| **v0.5** | **Real base, synthetic boost.** A buyer's money buys a real LiquidV trader token (`$vTRADER`); the pool only backs the **extra** move. Each token starts at $1.00 and has **one common zero, its launch** (like a LiquidV token); a new Series opens only after a Crown or stop-loss, never on a schedule. No daily reset, no leverage leak, a stop-loss floor at $0 and a max price. The Steady pool hedges with `$vTRADER` in place of a copy bot. Coverage is checked **per pool, after the hedge is paid for**. Pool capital per token falls by about half. **Simulated on LiquidV's live prices (§20); attacked and checked for fairness bugs (§21)**, which changed the stop ($0.25, 2 updates), the Crown (LPs pay exactly the covered boost, holders keep their real token), fees near the stop, the pool split (fixed at mint) and LP exits |

---

## 0. The name (unchanged)

In Greek myth, **Elysium** is paradise for the **heroes**. The **Asphodel Meadows** next to it hold **everyone else**, who spend eternity watching the heroes. **Rhadamanthus** is the incorruptible judge of who gets in.

Hyperliquid makes every trader's account public. A few heroes (whales, great traders) are watched by the crowd in the meadow. **Asphodel lets the meadow trade the heroes**, and in v0.5, trade them **boosted**.

### Glossary

| Term | What users see | What it is underneath |
|---|---|---|
| **Hero** | A trader page (e.g. "0xWhale") | A Hyperliquid account (or wallet group) that LiquidV has tokenized |
| **`$vTRADER`** (e.g. `$vWHALE`) | "Backed by LiquidV" | LiquidV's 1x long token for that hero: a vault holding real copied positions |
| **Boost token** (e.g. `$WHALE 2x S3`) | A token with a price chart, Buy and Sell | ERC-20 on Elysium: a **real base** of `$vWHALE` plus a **synthetic boost** owed by the Meadow |
| **Base** | "Real backing" | The `$vTRADER` held for every boost token in the Backing Vault |
| **Boost** | "2x" | The extra move on top of the base, paid by or to the Meadow |
| **Series** | "S3" | A boost token's lifetime from one start price; a new Series opens at $1.00 only after the previous one is Crowned or Knocked out |
| **Max boost** (`C`) | "Max boost reached at $3.00" | The LPs' part stops at `MAXB` ($1.00 for 2x). Two updates at or above `C`: **Crowned**, base sold, value frozen at sale proceeds + `MAXB`, redeemable forever |
| **Stop-loss** (knockout) | "Stops at $0.25 if 0xWhale falls 37.5%, you keep what's left" | Two updates at or below $0.25: **Knocked out**; the base is sold, the holder gets what's left, the rest goes to the Meadow |
| **Meadow** | "Pools: earn APR" | The LP vault that backs every boost |
| **Hearth** | "Steady pool" | LPs who back the boost **and** hold `$vTRADER` against it. Earns fees |
| **Ember** | "Boosted pool" | LPs who back the boost unhedged. Earns fees plus holders' boost losses |
| **Rhadamanthus** | "Price source: live from Hyperliquid" | The index engine; reads the hero's LiquidV vault through Elysium's HyperCore precompile |

---

## 1. The idea in one example

**Alice** buys **$100 of `$WHALE 2x`**.

1. Her $100 buys **$100 of real `$vWHALE`**. That pays the normal move.
2. The **extra** move (the boost) is owed by the Meadow.
3. **Bob** (Hearth) has $100 of USDC in the Meadow **and** holds $100 of `$vWHALE` against it.
4. **Carol** (Ember) has $100 of USDC in the Meadow and holds nothing against it.

| 0xWhale | Alice's real base | Boost from the Meadow | **Alice ends with** |
|---|---|---|---|
| +10% | $110 | +$10 | **$120** |
| −20% | $80 | −$20 | **$60** |
| −37.5% (2 updates) | $62.50 | −$37.50 | **$25: stop-loss, she keeps what's left** |
| +100% (2 updates) | $200 | +$100 | **$300: max boost, Crowned** |

If Bob backs the boost, his `$vWHALE` moves the same amount the other way, so **Bob ends at $0 plus fees** in every row. If Carol backs it, she pays when Alice wins and collects when Alice loses, plus fees.

**Why it's better than either earlier design:**
- **Not "synthetic, hope the house pays."** The normal move is a real position.
- **The pool only backs the slice nobody else sells.** About half the locked LP money of v0.4 (§7.1).
- **Steady LPs finally have an exact hedge**, the same token the base is made of.
- **Not a LiquidV clone.** LiquidV sells the base; Asphodel sells the boost, built on top of them.

---

## 2. The product principle

**It must feel like normal trading.** Users see a list of heroes, boost tokens (2x, 3x), a chart, **Buy** and **Sell**, and two pools with an **APR**.

**"2x" means two gains, not leverage.** Nobody borrows anything. The buyer gains once because the real token rises (they were right), and gains the same amount again from the LPs on the other side. Two equal gains on every move, or two equal losses. The label is "2x" because that's how it feels.

**No leverage leak.** Leveraged tokens reset their leverage every day, so a market that goes back and forth slowly drains them. A boost token counts from its launch and never resets:

| 0xWhale | Daily-reset 2x | **`$WHALE 2x`** (counts from launch) |
|---|---|---|
| Monday +10% | $100 → $120 | $100 → $120 |
| Tuesday −10% (0xWhale ends −1%) | $120 → **$96** | **$98** |

**A known worst case, before you buy.** No margin, no liquidation, no margin calls. The page shows exactly where the stop-loss and the max price are. The worst case is $0; the best case is `C`.

**Fully disclosed.** Every guardrail is on the token page (§12). Legally these are still derivatives (§17).

**Plain 1x exposure is LiquidV's product**, not ours. The app can route a plain "Buy 0xWhale" to `$vWHALE` for a frontend fee (§11.3) and keeps its own markets for boosts.

---

## 3. Actors

| Actor | Does | Earns from |
|---|---|---|
| **Buyer** | Buys and sells boost tokens | The hero's performance, boosted |
| **LP, Hearth (Steady)** | Deposits USDC; part backs the boost, part buys `$vTRADER` as a hedge | **Fees**, minus hedge costs |
| **LP, Ember (Boosted)** | Deposits USDC; backs the boost unhedged | Fees, plus buyers' boost losses, minus their boost gains |
| **Hero** | Trades on Hyperliquid as usual; may opt in as Ascended | A fee share (Ascended only) |
| **LiquidV** | Issues and redeems `$vTRADER` at NAV | Its own mint and redeem fees (§11.1) |
| **Keeper** | Updates the index, fills buys and sells, triggers Crown and stop-loss, nets base flows | A small bounty per action. Index and fill keepers are permissionless |
| **Protocol** | Lists heroes, sets guardrails | A share of fees |

---

## 4. Rhadamanthus: the price source

### 4.1 What the price follows

Every boost token's price follows **the NAV of the hero's `$vTRADER`**, not the raw wallet. That's what makes the base an **exact** backing: the token and its base are priced off the same thing.

```
x = NAV_t / NAV_0      (NAV now ÷ NAV at launch; x = 1 at the start)
```

### 4.2 How it's read

- Rhadamanthus computes the NAV from **the LiquidV vault's own HyperCore account** (positions, oracle prices, cash), read through the Elysium HyperCore precompile.
- It **cross-checks** against LiquidV's published exchange rate. A gap above a threshold trips the breaker (buys pause).
- It also runs the v0.4 **wallet index** (return attribution on the hero's own positions) and publishes **fidelity**: wallet return vs vault NAV, per hero.

### 4.3 Freshness and fill timing

- Every value stores its **HyperCore timestamp**. Reads older than **maxAge** pause buys and sells.
- **Fill rule:** a buy or sell request fills at the first update whose **oracle timestamp is later than the request**, not just the next block. (Hyperliquid's oracle price is published every few seconds and can be predicted from CEX prices, so "next block" alone would let bots trade ahead of a known update.)
- **Never fill against LiquidV's published price.** LiquidV's indexer updates every 7–23 minutes, while anyone can watch the hero and the vault live on Hyperliquid. Fills must use the NAV Rhadamanthus computes **live from the vault's HyperCore account** (§4.2). In the simulation (§20), an attacker who knew the next price and could fill at the current one made up to **$13,000 on one token** and cost Hearth **37%**; with next-update fills the same attacker **lost $202,000** across 18 tokens, all of it to fees.
- ⚠️ On Elysium, use HyperCore timestamps and `ArbSys.arbBlockNumber()`, never `block.number` (unchanged from v0.4).

---

## 5. The boost token

### 5.1 The math

Each boost token belongs to a **hero** and a **boost level** `B` (e.g. 2x). It starts at **$1.00**, whatever `$vTRADER` costs that day.

**Why $1.00 and not the `$vTRADER` price.** Mathematically the two are the same product in different units: each token simply holds `1 / NAV_0` units of `$vTRADER` (tested in the simulation: identical results). $1.00 is chosen because:
- every token's rules read the same: **starts at $1.00, stop-loss $0.25, max boost at $3.00**;
- the price is a plain percentage: $1.20 means "up 20% since launch, both gains included";
- it avoids implying our token *is* `$vWHALE`. It isn't: it moves with both gains, so after launch the two prices separate anyway.

LiquidV does the same: its own tokens launch at about $1.00.

```
base   = x                                  real: (1 / NAV_0) units of $vTRADER per token, a fixed count
boost  = (B − 1) × (x − 1), capped at +MAXB  synthetic: owed by the Meadow (negative = owed to it)
         where MAXB = (B − 1) × (C − 1) / B (the covered boost: $1.00 for 2x, C = $3)
price  = max(0, base + boost), then × carry
```

**The cap is on the LPs' boost, not on the holder's real token.** Up to the max, price = 1 + B × (x − 1) as before. Above it, the LPs' part stops growing but the holder's real `$vTRADER` is still theirs, so the price keeps following it 1:1. Round 3 of the simulation (§21) found that capping the whole price at `C` takes the holder's own real-token gains above the max (up to **$0.38 a ticket** on real data with a $2 max), and that promising "exactly `C`" can't always be paid.

| Point | Where | `$WHALE 2x`, C = $3 |
|---|---|---|
| **Stop-loss** (price $0.25) | `x_k = 1 + (0.25 − 1)/B` | 0xWhale −37.5%, for **2 updates in a row** |
| **Max boost** (price `C` = $3) | `x_c = 1 + (C − 1)/B` | 0xWhale +100%, for **2 updates in a row** |

**The base never needs rebalancing.** Each token is backed by a fixed number of `$vTRADER` units, set at launch. Only buys and sells change how many units the vault holds.

### 5.2 Max price: Crowned

When the real token has been at or above `x_c` for **2 updates in a row**:
1. Buys stop. The Backing Vault **sells the base**, and the Meadow pays **exactly the covered boost** (`MAXB` per token, $1.00 for 2x/$3): no more, no less.
2. Each token's final value = **what its base actually sold for + `MAXB`**, frozen and redeemable forever. If the hero overshot, the holder keeps it (it's their real token). If the sale fills a bit lower, the holder bears that, not the LPs, so **coverage can never be exceeded**.
3. Hearth's hedge for that token is **sold**.

**Why not "frozen at exactly `C`":** the simulation broke it. If the base can only be sold an update later and the price has fallen back, paying exactly `C` needed **$0.56 per ticket against $0.50 of coverage** on real data (max $2): somebody can't be paid. And a one-update spike to the max crowned 17 of 18 tokens, handing a buyer about **$42,600** that the next update took back. Two updates above the max: 0 crowned.

**Why 2 updates:** one-update spikes and wicks are common at LiquidV's real speed (§21). Waiting one more update costs the LPs nothing measurable on real data and stops a single spike from crowning a token.

### 5.3 Stop-loss: Knocked out

When the price has been at or below **$0.25 for 2 updates in a row**:
1. The token is **Knocked out**. Buys stop.
2. The base is **sold at once**. The holder gets **what's left**: `max(0, 1 + B × (x_sale − 1))` per token, from the base's real sale proceeds. The rest of the base belongs to the Meadow.
3. Hearth's hedge for that token is **sold at once**.

**Why $0.25 and 2 updates, not $0 instantly (round 3, real data):**

| Stop rule | Real stop hits | Saved by bouncing back | Holder keeps (avg) | LPs short of what the stop promised (avg / worst) |
|---|---|---|---|---|
| $0, instant | 287 | 0 | $0.00 | $0.02 / $0.09 |
| $0.25, 2 updates | 616 | 170 | **$0.18** | **$0.00 / $0.00** |

- **44% of real $0 stop hits were back above the stop the very next update.** An instant stop wipes those holders out permanently for a one-update wick. In the round-2 test, a 70% one-update wick wiped holders in 83% of runs with an instant stop, and in 0% with 2 updates.
- With a $0.25 stop, **the holder's remaining $0.25 absorbs the gap first**, so the LPs got everything the stop promised them in every real case, and holders leave with something instead of nothing.
- The cost: the stop sits at −37.5% instead of −50%, so it's hit more often. Shown on the token page.

**Gap leak:** if the hero falls through the stop faster than the base and hedge can be sold, the holder's $0.25 cushion takes it first; only a gap past $0 reaches the LPs. That gap is the main leak in the design, and the reason Elysium's speed matters (§9). Mitigations: fast stop-loss triggers on Elysium (§9), sell orders prepared (but not sent) as the price approaches `x_k`, and per-hero boost limits that tighten with the hero's own leverage (§10). **Nothing is sold before the stop-loss itself:** selling early would leave the Meadow unhedged if the price bounces back.

### 5.4 Series and the effective boost

All tokens in a Series share one start, so they're fungible ordinary ERC-20s. A buyer who comes in later gets a different **effective boost**:

```
effective boost = B × x / price
```

**Example (`$WHALE 2x`):** after 0xWhale is up 20%, the price is $1.40 and the effective boost for a new buyer is 2 × 1.2 / 1.4 = **1.71x**. After a 20% fall, the price is $0.60 and the effective boost is **2.67x**, because the stop-loss is closer.

So the token page always shows the **live effective boost** and **the distance to the stop-loss and max price**.

**One common zero, like a LiquidV token.** A Series' zero is its launch, and everyone after that buys at the live price, the same way `$vTRADER` holders all share the token's bond date as its zero and each buyer's own result starts from the NAV they minted at. **A new Series opens only when the current one ends** (Crowned or Knocked out). While the live effective boost is above a limit (e.g. 4x, close to the stop-loss), the Meadow stops minting that Series; it can still be sold back any time and traded freely between people.

### 5.5 Secondary markets (unchanged)

Boost tokens are ordinary ERC-20s. AMM prices are anchored by arbitrage against the Meadow's buy and sell. A token Crowned or Knocked out inside an AMM is still worth exactly `C` or $0 to whoever holds it.

---

## 6. The Backing Vault: the real part

### 6.1 What it holds

The Backing Vault holds the **base** for every live boost token: exactly `supply / NAV_0` units of `$vTRADER` per Series.

### 6.2 Buying and selling

**Buy:** a buyer pays `price` (+ fees) in USDC. The vault acquires the base, `x` dollars of `$vTRADER` per token, and the difference `price − x` (the boost part) is settled with the Meadow:
- if the hero is up since launch, the buyer pays the Meadow the boost they are joining at;
- if the hero is down, the Meadow pays toward the base, and owns that claim back through the boost.

**Sell:** the reverse. The vault releases base, the Meadow settles the boost part, the seller gets `price` in USDC.

### 6.3 Netting first (saves LiquidV fees)

Buys and sells of the same hero are **netted inside the vault** before anything touches LiquidV. Alice selling and Dan buying moves base units between them, with no LiquidV mint or redeem fee. Only the **net** flow per window is minted or redeemed with LiquidV.

A fill settles only once the vault holds the base. If LiquidV minting is slow, fills wait (shown as "Filling…"); if redemption is slow, sells queue, never cancel.

### 6.4 Where `$vTRADER` lives

`$vTRADER` is issued on HyperEVM; boost tokens live on Elysium. v1 needs one of:
- a **HyperEVM-side vault** that holds `$vTRADER` and is controlled from Elysium with proven messages, or
- a **bridged representation** of `$vTRADER` on Elysium, backed 1:1.

This is open question 1 (§18). Neither may count toward anything until its trust model is written down.

### 6.5 Path B: heroes LiquidV hasn't tokenized

For a hero without a `$vTRADER`, the v0.4 **Hedger** builds the base itself: a copy of the hero's positions on HyperCore through the Elysium keeper fast-write lane, with trade-only API keys. Path B has v0.4's copy-lag and trading-cost leaks, so Path B heroes get lower caps and are labelled "Self-backed." v1 can launch with Path A only.

---

## 7. The Meadow: the synthetic part

### 7.1 Coverage: the core safety rule

The Meadow must always be able to pay **every boost at the max price**, **in each pool separately**:

```
per token:   max boost owed = MAXB = (B − 1) × (C − 1) / B        (exactly what the Meadow pays at a Crown, §5.2)

Hearth cash on Elysium ≥ Hearth share × Σ supply × max boost owed   + cost of any hedge it still has to buy
Ember cash on Elysium  ≥ Ember share  × Σ supply × max boost owed
```

**Checked per pool, after the hedge is paid for.** The simulation broke an earlier version that checked the Meadow's *total* cash. Ember's surplus hid a Hearth shortfall; then Hearth spent its cash on the hedge, coverage fell below 100%, and in fuzz runs some sells couldn't be paid. That's the Avantis audit bug class. With the per-pool rule, **0 violations in nearly 4,000 runs** (§20).

**This is what stops anyone getting more unrealized profit than the pool can pay.** The LPs' part of any token can never exceed `MAXB`, and the cash for every token's `MAXB` is locked before the token is created. A buy that would break this is refused. **Round 3 checked it directly:** at 649 random moments on real data, a copy of the market made every holder sell everything and then every LP withdraw everything: 0 holders short-changed, 0 pools broken, $0.00 left stuck.

| Token | Coverage per token | v0.4 equivalent |
|---|---|---|
| `2x`, C = $3 | **$1.00** | v0.4 1x token at C = $3 locked **$2.00** of LP money per token |
| `2x`, C = $2 | $0.50 | |
| `3x`, C = $3 | $1.33 | |

Coverage counts **only USDC on Elysium**. The base and Hearth's hedge don't count in v1, so a problem with LiquidV or a bridge can never make a boost payout fail.

### 7.2 Free capital and withdrawals

```
Hearth free capital = Hearth cash − Hearth's coverage − cost of the hedge it still has to buy
Ember free capital  = Ember cash  − Ember's coverage
```

- LPs can withdraw any amount of **free capital**, never more. **An LP can't run away with money that backs a holder.** In the simulation, both pools tried to pull out everything every update for 90 runs: every holder sell was still paid in full.
- **Deposits and withdrawals fill at the next index update**, like buys and sells, with a small fee, so LPs can't time the pool against a hero whose state is public (e.g. deposit into Ember just before a visible liquidation).
- LP share prices **mark every Series' boost liability to market** before every deposit and withdrawal. A new LP never buys into, or dilutes, existing LPs' unrealized results.
- The withdrawal check runs after fees and PnL are settled, **per pool** (the Avantis audit lesson, unchanged).
- **Show "available now" next to "your value".** Part of an LP's marked value is locked (coverage, and the LPs' own unrealized gains, which sit inside the real token in the vault until holders sell or are stopped out). On real data an LP could withdraw 66–95% of their value on average, and as little as **11%** at the worst moment (Hearth, vSMARTEST). It's not a loss, but it must never be a surprise.
- **Leaving fast must not dump gap risk on the LPs who stay.** The mark prices a token's boost at today's price, not the chance of a gap through the stop. In round 3, a Hearth LP who left when the price got near the stop lost **$2**; the identical LP who stayed lost **$9,590** when the hero was then liquidated. Rule: while any of a pool's tokens is within a set distance of its stop, withdrawals from that pool leave behind a **gap holdback** (released once those tokens end or move away from the stop). With the $0.25 stop the holder's cushion takes ordinary gaps, so the holdback only matters for heroes whose account could be liquidated in one update.

### 7.3 Two pools

Every boost liability is backed by Hearth and Ember in a **split fixed when the token is minted**, by the pools' capital at that moment. Later deposits and withdrawals only change the split for new tokens.

**Why not a split that follows capital continuously:** every deposit or withdrawal would move Hearth's share of every existing token and force it to resize its hedge, paying LiquidV's 1% fee **for other people's deposits**. In the simulation, someone moving $25,000 in and out of Ember cost Hearth's LPs about **$8,000**; ordinary LPs coming and going cost them about $130. A split fixed at mint: $0.

| | **Hearth: "Steady"** | **Ember: "Boosted"** |
|---|---|---|
| Holds | USDC for coverage **plus `$vTRADER` against its share** | USDC for coverage |
| When boost holders win | Pays its share; **its `$vTRADER` rises the same** | Pays its share |
| When boost holders lose | Collects its share; **its `$vTRADER` falls the same** | Collects its share |
| Earns | **Fees + carry**, minus hedge costs | Fees + carry, ± buyers' boost results |
| APR | Lower, steady | Higher, swings, can be negative |
| Main risk | Stop-loss gaps, LiquidV risk | The heroes winning |

### 7.4 What LPs see

| Line | Hearth | Ember |
|---|---|---|
| Fee APR | ✅ | ✅ |
| Carry APR | ✅ | ✅ |
| Hedge cost (LiquidV fees, gap leaks) | ✅ negative | — |
| Trading APR (buyers' boost losses minus gains) | ≈ 0 | ✅ variable |
| Total APR, 7 and 30 day | "Variable, not guaranteed" | "Variable, can be negative" |

---

## 8. Hearth's hedge

### 8.1 Sizing

Hearth is short `(B − 1)` units of the hero's move per token (its share). Holding `(B − 1)` units of `$vTRADER` per token cancels it:

```
Hearth hedge, per Series = Hearth share × supply × (B − 1) / NAV_0    units of $vTRADER
```

**Example:** 100 tokens of `$WHALE 2x`, Hearth is the whole pool, so Hearth holds **$100 of `$vWHALE`** at launch.

### 8.2 Why it's an exact hedge

- It's the **same token** the price is computed from, so there's no tracking error before the stop-loss and max price.
- Like the base, it's a **fixed count** of units: it never needs resizing because the price moved, only when supply changes or the Hearth / Ember split changes.

### 8.3 When the hedge changes

| Trigger | Action |
|---|---|
| Buys or sells change supply | Resize, netted with base flows (§6.3), only outside a ±5% band. **Hearth never buys hedge with coverage money**: if free cash is short, it buys what it can, and buys on that hero pause |
| LP deposits or withdrawals change Hearth's share | Resize, same band |
| **Crowned** | Sell the hedge for that Series |
| **Knocked out** | Sell the hedge for that Series, immediately |

### 8.4 Where it leaks

```
Hearth return ≈ fees + carry − LiquidV mint/redeem fees on the hedge − stop-loss gaps
```

| Leak | Fix |
|---|---|
| **Stop-loss gap** (hero falls past the point where the ticket is worth $0 faster than the hedge can be sold; the holder's $0.25 cushion takes smaller gaps) | Fast triggers and prepared sell orders (§5.3); per-hero boost limits by hero leverage; Elysium speed (§9) |
| **LiquidV fees** on every hedge change | **Hedge fee paid by buyers and sellers** (§11.1). Without it the simulation had Hearth **losing about 1% in 11 days**, because LiquidV's 1% mint fee on the hedge outweighed Hearth's share of fees. With it, Hearth was **positive in the average run**. Plus netting with base flows and a no-trade band |
| **LiquidV capacity** (their vault is capped by the hero's size) | Supply caps per hero ≤ the `$vTRADER` capacity we can actually get (§10) |
| **LiquidV failure** (pause, depeg, hack) | Hearth bears it on the hedge, holders on the base; disclosed; breaker on NAV mismatch (§4.2) |

### 8.5 A note for v2: the hedge already covers the boost

At every price, Hearth's hedge is worth `(B − 1) × x` per token and its boost liability is `(B − 1) × (x − 1)`. **The hedge is always worth `(B − 1)` more than what it backs.** So with a haircut for selling risk, the hedge could count toward coverage and Hearth would need roughly **half the capital** of v1. v1 doesn't count it (§7.1); v2 should, once the custody of `$vTRADER` (§6.4) has been proven.

---

## 9. Why only on Elysium

| Need | On HyperEVM | **On Elysium** |
|---|---|---|
| Read the LiquidV vault's HyperCore account **trustlessly and fast** | Read precompiles, but a small, crowded chain (~3M gas/s) | **Market-data precompile from a co-located node, target ~200 ms** |
| Fire the **stop-loss and max price** at the right point | Seconds of delay: bigger gaps, bigger Hearth leak | **Sub-second: small gaps** |
| Reprice every Series of every hero constantly | Too expensive | **~100 ms blocks, 300 Mgas/s target** |
| Path B base (copying the hero directly) | CoreWriter is deliberately delayed by seconds | **Keeper fast-write lane, ~100 ms** |

**Speed is the risk model here, not a feature.** The faster Rhadamanthus sees the hero's NAV, the tighter the stop-loss, and the smaller the only real leak in Hearth's hedge.

**Dependency:** the HyperCore market-data precompile and keeper fast-write lane are scheduled for about four weeks after Elysium's Nov 9 mainnet, in an ArbOS upgrade. Launch is gated on both, on the precompile exposing **any address's** positions (here, LiquidV's vault accounts), and on §6.4.

---

## 10. Listing and lifecycle

### 10.1 Eligible heroes

A hero is eligible when:
- **LiquidV has tokenized them** (Path A), or the hero passes v0.4's Path B tests,
- `$vTRADER` has **enough capacity and liquidity** for our expected base and hedge,
- the account has ≥ $1M equity and ≥ 30 days of history (configurable),
- a **history replay** passes: Series, stop-losses, Crowns and Hearth's hedge are simulated on the account's past, including gap leaks,
- it is **not a market-maker-style wallet** (v0.4 §18),
- one wallet or a **wallet group** (v0.4 §18).

**Boost levels per hero:** v1 offers **2x** and **3x**. Heroes whose own leverage (notional ÷ equity) is high get only 2x, or a lower `C`.

### 10.2 Phases (unchanged)

```
PREVIEW ──▶ LIVE ──▶ (BUYS PAUSED ⇄ LIVE) ──▶ SETTLED
```

Preview runs the chart and a paper Series; going Live needs the **LP coverage target committed** (seed pot, refunds if it never fills; opening can use Cloak's sealed-bid launch). A hero that is liquidated, goes dormant or moves wallets is **Settled**: open Series freeze at their last valid price and stay redeemable forever. In practice a liquidated hero's Series have already been Knocked out.

### 10.3 Launch sequence

1. Partnership terms with **LiquidV** (§18, question 2).
2. Meadow genesis: Hearth first, with an early-LP boost.
3. 3–5 heroes, **2x only**, `C` = $2, small supply caps for 4 weeks.
4. Add 3x, raise `C` and caps as replay and live data allow.

---

## 11. Fees and revenue

### 11.1 Fees (illustrative, set by governance)

| Fee | Size | Charged on | Goes to |
|---|---|---|---|
| Buy fee | 0.30%, rising with utilization and hero leverage | The buy | §11.2 split |
| Sell fee | 0.30%, plus a size-based fee on large sells | The sell | §11.2 split; size fee stays in the pool |
| **Boost carry** | ~2–6% a year **on the boost part only**, rising with utilization | A slow drift in the price | §11.2 split |
| **LiquidV pass-through** | Their mint (1%) and exit (0.3%) fees on the buyer's own base | The buyer or seller, shown separately | LiquidV |
| **Hedge fee** | Hearth share × (B − 1) × LiquidV's fee: about **0.5%** to buy and 0.15% to sell, at a 50% Hearth share | The buyer or seller | Hearth, to pay for its `$vTRADER` hedge |
| Keeper bounty | Small fixed amount | Paid from fees | Keepers |

The buy screen shows the total cost, split into "Asphodel" and "LiquidV." At today's LiquidV fees, **entry costs about 1.8%** (0.3% Asphodel + 1% LiquidV + 0.5% hedge fee), against 1% to buy `$vTRADER` directly. That's the price of the second gain. Netting buys against sells (§6.3) avoids LiquidV's fee on matched flow; in the simulation about a fifth of base flow could be netted. A partner fee rate from LiquidV (§18) is the biggest lever.

### 11.2 Where Asphodel's fees go

| Recipient | Share |
|---|---|
| Meadow LPs (Hearth / Ember by capital; Ember lock boost) | 60% |
| Protocol treasury | 30% |
| Ascended hero (vested, v0.4 §18) | 10%, else to LPs |

Hearth's LiquidV fees on its hedge are mostly covered by the hedge fee; anything left (band resizes, gap leaks) is shown as its hedge cost.

### 11.3 How the company makes money

1. 30% of Asphodel fees, whether heroes win or lose. The protocol is the venue, not the house.
2. **Frontend fee on routed plain buys** of `$vTRADER` (§2).
3. Listing fees (v2), private mode premium (v2), integration rebates.

---

## 12. What every token and pool page must show

- **What it tracks:** "0xWhale's LiquidV token since launch, with an equal second gain from the pool. Perps only." Links to the hero and to `$vWHALE`.
- **Since launch vs the hero's own PnL**, side by side, so "the whale is green but my token is red" is never a surprise.
- **Backing:** "Real base: `$vWHALE` held in the Backing Vault" with the live vault balance, and "Boost: backed by the Meadow" with the live coverage ratio.
- **Stop-loss** and **max price**, as prices and as hero moves ("stops at $0 if 0xWhale falls 50% from launch").
- **Live effective boost** for a buyer right now.
- Supply cap and room left, carry rate, current state, price freshness.
- **LiquidV risk:** "The base depends on LiquidV."
- Pool pages: Hearth's APR split into fees, carry and hedge cost, labelled "hedged, not risk-free"; Ember's split into fees, carry and trading, labelled "unhedged, can lose."

---

## 13. Guardrails

| Guardrail | Rule | User-facing effect |
|---|---|---|
| **Coverage, per pool** | Each pool's USDC ≥ its share × Σ supply × max boost owed, after paying for the hedge (§7.1) | Invisible; why no holder can ever be owed more than the pool holds |
| **Free-capital withdrawals** | LPs withdraw only what isn't backing a holder or a pending hedge | "Available to withdraw: $X" |
| **Hedge fee** | Buyers and sellers pay Hearth's LiquidV cost on its hedge | Shown in the buy breakdown |
| **Mint limit near the stop-loss** | No new tokens while the live boost is above 4x (ticket close to $0); sells and DEX trading stay open | "New buys paused: close to stop-loss" |
| **Full base** | Vault holds `supply / NAV_0` units per Series, always | "Real base" balance on the page |
| **Max boost + Crown** | 2 updates at or above `C`; Meadow pays exactly `MAXB`; holder gets base sale proceeds + `MAXB` | "Max boost reached" |
| **Stop-loss** | 2 updates at or below $0.25; base and hedge sold at once, never before; holder gets what's left | "Stops at $0.25 if 0xWhale falls 37.5%" |
| **Fees only on your own share** | Near the stop most of the real token belongs to the LPs: the holder pays LiquidV and hedge fees only on their part, and a fee can never exceed what a seller is owed | Fair costs near the stop |
| **Real redemption on the base** | Sellers get what their base actually redeems for (LiquidV slippage on large exits is theirs, not the LPs') | "Large sell: est. slippage X%" |
| **Fixed split at mint** | Each token's Hearth/Ember split is set when minted (§7.3) | Invisible |
| **Gap holdback on LP exits** | Exits from a pool with tokens near their stop leave a holdback until those tokens end (§7.2) | "Part of your withdrawal is held until …" |
| **Supply cap** | ≤ LiquidV capacity, ≤ k × hero equity, ≤ Meadow-based cap | "Supply cap reached, buy on secondary" |
| **Exposure / concentration caps** | Per hero and across heroes, on boost liability | Buys pause for that hero |
| **Leverage-aware boosts** | High hero leverage means 2x only, lower `C` | Fewer or lower boosts while the hero is risky |
| **NAV mismatch breaker** | Our NAV vs LiquidV's rate beyond a threshold pauses buys; permissionless trip with proof | "Buys paused: under review" |
| **Fill rule** | Fill on a later oracle timestamp than the request, at the NAV read live from HyperCore, never LiquidV's published rate | Invisible |
| **Freshness pause** | No fills on stale data | "Waiting for price" |
| **Redemption queue** | Slow LiquidV redemption queues sells, never cancels | "Sell queued" (rare) |

**Principle (unchanged): sells are only ever paused by stale data.** Every other guardrail pauses buys.

---

## 14. Worked example

**Setup:** `$WHALE 2x` Series 1, `C` = $3 (stop-loss at $0.25, which is 0xWhale −37.5%; max boost at +100%; each needs 2 updates in a row). Alice buys **100 tokens for $100**. Fees and carry left out.

- Backing Vault buys **$100 of `$vWHALE`** (the base).
- Meadow locks **$100** of coverage (100 × $1.00).
- **Case 1, Bob is the Meadow (Hearth):** Bob's $200 deposit is $100 coverage + $100 of `$vWHALE` hedge.
- **Case 2, Carol is the Meadow (Ember):** Carol's $100 deposit is all coverage.

| 0xWhale | Alice | Base | Meadow pays (−) / collects (+) | Bob's hedge | **Bob net** | **Carol net** |
|---|---|---|---|---|---|---|
| +10% | $120 | $110 | −$10 | +$10 | **$0** | −$10 |
| +100%, **Crowned** | $300 | $200, sold | −$100 | +$100, sold | **$0** | −$100 |
| +110% at the sale (overshoot) | **$310**: $210 real + $100 boost | $210, sold | −$100 (never more) | +$110, sold | **+$10** | −$100 |
| −20% | $60 | $80 | +$20 | −$20 | **$0** | +$20 |
| −37.5%, **Knocked out** | **$25** (what's left) | $62.50, sold | +$37.50 | −$37.50, sold | **$0** | +$37.50 |
| Fast drop, base sells at −45% | **$10**: her cushion took the gap | $55, sold | +$45 | −$45, sold | **$0** | +$45 |
| Gap past $0, base sells at −60% | $0 | $40, sold, to Meadow | +$40 | −$60, sold | **−$20 gap leak** | +$40 |

Everyone also earns or pays fees. Only a gap all the way past $0 (the last row) reaches the LPs; that's the leak §5.3, §9 and the gap guard (§13) exist to keep rare.

---

## 15. Edge cases

| # | Edge case | Handling |
|---|---|---|
| 1 | Hero deposits or withdraws | NAV is per unit of LiquidV's vault, so the hero's own cash flows don't move it |
| 2 | Hero pumps a thin coin | LiquidV's own universe rules, plus our NAV cross-check, breaker and max move per update |
| 3 | Hero buys their own boost, then gambles | Capped by `C`, the stop-loss, supply caps and leverage-aware boosts |
| 4 | Bot sees a move before the price updates | Fill on a later oracle timestamp (§4.3) |
| 5 | Hero falls through the stop-loss in a gap Fast triggers, prepared sell orders; leak absorbed by the Meadow, Hearth's share shown as hedge cost |
| 6 | LiquidV pauses minting | Buys pause for that hero; sells net internally, else queue |
| 7 | LiquidV pauses redemption | Sells queue; Crowned and Knocked-out base sales queue; coverage untouched |
| 8 | `$vTRADER` NAV departs from the hero's wallet | Our price follows the NAV (the base stays exact); fidelity to the wallet is published |
| 9 | LiquidV hacked or depegged | Base value lost by holders, hedge value by Hearth; boost coverage still pays; disclosed |
| 10 | Bridge or cross-chain vault failure (§6.4) | Same as 9 for whatever it holds; coverage is on Elysium and unaffected |
| 11 | Effective boost drifts far from 2x | The page shows the live effective boost; above the limit the Meadow stops minting (sells and secondary trading stay open); a new Series opens only after Crown or Knockout |
| 12 | Many Series Crowned or Knocked out at once | Each was fully covered; redemption queue never cancels |
| 13 | LP bank run | Only free capital leaves; LP deposits and withdrawals fill at the next update |
| 14 | Elysium sequencer down | Everything pauses; the base and hedge are tokens and need no maintenance |
| 15 | Hero liquidated | Series are Knocked out on the way down; hero Settled |
| 16 | Rounding or dust | Rounding favours the Meadow by at most 1 wei per operation |

### Invariants (fuzz-tested)

- **Coverage:** Elysium USDC ≥ Σ supply × (B − 1)(C − 1)/B, with base and hedge excluded.
- **Full base:** for every live Series, vault units = supply / NAV_0.
- **Bounded prices:** 0 ≤ price ≤ `C`.
- **Price identity:** price = base + boost, for every Series, every update.
- **Withdrawals:** no LP withdrawal makes either pool's free capital negative.
- **Sells:** a sell with fresh data is never refused (it can only be queued).
- **Isolation:** a total loss of LiquidV or the bridge can reduce holders' base and Hearth's hedge, but never breaks boost coverage.

---

## 16. Contract architecture

```
HeroRegistry       listing, phases, boost levels and parameters per hero, LiquidV token address
Rhadamanthus       reads LiquidV vault accounts via the Elysium HyperCore precompile, computes NAV,
                   cross-checks LiquidV's rate, stores x with HyperCore timestamps, freshness and breaker
BoostToken (ERC20) one per hero × boost × Series; mint/burn only by Meadow; price = f(x, B, C, carry);
                   Crown and Knockout
BackingVault       holds base $vTRADER per Series (Elysium or HyperEVM-side, §6.4); nets flows;
                   mints and redeems with LiquidV
Meadow             buy and sell, boost settlement, coverage, Hearth and Ember, LP shares marked to market,
                   free-capital withdrawals, fees
HearthHedge        holds Hearth's $vTRADER per Series; resizes on supply and share changes; sells on Crown
                   and Knockout
RiskEngine         per-pool coverage, caps, mint limit, leverage-aware boosts, dynamic fees and carry,
                   hedge fee, relaunch after Crown or Knockout, redemption queue
Hedger (Path B)    v0.4 copy hedger, for heroes without a $vTRADER
Treasury           protocol and Ascended fee shares
Keepers            index, fill, Crown/Knockout and netting keepers (permissionless, with bounties)
```

### Core interface (sketch)

```solidity
interface IMeadow {
    function requestBuy(address boostToken, uint256 usdcIn, uint256 minTokensOut) external returns (uint256 id);
    function requestSell(address boostToken, uint256 tokensIn, uint256 minUsdcOut) external returns (uint256 id);
    function fill(uint256 id) external;          // keeper; first update with a later oracle timestamp

    enum Pool { Hearth, Ember }
    function requestDeposit(Pool pool, uint256 usdc, uint32 lockDays) external returns (uint256 id);
    function requestWithdraw(Pool pool, uint256 shares) external returns (uint256 id);  // free capital only
    function freeCapital(Pool pool) external view returns (uint256);
    function coverageRatio() external view returns (uint256);
}

interface IBoostToken {
    function hero() external view returns (address);
    function boost() external view returns (uint256);           // B
    function maxPrice() external view returns (uint256);        // C
    function startNav() external view returns (uint256);        // NAV_0
    function price() external view returns (uint256);
    function basePerToken() external view returns (uint256);    // 1 / NAV_0, in $vTRADER units
    function effectiveBoost() external view returns (uint256);  // B × x / price
    function state() external view returns (uint8);             // Live, Crowned, KnockedOut, Settled
    function crown() external;                                  // anyone, when price ≥ C
    function knockOut() external;                               // anyone, when price ≤ 0
}

interface IRhadamanthus {
    function poke(address hero) external;
    function nav(address hero) external view returns (uint256 value, uint64 hlTimestamp);
}

interface IBackingVault {
    function baseUnits(address boostToken) external view returns (uint256);
    function settleNet(address hero) external;   // keeper; nets buys and sells, mints/redeems the rest
}
```

---

## 17. Roadmap

| Version | Adds |
|---|---|
| **v1** | Path A heroes (LiquidV-tokenized), 2x and 3x boosts, one common zero per token (relaunch after Crown or Knockout), stop-loss and max price, Hearth hedged with `$vTRADER`, Ember, all §13 guardrails, routed plain buys |
| **v2** | Hearth's hedge counts toward coverage with a haircut (§8.5); Path B self-backed heroes; private mode (Cloak); permissionless listing |
| **v3** | Other payout shapes on the same real base: "is 0xWhale up this week?", boosts with a floor; hero baskets; ZK-proven private heroes |

---

## 18. Open questions

1. **Custody of `$vTRADER`:** HyperEVM-side vault controlled from Elysium, or a bridged token? What is the trust model, and how fast can it sell at a stop-loss?
2. **LiquidV partnership, and capacity (the biggest blocker).** Today's LiquidV vaults hold **$9 to $1,334** each (vANSEM: $641). $10,000 of our tokens needs ~$10,000 of `$vTRADER` base plus Hearth's hedge: **7x to 1,000x the size of their vaults**. We would *be* their vault. We need: minting and redeeming at size, a partner fee rate (their 1% mint fee is most of our entry cost), capacity per hero (their vault is capped by the trader's size), mint/redeem latency, and their answer if they launch boosts themselves.
3. **Precompile scope and speed:** does Elysium's precompile expose LiquidV's vault accounts, at what latency (target ~200 ms), and can Rhadamanthus reproduce LiquidV's NAV exactly?
4. **Stop-loss gaps:** real gaps exist (vFLOOD fell **58.7% in one update**). In the simulation, gap leak stayed small: $5 a run on average, with Hearth's worst run −5% even with every move made 3x bigger. It needs re-running at real sizes and on longer histories.
5. **Hearth's real APR:** the simulation's 11 days and random traders are too short and too artificial to quote an APR. Hearth was positive on average with the hedge fee and negative without it. A replay on months of data with realistic flow is still needed.
6. **Live boost UX:** is "today's boost: 1.7x" understandable to a late buyer?
7. **Legal:** boosted payouts on another person's trading are derivatives in many jurisdictions. Geo-restrictions and terms before launch.
8. **Hero consent:** should un-Ascended heroes be able to opt out? Ember LPs profit when a public hero loses, which gives them a reason to hunt the hero's public liquidation price.

---

## 19. Carried over from v0.4, and what's dropped

**Still applies:** the myth and naming, freshness and `block.number` rules, Preview / Live / Settled, the seed pot and sealed-bid opening, wallet groups, market-maker exclusion, history replay, published fidelity, the permissionless breaker, vested Ascended royalties, trade-only keys (Path B), the coverage-first safety model, the Avantis withdrawal lessons, privacy via Cloak (v0.4 §12), and the full LiquidV and Bounce analysis (v0.4 §18).

**Dropped:**
- The synthetic 1x hero token. Plain exposure is LiquidV's `$vTRADER`, which we route to.
- Hearth's copy-bot hedge, except as Path B.
- Carry of 10–20% a year. Carry is now charged on the boost part only, benchmarked against Bounce's 2%.

---

## 20. Simulation: trying to break it on LiquidV's live prices

**What was run.** A model of this spec (`asphodel-sim/sim/engine.py`) on the real price history of **18 live LiquidV tokens**, including vANSEM: about 720 updates each over 11 days, one every 7–23 minutes, with LiquidV's live fees (1% mint, 0.3% exit). Each boost token starts at $1.00, `B` = 2, max price $3, stop-loss $0, Hearth $25,000 and Ember $25,000. Full output: `asphodel-sim/SIM-REPORT.md`. Closed-form tests (`sim/tests.py`) reproduce §14 exactly, including Bob's −$10 gap leak.

**Results:**

| Attack or test | What happened | Verdict |
|---|---|---|
| Normal trading, 720 runs | 0 rule violations. Hearth **+1.3%** on average over 11 days (worst −2.5%); Ember ±16% depending on the hero. Gap leak $5 a run on average | ✅ |
| **Without the hedge fee** | Hearth **−1.1%** on average (worst −4.3%): LiquidV's 1% mint fee on the hedge eats its fees | ❌ → hedge fee added (§11.1) |
| **Coverage checked on the Meadow's total** (earlier draft) | Fuzz runs broke coverage and some sells couldn't be paid | ❌ → per-pool coverage after the hedge (§7.1) |
| One buyer fills the pool at launch | Buys refused once coverage was full. Paid out in full everywhere, up to $67,000 when vRTB2 jumped 79%. Ember took it (−43% on vRTB2); Hearth ≈ 0. Hearth's capital ($2 per token) runs out first | ✅ |
| Cheap tickets near the stop-loss | Blocked by the 4x mint limit. With the limit off, the buyer lost everything on vSMARTEST | ✅ |
| LP bank run: both pools pull out everything, every update, 90 runs | Only free capital left; every holder sell paid in full | ✅ |
| Attacker knows the next price and fills at the **current** one | Up to **+$13,000 on one token**; Hearth −37% there | ❌ if fills used a stale price |
| Same attacker, **next-update fills** (the spec rule) | Attacker **−$202,000** across 18 tokens; LPs gain the fees | ✅ |
| Every move made 2x and 3x bigger | 0 violations; Hearth's worst −5%; gap leak up to $179 a run | ✅ |
| Fuzz: 3,000 random jumpy markets, random buys, sells and withdrawals | 0 violations after the per-pool fix | ✅ |
| Capacity vs LiquidV's vaults | Their vaults hold $9–$1,334; $10,000 of our tokens is 7x–1,000x that | ⚠️ business blocker (§18, question 2) |

**What it shows.** The guardrails hold: no holder was ever owed more than a pool held, no LP could take money backing a holder, and sells always paid. Three things had to change, and all are now in the spec: per-pool coverage, the hedge fee, and never filling against a stale price. The remaining risk isn't the math, it's **LiquidV's size and fees**.

**Limits of the simulation.** 11 days of data; random traders, not real ones; tiny real vaults; no carry; Hearth and Ember shares fixed for each run; custody (§6.4) not modelled. A replay on months of data at realistic sizes is next.

---

## 21. Rounds 2 and 3: attacks, and bugs where honest people lose

Round 2 (`asphodel-sim/ATTACK-REPORT.md`) attacked the design as the market, the hero, buyers and LPs. Round 3 (`asphodel-sim/FAIRNESS-REPORT.md`) looked for the more dangerous kind of problem: **rules that make an honest holder or LP lose money they were owed, or stop them being paid.** Engine: `sim/engine2.py`; closed-form tests: `sim/tests2.py` (all pass, including §14's rows under the final rules).

### Fairness bugs found and fixed

| # | Bug | Who lost | How much | Fix (now in this spec) |
|---|---|---|---|---|
| 1 | Instant stop on a one-update wick | Holders, permanently | 44% of real stop hits bounced back the next update; a 70% wick wiped holders in 83% of runs | Stop needs **2 updates in a row** (§5.3) |
| 2 | Stop at $0: gaps skip it | LPs | Avg $0.02, worst $0.09 per ticket on real data | Stop at **$0.25**: the holder's cushion takes the gap; LPs short **$0.00** on real data (§5.3) |
| 3 | Crown promised "exactly $C" | Somebody can't be paid | Needed $0.56 per ticket against $0.50 of coverage when the base sold one update late | Meadow pays **exactly the covered boost**; holder gets base proceeds on top (§5.2) |
| 4 | Whole price capped at `C` | Holders: their own real-token gains taken | Avg $0.20, worst $0.38 per ticket (real data, $2 max) | Cap only the LPs' boost; the real token stays the holder's (§5.1) |
| 5 | Above the max but before the Crown confirmed, a seller got $3 | Holders | The real token's value above the max | Price = real token + capped boost at all times (§5.1; test added) |
| 6 | Near the stop, a sell could owe more fees than it was worth | Holders: the sell would revert ("sells always open" broken) | −$0.22 on a $100 position in v1 | Fees only on the holder's own share, never more than they're owed (§13) |
| 7 | LiquidV fees charged on the LPs' part of the base | Buyers near the stop | Buy cost 27.8% vs 12.3% fair at a $0.02 ticket; 7.9% vs 3.9% at $0.10 | Same as #6 |
| 8 | Coverage checked on the Meadow's total (round 1) | Holders: some sells unpaid | Fuzz failures | Per pool, after the hedge (§7.1) |
| 9 | Hearth/Ember split followed capital | Hearth LPs paid for others' deposits | ~$8,000 from someone flipping $25k; ~$130 from ordinary churn | Split **fixed at mint** (§7.3) |
| 10 | Index price paid on the base during big exits | LPs ate LiquidV slippage | $17,000 average at $50k depth | Sellers get the base's real redemption (§13) |
| 11 | Fast LP exits before a gap | LPs who stay | Leaver −$2, stayer −$9,590 | **Gap holdback** on exits (§7.2). Only partly tested: the rough version cut the stayer's loss to −$8,677, so this needs a proper design |

**After the fixes, a full-exit check passed every time:** at 649 random moments on real data, every holder sold everything, then every LP withdrew everything: 0 short-changed, 0 pools broken, nothing stuck. 4,000 fuzzed chaotic markets (random rules, wicks, pumps, liquidations, stale feeds, LP churn): **0 violations**.

### Attacks, naive settings vs this spec's settings

| Attack | Naive | This spec |
|---|---|---|
| 70% one-update wick: holders wiped | 83% | **0%** |
| One-update pump to the max: attacker's prize | $42,600 (and 4,365 coverage violations) | **$664**, 0 violations |
| Ember LP pushes the price through the stop: retail holders | −$9,105 | −$3,231 |
| Mass exit through a thin LiquidV vault: LPs | −$25,288 | −$8,231 |
| Someone flipping Ember capital: Hearth | −$7,977 | **$0** |
| Hero makes his account a ±50% coin flip: attacker | +1.2% | 0% (mints refused by the gap guard) |
| Normal trading: Hearth / Ember | −1.4% / −3.7% | **+1.2%** / −1.4% |

### Speed, revisited

With a $0 stop, what LPs lose to gaps grows about **70x** between 0.5-second and 20-minute updates (a 25x-leverage hero: $0.0006 vs $0.042 per ticket per stop hit). With the $0.25 stop the LPs lost **$0.00 at every speed**, because the holder's cushion takes the gap. So speed now mostly protects **how much holders keep** at the stop. Faster is still better, and Elysium's precompile matters for that.

### Still open

- **A hero liquidated in one update from far above the stop.** No stop can catch it: holders lose their stake, and Hearth loses its hedge (about $4,300 per event in the simulation, under any stop). It didn't happen in 11 days of real data, but Hyperliquid whales do get liquidated. Defences: listing rules on hero leverage and distance to liquidation (readable on HyperCore), the gap guard, and pricing it into fees.
- **LiquidV hacked:** holders lose their base and Hearth its hedge; coverage cash is untouched. Disclose.
- **Quiet heroes:** on real data, LiquidV NAVs didn't move in 43–100% of updates (heroes holding no positions). LP coverage stays locked and earns little meanwhile. Needs a dormancy rule that settles and releases capital.
- **Stale feeds** pause sells by design; in a crash, holders are stuck until data returns.
- **Gap holdback (#11)** needs a proper design and test.

---

### Prior art this spec draws on

- **LiquidV:** backed trader tokens on Hyperliquid; the base of every boost token. ([liquidv.xyz/llms-full.txt](https://liquidv.xyz/llms-full.txt))
- **Bounce:** leveraged tokens with daily-style rebalancing, the leak our fixed boost avoids; fee benchmark. ([docs.bounce.tech](https://docs.bounce.tech/llms.txt))
- **GMX, gTrade, Avantis, Jupiter JLP, Hyperliquid HLP:** LP-as-counterparty, reserved maximum profit, profit caps, utilization fees and their audit lessons (as in v0.4).
- **Knock-out certificates** (retail structured products): fixed terms from issue and a known stop-loss level, the model for the stop-loss and max price.
- **Opyn, Pendle, Polymarket:** one token per set of terms, made by a factory contract. That's how a relaunched token (S2 after a Crown or Knockout) is deployed as an ordinary ERC-20.
