# Asphodel contracts

Two isolated builds of Asphodel's boosted token, side by side. They share only the price-feed interface;
neither depends on the other.

| Build | Folder | Base (the real token) | Spec |
|---|---|---|---|
| **v0.5 LiquidV (the original)** | `contracts/liquidv/` | A LiquidV trader token (`$vTRADER`) | `ASPHODEL-SPEC-v0.5.md` |
| Stocks on Hyperliquid | `contracts/` (top level) | A Hyperliquid stock market (`xyz:SP500`, ...) | `ASPHODEL-STOCKS-v0.1.md` |

## v0.5 LiquidV build

Example: $100 of `$vWHALE` 2x buys 100 tickets at $1.00, and the $100 really buys `$vWHALE` from LiquidV.
0xWhale's token rises 10%: the ticket is $1.20 and Alice sells for $120 (her own +$10, plus +$10 from the
Meadow). If it falls 37.5% for 2 updates, she's stopped out with $25.

**How LiquidV works on-chain.** Checked against the real deployed vault code on a fork of HyperEVM
(`test/fork/`), with vANSEM's vault, 2026-11-22:

- A trader's vault is an ERC-4626 contract whose **share is the trader token** (`$vANSEM` is vault
  `0xC7F1…Ce91`, symbol `vb2b7e6` after Ansem's wallet `0xb2b7e6…`).
- **Buy** = `deposit(usdc, receiver, minShares)`: 1% fee ($10 in -> shares worth $9.90).
- **Sell** = `redeem(shares, receiver, owner, minAssets)`: 0.3% fee, instant, but **only up to the idle
  cash** the vault keeps on HyperEVM. vANSEM held $187.25: $160.14 working on its Hyperliquid trading
  account and $27.10 idle. Selling more than the idle cash reverts.
- **Bigger exits** = `requestRedeem(...)`: the shares wait in a queue. Anyone can call
  `processRedemptions(n)`; it pays waiting requests in order once LiquidV's keeper has brought cash back
  from Hyperliquid, straight to the receiver, **at the price when processed** (a $490 quote paid $444.81
  after a 10% fall). vANSEM's queue had been used 4 times, all paid.
- **The value is live**: `totalAssets()` = idle cash + the trading account read through HyperCore's
  precompiles; it matched Hyperliquid's live account value to the cent.
- **Stale** (anyone can flag it after the keeper misses its 1-hour heartbeat) and **paused** (LiquidV's
  guardian) **only block deposits**: redeems still work and the value is still live.
- **Capacity**: deposits are capped at $5,000 per vault and at the trader's own account size.

What the market does with that: new tickets are refused while LiquidV is stale or paused, but sales,
stops and Crowns go on. A stop or Crown redeems what it can instantly, then puts the rest (with Hearth's
hedge) in LiquidV's queue and processes the queue on each update until it's paid, then settles on what
the base really redeemed for. A holder's sale bigger than LiquidV's idle cash waits until there is cash.

| File | What it does |
|---|---|
| `contracts/liquidv/AsphodelLiquidVMarket.sol` | One Series of one boosted trader token, per spec v0.5: price `1 + B(x-1)` from a $1 start with one zero at launch, LPs' part capped at MAXB; orders fill at the **next** update at the vault's live NAV; stop $0.25 on 2 updates, holder keeps what's left at the real redemption price; Crown on 2 updates, Meadow pays exactly MAXB and holder keeps the real token's value; per-pool coverage after the hedge is paid for (Ember: its share of MAXB in cash; Hearth: its share of MAXB in cash **and** its hedge); hedge fee; LiquidV fees only on the holder's own share; sellers get the real redemption; fixed Hearth/Ember split; LP withdrawals from free capital only; mint limit; gap guard; carry. When LiquidV lacks idle cash, sales wait and a stop/Crown stays ENDING until the base is redeemed, then settles on what it really redeemed for |
| `contracts/liquidv/LiquidVNavFeed.sol` | NAV per `$vTRADER` share from the vault itself (`convertToAssets`), refused while the vault is stale, paused or not activated |
| `contracts/liquidv/ILiquidVVault.sol` | LiquidV's vault interface, from the deployed implementation's function selectors |
| `contracts/mocks/MockLiquidVVault.sol` | Test vault: settable NAV, 1% / 0.3% fees, idle cash, capacity, stale/paused |

**Fork tests** (real LiquidV code; off unless switched on):

```bash
LIQUIDV_FORK=true LIQUIDV_CORE_USD6=<vANSEM coreAssets() now> npx hardhat test solidity test/fork
```

They check every point above, then run this market against the real vault: $100 -> 98.23 tickets ->
Ansem +10% -> Alice receives $117.25 in USDC ($120 less fees); and a stop that goes through LiquidV's
real queue and settles at $0.237 a ticket. HyperCore isn't on a fork, so its three reads (account
value, spot balance, lending reserve) are stood in for at their live values.

**Open problems** (documented, not built): `docs/OPEN-PROBLEMS.md`: flash dumps and fast LP exits; flippers picking off Ember.

**v0.5 still to do:** holder sales bigger than LiquidV's idle cash could also use the queue (today they
wait); a keeper that pokes every block;
a factory for the next Series after a Crown or stop; an LP share token; the gap holdback (spec §21, #11);
a dormancy rule for quiet traders; an audit.

## Stocks build

Asphodel's boosted token on Hyperliquid's own stock markets (HIP-3 perps such as `xyz:SP500`,
`xyz:XYZ100`, `xyz:NVDA`). A buyer's money buys the real asset (the base); the Meadow
(Hearth + Ember LP pools) backs the boost. Rules follow `ASPHODEL-SPEC-v0.5.md` and
`ASPHODEL-STOCKS-v0.1.md`.

Example: $100 of S&P 500 2x buys 100 tickets at $1.00. The S&P rises 10%: the ticket is $1.20,
Alice sells for $120 (her own +$10, plus +$10 from the Meadow).

## What's built

| File | What it does |
|---|---|
| `contracts/AsphodelMarket.sol` | One Series of one boosted token (ERC-20 tickets). Pricing (`1 + B(x-1)`, LPs' part capped at MAXB), buy/sell orders that fill at the **next** price update, stop ($0.25, 2 updates >= 60 s apart), Crown (Meadow pays exactly MAXB, holder keeps the real base's value), Hearth/Ember pools with per-pool coverage, LP deposits/withdrawals from free capital only, Hearth's hedge counted as collateral, fees only on the holder's own share, mint limit, gap guard, carry, weekend rules |
| `contracts/hypercore/HyperCorePerpFeed.sol` | Reads a perp's oracle and mark price from HyperCore's precompiles (`0x…0807`, `0x…0806`); refuses the price when the mark has drifted from the oracle |
| `contracts/MarketCalendar.sol` | US market hours: weekend closure (Fri 20:00 → Mon 14:30 UTC) plus owner-added holidays. While shut: no new tickets, no stop/Crown, sales pay the boost on the 1-hour average |
| `contracts/interfaces/IBase.sol` | What the market needs from the base: buy/sell units at the live price |
| `contracts/mocks/` | Test USDC, price feed, base, and a fake HyperCore precompile |
| `markets.json` | Hyperliquid stock markets and their asset ids |

## What's not built yet

1. **The real base on HyperCore.** `IBase` is synchronous (buy now, get units now). On Hyperliquid a
   contract opens a perp position by sending an order through CoreWriter (`0x3333…3333`), and it fills
   on HyperCore *after* the EVM block. The next step is an async base: each update sends one net order
   for the batch, and the following update books the actual fill (`position` precompile) before
   settling. Fill-at-next-update already fits that shape.
2. **Testnet checks:** that the price precompiles take HIP-3 asset ids (`110052` for `xyz:SP500`),
   price decimals per market, and each market's split/halt rules.
3. **A keeper** that calls `poke()` every block. Without one, a buyer could wait for a good price and
   poke it themselves within `maxOrderAge` blocks, so keep `maxOrderAge` small (a few blocks) and run
   the keeper.
4. **Factory / next Series** after a Crown or stop, an LP share token, and the gap holdback (spec §21, #11).
5. **An audit.** This is a first build.

## Run

Needs Node 22+. Foundry's installer isn't required: Hardhat 3 runs the Solidity tests.

```bash
npm install
```

```bash
npx hardhat test solidity
```

40 tests. v0.5 LiquidV (18): the worked example up and down, LiquidV fees and the hedge fee, fill at
the next update at live NAV, stale vault, Crown, stop, one dip doesn't stop, a stop that waits for
LiquidV's idle cash and settles on the real redemption, a sale that waits for idle cash, Hearth needing
coverage and hedge, Ember coverage per pool, LiquidV full, LP withdrawals, mint limit, gap guard, and a
120-step random walk with fees and thin idle cash checking solvency every step.

Stocks (22): the spec's worked example (up and down), fill at the next update, stale feed, cancel only
after `maxOrderAge`, Crown on 2 updates, one spike doesn't Crown, stop on 2 updates, a gap through
the stop, one dip doesn't stop, weekend (no mints, no stop; stop fires on Monday), weekend sale on the
hour average, coverage refusal, Hearth's hedge as collateral, LP withdrawals limited to free money,
fees never make a sale negative, mint limit after a big fall, a 120-step random walk that checks
solvency every step, the HyperCore price reader and the calendar.

`lib/forge-std` is a clone of foundry-rs/forge-std (test helpers only).
