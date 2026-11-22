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

**How LiquidV works on-chain** (read from a live vault on HyperEVM, 2026-11-22): each trader's vault is an
ERC-4626 contract whose **share is the trader token** (vault `0x7952…f8` for trader `0x0149…bdb` has the
symbol `v014980`). You buy by depositing USDC (1% fee) and sell by redeeming (0.3% exit fee).
`totalAssets()` = idle USDC + the vault's HyperCore account, and that account part matched Hyperliquid's live
account value to the cent, so the NAV is read live on-chain. Instant redeems only go up to the vault's idle
cash ($14.59 of $91 that day); bigger exits join LiquidV's redemption queue.

| File | What it does |
|---|---|
| `contracts/liquidv/AsphodelLiquidVMarket.sol` | One Series of one boosted trader token, per spec v0.5: price `1 + B(x-1)` from a $1 start with one zero at launch, LPs' part capped at MAXB; orders fill at the **next** update at the vault's live NAV; stop $0.25 on 2 updates, holder keeps what's left at the real redemption price; Crown on 2 updates, Meadow pays exactly MAXB and holder keeps the real token's value; per-pool coverage after the hedge is paid for (Ember: its share of MAXB in cash; Hearth: its share of MAXB in cash **and** its hedge); hedge fee; LiquidV fees only on the holder's own share; sellers get the real redemption; fixed Hearth/Ember split; LP withdrawals from free capital only; mint limit; gap guard; carry. When LiquidV lacks idle cash, sales wait and a stop/Crown stays ENDING until the base is redeemed, then settles on what it really redeemed for |
| `contracts/liquidv/LiquidVNavFeed.sol` | NAV per `$vTRADER` share from the vault itself (`convertToAssets`), refused while the vault is stale, paused or not activated |
| `contracts/liquidv/ILiquidVVault.sol` | LiquidV's vault interface, from the deployed implementation's function selectors |
| `contracts/mocks/MockLiquidVVault.sol` | Test vault: settable NAV, 1% / 0.3% fees, idle cash, capacity, stale/paused |

**v0.5 still to do:** confirm the vault interface with LiquidV (the meaning of the 4th argument of
`deposit`/`redeem`, and `requestRedeem` for exits bigger than idle cash); a keeper that pokes every block;
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
