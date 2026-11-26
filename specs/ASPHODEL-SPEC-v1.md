# Asphodel v1 (draft): baskets first

**Status:** draft spec, nothing built yet · **Date:** 2026-11-26
**Replaces as the plan:** v0.5 (LiquidV trader tokens). v0.5 and the stocks section v0.1 stay in this folder as history; their code stays in the repo, parked.

> "ETF" and "basket" here mean an on-chain basket of tokenized stocks, not a regulated fund. Capital is at risk.

---

## 0. What changed, and why

| | v0.5 | v1 |
|---|---|---|
| **What people hold** | LiquidV trader tokens (`$vTRADER`) | **Our own baskets of tokenized stocks** (`$BASKET` shares) |
| **Cost to buy and sell the base** | ~1.3% round trip (LiquidV's 1% in, 0.3% out), instant only up to LiquidV's spare cash | **0% in kind**, ~0.2–0.5% through a swap; redeeming in kind is always instant |
| **Leverage pools** | Hearth (hedged) + Ember (bold) | **Hearth only.** Ember moves to the roadmap (§7) with its guardrails |
| **Hearth's money per $1 of 2x** | $2: the hedge plus the same again in locked cash | **$1: the hedge only**, all in basket shares (§5.3) |
| **The game** | None | **The Funding League**: stakers pay a small daily funding fee; each week it goes to the people who held the best baskets (§4) |
| **Chain** | Elysium / HyperEVM | **BNB Chain** (§2.1) |

**Build order:** baskets (§3) → the League (§4) → leverage (§5). Each layer only launches once the one below it is proven. Leverage needs an on-chain price we haven't verified yet (§9), so it comes last.

---

## 1. The three layers in one example

**Layer 1: the basket.**
- Kemi creates **AI Kings**: NVDA 30%, MSFT 25%, AVGO 25%, AMD 20%.
- She seeds it with $100 of those four stock tokens and gets 10 shares at $10.
- Anyone can mint more, at the share's value, by putting in the same stocks or USDT. Anyone can redeem for the stocks or USDT.

**Layer 2: the League.**
- Tolu holds 100 AI Kings shares ($1,000) and **stakes** them in the League.
- He still owns the stocks and keeps their gains. He pays a small daily funding fee (0.02% a day ≈ $1.40 a week).
- All the funding paid that week goes into a pot. The pot goes to the stakers of the week's best baskets, most of it to the top one.

**Layer 3: leverage (Hearth only).**
- Alice wants 2x on AI Kings. Her $1,000 buys 100 shares, which stay **hers**, held for her.
- Bob, a Hearth LP, puts in 100 AI Kings shares ($1,000) as the other 1x.
- The basket goes +10%: Alice's ticket is worth $1,200, paid in shares, and Bob still has $1,000. The basket goes −10%: Alice has $800 and Bob still has $1,000.
- Bob earns a daily carry from Alice, plus fees. Alice gets 2x without borrowing.

---

## 2. Foundations

### 2.1 Chain and stock tokens

**BNB Chain**, using the work already tested in `NECOKIZZ/ETF` (Median Markets):
- **bStocks** (~46–60 tokens):
  - simple ERC-20 tokens that trade 24/7 and have no share ratio;
  - they move into and out of a brand-new contract with no allowlist (tested on a mainnet fork).
- **Ondo** tokens:
  - they have market sessions;
  - token price = share price × `tokenToShareRatio`, and the ratio grows with reinvested dividends, so dividends are built in.
- **xStocks:** when they appear in the API (they don't yet).
- **Swaps:** quotes and swaps through the Binance Web3 trading API, with a referral fee for creators (checked on a real $5 buy: the 1% fee came off exactly). Liquidity mostly sits in BNB pools on PancakeSwap. Price impact at $5–10 was 0.003%; larger sizes are unmeasured (§9).
- **Gas:** fractions of a cent.

**Why not the Base / B20 / Chainlink version** (from the Gemini draft):
- We haven't verified B20 tokens or Chainlink total-return feeds on Base.
- BNB Chain is where we've actually moved real stock tokens through contracts.
- Base or Robinhood Chain can come later if their feeds and liquidity check out.

### 2.2 Which tokens a basket may hold

Taken from the ETF repo's tested rules (`src/bsc/tokens.ts`):
- Allowlisted stock and fund tokens only.
- **Banned:**
  - leveraged and inverse funds (TQQQ, SOXL…), which would win the League by volatility alone;
  - pre-IPO tokens, which have no reliable price;
  - anything not trading.
- **Crypto slice:** BNB, BTC and ETH, up to 20% of a basket together. A basket still needs at least 3 stocks or funds. Baskets with a crypto slice can't be leveraged at launch (§5.6).

### 2.3 Prices

**The basket itself never needs a price to mint or redeem** (§3.3). That's deliberate: the foundation works even if every oracle is down.

| Who needs a price | For what | Source |
|---|---|---|
| Rider baskets | Nothing on-chain | – |
| Zaps (USDT in/out) | A safety limit on the swap only | The swap's own output, checked against a reference price |
| Rebalancer baskets | To see drift and check each trade | An on-chain price, with staleness checks (§3.2) |
| The League | Weekly scores | **v1:** a keeper posts Binance reference prices × `tokenToShareRatio`, and anyone can recompute them (§4.7). **v2:** an on-chain oracle |
| Leverage | Every update: stop, max, ticket value | **An on-chain price with staleness and deviation checks. A hard requirement: no leverage launch without it** (§9) |

---

## 3. Layer 1: the basket

### 3.1 Creating a basket

`createBasket(name, symbol, tokens[], weightsBps[], mode, driftBps)` is open to anyone.

| Rule | Value | From |
|---|---|---|
| Tokens | 3 to 10, every one allowlisted, at least 3 stocks or funds | ETF repo |
| Weights | Add to 100%. Every token **≥ 5%** and **≤ 50%** | ETF repo + Gemini |
| Crypto | ≤ 20% together | ETF repo |
| Seed | The creator puts in **≥ $10** of the tokens, in the weights (in kind or by zap) | ETF repo |
| No near-clones | Same set of tokens as a live basket **and** weights less than **10%** apart → refused, with a link to the existing basket | Gemini (the ETF repo merged clones into one team; refusing is simpler for a permanent token) |
| Name | ≤ 32 bytes | ETF repo |
| Creator fee | 0–1% on zaps into this basket (§3.4) | ETF repo (was 0–2%) |

How the 10% gap is measured: half the sum of |weight difference| across the tokens. Example: AI Kings (30/25/25/20) vs 35/25/25/15 → (5 + 0 + 0 + 5) ÷ 2 = 5%, **refused**. vs 40/20/20/20 → (10 + 5 + 5 + 0) ÷ 2 = 10%, **allowed**.

There's no $100 crowdfunding phase (it was in the Gemini draft). One creator and $10 is enough to exist. The League and leverage set their own size minimums.

### 3.2 Two kinds of basket

| | **Rider** ("let it run") | **Rebalancer** ("keep the weights") |
|---|---|---|
| After creation | Holds the same quantities forever. Weights drift with prices | Trades back to the target weights when any weight drifts more than its threshold (2–25%, set at creation) |
| Its return | Exactly buy-and-hold of the seed basket | Constant-weight return, after trading costs |
| Needs a price on-chain | No | Yes, to see drift and check trades |
| Launches | **First** | After an on-chain price is verified |

**Example: AI Kings after NVDA doubles** (everything else flat):

| | NVDA weight |
|---|---|
| Rider | 30% → **46%**. Nothing trades; the winner keeps running |
| Rebalancer (5% threshold) | Sells NVDA back to 30% and buys the other three |

**The Rebalancer's rules:**
- `rebalance()` can be called by anyone once a weight is past its threshold.
- **When:** only during US market hours, at most once every 6 hours.
- **How much:** each call trades at most 5% of the basket's value, so a big drift takes several calls. That keeps each swap small and harder to sandwich.
- **Price check:** every leg must come within 0.5% of the on-chain reference price, or the whole call reverts.
- **Who can be used:** allowlisted routers only, sent privately where the chain allows it.
- **Caller's tip:** 0.05% of the value traded, paid by the basket. The cost shows in the basket's value, so holders see it.

### 3.3 Minting and redeeming

**In kind (the default, free).**
- **Mint:** put in each token in the basket's current proportions. You get shares = the smallest of (your amount ÷ the basket's holding) for each token, × supply. Anything over the proportions comes straight back.
- **Redeem:** burn shares and get your share of every token.
- No price, no swap, no fee. It's always instant, because the tokens are right there.

**Example:**
- AI Kings has 1,000 shares and holds 3 NVDA, 5 MSFT, 4 AVGO and 15 AMD.
- To mint 100 shares (10%), you put in 0.3 NVDA, 0.5 MSFT, 0.4 AVGO and 1.5 AMD.
- Redeeming 100 shares gives you exactly those back.

**By zap (USDT).**
- **Zap in:** the router splits your USDT by the basket's current proportions (Rider) or its target weights (Rebalancer, which then rebalances them). It buys each token, then mints **in kind with what was actually bought**. You get what the swaps really delivered, never a quoted number. A `minShares` you set protects you.
- **Zap out:** redeem in kind, then swap each token to USDT, with a `minOut` you set.
- **Fees:** protocol 0.20% plus the creator's fee (0–1%), on zaps only.

**Paused stock tokens.** A token's issuer can pause it.
- Redemptions pay out every other token straight away. The paused token's part stays claimable for when it's unpaused. A paused token can never block a whole redemption (tested in the ETF repo's escrow).
- In-kind mints and zaps into that basket wait.

**Blocklists.** If an issuer blocklists the basket contract itself, that token is frozen inside it. This is a listing risk (§9). Prefer issuers whose rules don't allow it.

### 3.4 Fees for the basket layer

| Action | Fee |
|---|---|
| Mint or redeem in kind | 0 |
| Zap in or out | 0.20% protocol + 0–1% creator (zap in only) |
| Rebalance | Swap costs + 0.05% caller tip, paid by the basket |
| Holding | 0. No management fee. Hearth and the leverage market hold baskets too, and must not pay for holding |

### 3.5 Dividends and splits

- **Ondo** tokens pass dividends through their growing share ratio, so the basket's value includes them automatically.
- **bStocks:** how dividends reach holders is **not yet known** (§9). Until it is, the League scores by the token's own price (what holders actually have), so everyone is treated the same.
- **Splits:** the basket only counts token quantities and token prices, never a raw share price.
  - Any single token moving over 30% in one update pauses that basket's Rebalancer and leverage until checked against a second price.
  - The League marks it for review.

---

## 4. Layer 2: the Funding League

### 4.1 The idea

Basket holders who want to play **stake** their shares. Staked shares:
- **keep everything:** the stocks, their gains, dividends, and the right to unstake;
- **pay a small funding fee every day;**
- **win** if their basket is one of the week's best.

All the funding paid in a week goes into the week's pot. The pot goes to the stakers of the best baskets, by stake × how close their basket came to the top. **No tickets.** You just pay to stay in, like funding on a perp.

### 4.2 Why staking is opt-in, not a fee on every holder

The draft idea was to tax every basket holder. Three reasons not to:
1. **Hearth's hedge and Alice's leveraged base are basket shares.** Taxing them would drain the leverage layer for a game they're not playing.
2. **A plain holder** who just wants AI Kings would pay a hidden fee for a lottery they never entered. The basket would then be worse than holding the stocks directly.
3. **A fee on everyone looks like a gambling tax on an investment product.** An opt-in contest is easier to explain and to defend (§9, legal).

### 4.3 The week

| | |
|---|---|
| **Round** | Monday at the US open (13:30 UTC; 14:30 in winter) → the next Monday's open |
| **Score** | The basket's % change in value per share. Each end is a 30-minute average price after the open (ETF repo rule) |
| **Joining** | Stake at any time. **Your stake starts counting from the next round.** Nobody can join once a winner is visible |
| **Funding** | 0.02% a day on staked shares (≈ 0.14% a week, ≈ 7.3% a year), charged every second while counted |
| **Leaving** | Unstake at any time. Funding stops at once. You give up any prize for the round in progress, and your share of it goes to the others in your basket |

**How the funding fee is taken.** Staked shares shrink slowly: 100 shares are 99.86 shares after a week. The shares taken go to the pot. At settlement, the pot's shares are zapped out to USDT in one batch per basket, during market hours, and winners claim USDT.

### 4.4 Who wins

We reuse the tested scoring from the ETF repo (`src/engine/league.ts`). It was stress-tested with exploits and 20,000 random rounds. The only change is the pot: it's funding, not $5 tickets.

1. **Which baskets count:**
   - staked value at the start of the round ≥ **max($500, 1% of all staked value)**;
   - at least one full round old;
   - no leveraged funds (§2.2).
2. **Distance:** D = best return − this basket's return.
3. **Top half wins:** with n baskets, k = n // 2 + 1 and m = the k-th smallest D. A basket wins if D < m. Boundary ties lose.
4. **Accuracy:** a = (1 / (1 + D/m))⁶. The best basket has a = 1. A basket halfway to the cut-off has a ≈ 0.09. That's what makes the **top basket take most of the pot**.
5. **The pot, after the take,** is split across winning baskets by **staked value × accuracy**, then inside each basket by stake.
6. **Creators** get 5% of their basket's stakers' winnings (not of their own). The ETF prototype used 10% and found backers paid creators about 1.5 points on top of the house edge, so it's halved.
7. **Take:** 10% of the pot: 5% protocol, 5% season pot (season prizes are still to design).
8. **The round is void, and the funding refunded in shares,** if there are fewer than 4 eligible baskets, every return is equal, a scored token is paused or has a stale price at a snapshot, or the keeper misses settlement for 3 days.

### 4.5 A week in numbers

$100,000 is staked across four eligible baskets, so the pot is $100,000 × 0.14% = **$140**. After the 10% take, **$126** goes to winners.

| Basket | Staked | Return | Funding paid | D | Wins? | Accuracy | Weight | Prize | Stakers' net from the League |
|---|---|---|---|---|---|---|---|---|---|
| AI Kings | $40,000 | +4.0% | $56 | 0 | ✅ | 1.000 | 40,000 | **$120.70** | **+$64.70** |
| Chips | $20,000 | +2.5% | $28 | 1.5 | ✅ | 0.088 | 1,756 | $5.30 | −$22.70 |
| Big Tech | $30,000 | +1.0% | $42 | 3.0 | ❌ (D = m) | – | – | $0 | −$42 |
| Value | $10,000 | −1.5% | $14 | 5.5 | ❌ | – | – | $0 | −$14 |

Here n = 4, so k = 3 and m = the 3rd smallest D = 3.0. Each basket's stakers also keep its real return: AI Kings' +4% on $40,000 is +$1,600 of stock gains, separate from the League.

**What it costs a player.**
- Funding is ~7.3% a year, and on average ~90% of it comes back as prizes.
- So a player with **no skill** loses about the take, ~0.7% a year: about what an ETF charges.
- A player who picks better than average comes out ahead.

### 4.6 Why not "winner takes all"?

The plain version is that the whole pot goes to the stakers of the single best basket. The trouble is that **anyone can make lots of small, wild baskets:**
- Someone creates 20 concentrated two-stock baskets with $1,000 each.
- One of 20 wild baskets is very likely to top the table in any given week.
- Under winner-takes-all, $1,000 of stake would collect the whole pot, paid by everyone else's funding.

Weighting by **staked value × accuracy** removes that edge:
- A $1,000 basket at the top gets a weight of 1,000, against AI Kings' 40,000.
- The minimum size (1% of all staked value) also means 20 baskets need 20% of the whole League staked.

The top basket still takes most of the pot (95.8% in the example above), so the spirit of "highest PnL wins" stays.

**Other attacks checked in the ETF prototype:**
- **Junk baskets to move the cut-off:** net −$24 to −$98, unprofitable.
- **Fake wallets backing your own basket:** just more stake at the same odds.

### 4.7 Settlement and trust (v1)

As in the ETF repo:
- A **keeper** computes the result off-chain with the open-source engine and submits it.
- **On-chain, the contract enforces:**
  - conservation: Σ prizes + take = Σ funding collected;
  - no prize above the cap;
  - staked shares always go back to their owners.
- The inputs (prices, stakes, baskets) are **committed by hash and published**, so anyone can recompute the result.
- **If the keeper doesn't settle within 3 days,** anyone can void the round.

v2 moves scoring on-chain once an on-chain price is verified.

---

## 5. Layer 3: leverage with Hearth

### 5.1 The product

**Classic 2x** on a basket. The pricing is unchanged from v0.5:
- **Ticket price** = 1 + B × (x − 1), where x = the basket's share value now ÷ at the series start. It starts at $1.
- **The stop:** $0.25 on 2 updates in a row (basket −37.5% at 2x). The series ends, and holders keep what's left.
- **The max:** $2 for stock baskets (basket +50% at 2x), on 2 updates. The series ends and pays out.
  - v0.5 used $3, but a stock basket can take years to double.
  - A lower max ends the series sooner, so holders roll into a fresh 2x.
- **One common zero per series;** new series open as old ones end.

### 5.2 Where the money sits

| | Holds | Whose |
|---|---|---|
| **Alice's base** | The basket shares her own money bought | **Hers.** Held for her and never lent out. It's her real exposure and her margin |
| **Hearth's hedge** | (B − 1) shares per ticket at the series start, so 1 share per ticket at 2x | Hearth's. It's both the hedge and the collateral |
| **Cash** | None needed (§5.3) | – |

### 5.3 Why Hearth needs only $1 per $1, all in shares

At 2x, the market holds 2 shares per ticket: 1 of Alice's and 1 of Hearth's. Alice is owed 1 + 2(x − 1) = 2x − 1 per ticket. Whatever x does:

> 2 shares × x − (2x − 1) = **$1 per ticket, always Hearth's**

Everything is **paid in basket shares**, so the market never has to sell anything to pay someone. It just moves shares. A seller who wants USDT zaps out (§3.3).

**Alice $1,000 at 2x on AI Kings, share price $10.** Alice has 100 shares and Bob (Hearth) has 100 shares.

| AI Kings moves | Share price | Alice's ticket | Alice gets | Bob keeps | Bob's value |
|---|---|---|---|---|---|
| +10% | $11.00 | $1,200 | 109.09 shares | 90.91 shares | **$1,000** |
| −10% | $9.00 | $800 | 88.89 shares | 111.11 shares | **$1,000** |
| +50% (the max) | $15.00 | $2,000 | 133.33 shares | 66.67 shares | **$1,000** |
| −37.5% (the stop) | $6.25 | $250 | 40 shares | 160 shares | **$1,000** |
| **−60% in one jump** | $4.00 | $0 | 0 shares | 200 shares | **$800 (−$200)** |

v0.5 asked Hearth for $2 per $1: the hedge plus as much again in cash, so LiquidV's limited spare cash couldn't delay payouts. With our own baskets, shares move instantly, so the cash isn't needed. **The same fees and carry earn Hearth twice the return.**

### 5.4 What Hearth earns

| Source | Rate (illustrative) | Example: Bob's $1,000 backing Alice's $1,000 |
|---|---|---|
| **Carry:** Alice pays on the boosted part, every second, in shares | T-bill + 2% ≈ **6% a year** | ≈ $60 a year |
| **Fees:** 60% of the 0.30% buy and sell fee | Per trade | ≈ $3.60 per round trip |
| **Basket gains** | 0: Hearth is market-neutral | – |

Hearth is a **lender of exposure**. It doesn't care which way the basket goes. It loses only on a jump past the stop (§5.6).

### 5.5 Rules carried over from v0.5 (unchanged)

- **Fills:**
  - Fill at the next update: orders queue and settle at a later price, never one already seen.
  - Orders expire after `maxOrderAge`; cancelling is only allowed after that.
- **Hearth and its withdrawals:**
  - Hearth withdrawals come from **free shares only** (those not backing a live ticket). The rest waits in the queue.
  - Hearth's hedge is fixed per ticket at mint: (B − 1) shares at the series start.
- **The stop and the max:**
  - The stop and the max each need 2 updates in a row.
  - At the max, Hearth pays exactly the max boost.
- **Limits on new tickets:**
  - Mint limit: no new tickets once the live boost is above 4x (after a fall).
  - Gap guard: no new tickets when the distance to the stop is smaller than the basket's biggest recent move.
- **Fees:**
  - Fees only on the holder's own part near the stop, and a fee can never be bigger than what a seller is owed.
- **Pull payments:** `claimable` / `claim()`.
- **Sells are paused only by stale prices.** Every other guardrail pauses buys.

### 5.6 New rules for stocks (from the stocks section v0.1, adapted)

| Rule | Why |
|---|---|
| **Weekend and holiday orders fill at Monday's first price** (buys and sells) | The real market is shut. A Sunday seller who knows bad news would otherwise exit at Friday's price at Hearth's cost |
| **Stop and max paused while the market is shut** | A thin 24/7 token price shouldn't end a series the real market will reprice on Monday |
| **The stop confirms by time while the market is open,** and never carries a half-confirmed stop into a close | Otherwise the holder carries the whole night's gap |
| **No new tickets in the hour before earnings** of any stock over 10% of the basket | Earnings gaps are the main one-jump risk for stocks |
| **Which baskets can be leveraged:** ≥ 5 stocks, none over 25%, no crypto slice, ≥ $50,000 in the basket, ≥ 4 weeks old | Diversified baskets gap less. The crypto slice moves at weekends while the stop is paused |
| **2x only at launch** | Higher boosts come after real data |
| **Any single stock moving > 30% in one update pauses the basket** until a second price agrees | Splits and bad prints |

### 5.7 The jump problem (still open)

A one-update fall past −50% at 2x costs Hearth (the −60% row in §5.3). For stocks, the risky moment is the **Monday open after bad weekend news** or an **earnings gap**. Diversified baskets make a −50% gap very rare. The fixes being discussed are in `docs/OPEN-PROBLEMS.md` §1 (on the main branch):
- a gap reserve funded by a slice of fees;
- an exit notice for Hearth;
- listing rules;
- **Steady 2x** (§6).

### 5.8 Fees for the leverage layer

| | Fee |
|---|---|
| Buy and sell | 0.30%: 60% to Hearth, 40% to the protocol |
| Carry | ≈ T-bill + 2% a year on the boosted part, to Hearth |
| Hedge cost | ≈ 0: Hearth deposits shares in kind |
| Zap (if paying in or out in USDT) | As §3.4 |

---

## 6. Roadmap: Steady 2x (rebalanced leverage)

Classic 2x lets leverage drift (1.5x at the max, 4.2x near the stop). **Steady 2x** sells shares on the way down to stay near 2x, and buys them back on the way up with that cash, **never with new Hearth money**.

- **Band:** rebalance when leverage leaves 1.6x–2.5x.
- **Down, above 2.5x:** sell some shares to cash, held in the box.
- **Up, below 1.6x:** buy shares back, but only with that spare cash. When there's none left, it drifts like Classic.
- **Hearth never adds money.** Bob stays at $1,000 throughout.

Alice puts in $1,000, and the basket moves 10% a step (the trade-offs were worked through in the design discussion):

| | Classic 2x | Steady 2x (both ways) |
|---|---|---|
| After 4 falls (basket 0.66) | $312, at 4.2x | $384, at 2x |
| **Path A:** a 5th fall (0.59) | **Stopped at $181** | $307, still alive |
| **Path B:** instead, 4 rises back to 1.00 | **$1,000** | $819 |
| A jump that hurts Hearth | > 20% near the stop | > 40% |

Steady protects in crashes and costs Alice on dip-and-recover. Offer both, and let buyers choose. Hearth is hedged either way. **This waits for an on-chain price and swap-depth data.**

---

## 7. Roadmap: Ember (the bold pool)

**Off at launch.** Ember takes the other side of holders' boost without a hedge. On stock baskets it loses on average, because stocks rise: −11.5¢ per $1 ticket a year on the S&P at 2x, −33¢ on AI-heavy baskets (stocks section v0.1 §7). It only turns on once these guardrails are built and a capped pilot shows it's fair.

**Guardrails already designed (from v0.5 and the open problems):**

| Guardrail | Rule |
|---|---|
| Coverage per pool | Ember locks its share of the max boost per ticket, in cash, before a ticket can mint |
| Fixed split at mint | Each ticket's Hearth/Ember split is set when minted |
| Free-capital withdrawals | Only cash not backing a live ticket can leave. The rest queues |
| Fill at the next update | No buying or LPing on a price already seen |
| Per-basket Ember cap | Ember backs at most a set share of each basket's tickets (e.g. 30%); Hearth takes the rest |
| Short-hold fee | A higher sell fee within minutes of buying (e.g. +0.5% within 10 minutes), to Ember. Stops pure flipping |
| Funding-like carry | Rises when Ember is mostly locked or losing (e.g. 4% a year base, 8% at 80% locked) |
| Gap protection | A gap holdback on LP exits, an exit notice, or a gap reserve (open problems §1) |
| Capacity cap | Ember's total size per basket is capped, so it's a side bet, not the main counterparty |

**Turn-on criteria (proposed):**
- a pilot of Hearth-only leverage with no unpaid holder;
- flipper data from real buyers;
- the jump fix chosen.

---

## 8. Contracts

| Contract | Layer | Based on |
|---|---|---|
| `BasketFactory` | 1 | New: allowlist, rules (§3.1), the near-clone check, deploys `BasketVault` clones |
| `BasketVault` | 1 | New: an ERC-20 share; Rider/Rebalancer; in-kind mint and redeem; paused-token handling |
| `ZapRouter` | 1 | New: USDT in/out through allowlisted routers; mints on what was actually bought; protocol and creator fees |
| `PriceAdapter` | 1–3 | New: one interface over the on-chain price (staleness, deviation vs a second source, pause). Same shape as `IPriceFeed` in `contracts/interfaces` |
| `FundingLeague` | 2 | `LeagueEscrow.sol` from the ETF repo (conservation, void, keeper trust model) + a funding index per basket + next-round activation |
| `league.ts` engine | 2 | The ETF repo engine as is, with the pot = funding |
| `BoostMarket` | 3 | `AsphodelLiquidVMarket.sol` on main, with the LiquidV vault swapped for `BasketVault` shares, Ember removed, no cash lock, settlement in shares, and the stock hours from `MarketCalendar.sol` |

**Parked, not deleted:** the LiquidV build (`contracts/liquidv/`) and the Hyperliquid stocks build (`AsphodelMarket.sol`, `hypercore/`) on main.

**Invariants to fuzz** (as before):
- Basket: shares × holdings always add up, and a redemption never pays more than the basket's share.
- League: conservation, and stakes always returned.
- Boost: Alice's base + Hearth's shares ≥ what's owed between the stop and the max; Hearth's free shares never include shares backing a ticket.

---

## 9. Must check before building (open questions)

1. **An on-chain price for bStocks and Ondo tokens on BNB Chain:** Chainlink, the issuer's own oracle, or a DEX average? This blocks the Rebalancer, League v2 and leverage, but not Rider baskets or League v1.
2. **bStock dividends:** how they reach holders (price drop, airdrop, ratio?). This decides whether a basket's value includes them.
3. **Issuer controls:** can bStocks and Ondo pause or blocklist a contract like `BasketVault`? What happens to tokens inside?
4. **Swap depth at size:** price impact for $1k–$100k zaps and rebalances (measured so far only at $5–10).
5. **Who may hold them:** stock tokens are restricted for some users (e.g. US persons). Does that pass through to basket shares?
6. **Legal:**
   - The League is a contest with a house take, so present it as a skill contest and get advice before real launch.
   - Leveraged exposure to stocks may be regulated as a derivative in some regions.
7. **League numbers:** funding rate (0.02% a day?), minimum stake, creator share and season prizes.
8. **Steady 2x band** (1.6x–2.5x?) and whether to offer it at launch.

---

## 10. Build plan

| Step | What | Done when |
|---|---|---|
| 1 | `BasketFactory` + `BasketVault` (Rider) + in-kind mint/redeem | Fuzz-tested; a real 3-stock basket made from bStocks on a BNB Chain fork |
| 2 | `ZapRouter` | A real $10 zap in and out on mainnet with a creator fee |
| 3 | `FundingLeague` + engine (keeper settlement) | A live round with ≥ 4 baskets settles, verifies and pays |
| 4 | Price check (§9.1), then Rebalancer | Rebalance on a fork within the 0.5% check |
| 5 | `BoostMarket` (Hearth only, Classic 2x) | All v0.5 invariants + share settlement; a capped pilot |
| 6 | Steady 2x, then Ember | Turn-on criteria in §6 and §7 |

The UI comes from the user and wires onto steps 1–3 first.
