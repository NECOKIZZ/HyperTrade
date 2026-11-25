# Asphodel on Elysium

Elysium is Kinetiq's L2 for Hyperliquid: 100 ms blocks, HYPE gas, settles to HyperEVM. Asphodel launches
on Elysium mainnet the day Elysium's HyperCore read precompile goes live. Until then it runs on Elysium
testnet, following real LiquidV traders.

Sources: https://elysium.kinetiq.xyz/docs (read 2026-11-25), LiquidV's app and docs
(https://app.liquidv.xyz/docs), and live reads of the vANSEM vault on HyperEVM.

## What Elysium gives us, and when

| | Status | What it means for Asphodel |
|---|---|---|
| Chain (99901 mainnet, 99801 testnet) | Live | Contracts deploy unchanged |
| HyperCore **read** precompile: books, prices, balances, positions, depth, slippage | ArbOS upgrade ~4 weeks after mainnet; **address and ABI not published yet** | A vault's HyperCore account read live, ~70 ms HyperCore blocks, 150–350 ms fresh. Every read is stamped with the HyperCore block and time it came from, and fails visibly when stale |
| `ElysiumCoreWriter` (contracts trade on HyperCore in ~100 ms via a trade-only agent) | Same upgrade | Not needed by Asphodel itself; relevant to LiquidV |
| Canonical bridge HyperEVM → Elysium | Live, ~1 minute | |
| Canonical bridge Elysium → HyperEVM | Live, **~5.5 days** (optimistic challenge period) | A Series can't redeem bridged `$vTRADER` back at the vault quickly (see below) |

HyperEVM's own L1Read precompile serves the same kind of data at ~1 s granularity, so the code is
written against one interface that both can implement.

## How the code is laid out for it

```
IPriceFeed  <- what every market reads (unchanged)
 ├─ LiquidVNavFeed     the vault's own convertToAssets()      today: testnet MirrorVault, or a real vault
 └─ HyperCoreNavFeed   LiquidV's formula, the fast part live   the precompile slot
        NAV/share = (idle cash + HyperCore account value) / shares
        └─ IHyperCoreReader
             ├─ HyperEvmCoreReader   HyperEVM L1Read (0x...080F), works today
             └─ ElysiumCoreReader    TO WRITE on the day the precompile ABI is published
```

LiquidV's formula checked live on vANSEM (2026-11-25): `availableIdle` $86.923504 + `coreAssets`
$611.627798 = `totalAssets` $698.551302; `coreAssets` equals Hyperliquid's own account value for the
vault to the cent, across `perpDexes()` = [0, 1] (main and xyz). So the HyperCore account value is the
whole moving part: idle cash and share supply change only when people mint or redeem, and the keeper
relays those (`HyperCoreNavFeed.setBook`).

## Launch day: precompile live → Asphodel live

1. Kinetiq publishes the read precompile's address and encoding.
2. Write `contracts/elysium/ElysiumCoreReader.sol` implementing `IHyperCoreReader.accountValue(user,
   dexes)`: one precompile read per dex for the account value, returning the HyperCore timestamp the
   response is stamped with. ~30 lines, plus a test that etches a mock at the precompile address (as
   `test/Elysium.t.sol` does for HyperEVM's).
3. Check it on Elysium testnet against the real vault: `HyperCoreNavFeed.read()` vs the vault's
   `convertToAssets(1e18)` (the watcher already reads the latter). They should agree within a few basis
   points; the only difference is the relayed idle/supply lag.
4. Deploy with `FEED=core CORE_READER=<adapter>`. The keeper then only relays idle cash and supply;
   prices come live from the precompile.

Everything except step 2 exists and is tested today.

## The open question for mainnet: holding the real token on Elysium

A Series holds the real `$vTRADER` and mints and redeems it at the vault (that is what makes the
ticket honest and lets a stop or Crown settle at the real price). LiquidV's vaults live on **HyperEVM**.
LiquidV's own app (checked 2026-11-25) has Elysium mainnet contracts, but they are **pool seeders**:
trader tokens are bridged to Elysium and seeded into trading pools there, plus a "remote buy" path.

What that means:

- **Bridged tokens + Elysium pools** would make a Series buy and sell through an AMM pool: price can
  drift from NAV, thin pools can be pushed, and every stop sells into the pool. Not acceptable for the
  stop and Crown.
- **Bridging back to redeem** takes ~5.5 days. Not usable for sales or stops.
- **What we need from LiquidV:** a way for an Elysium contract to mint at NAV and redeem at NAV (or
  queue at the real redemption price, as on HyperEVM) with a bounded delay. Their "remote buy" may be
  half of it. Their vaults could also live on Elysium using `ElysiumCoreWriter` once it ships.

That is the integration to agree with LiquidV (and Kinetiq) before mainnet. The market contract talks
to the vault through `ILiquidVVault`, so whatever LiquidV provides plugs in as the `VAULT` at deploy;
`scripts/deploy.ts` refuses a mainnet deploy without it.

## Testnet

Elysium testnet has no LiquidV vaults. Each Series there holds a **MirrorVault**: same surface as a
LiquidV vault (1% mint, 0.3% exit, idle cash, redemption queue), with its NAV per share relayed by the
keeper from the real vault on HyperEVM. So testnet tickets move with the real trader. If the keeper
stops for longer than `maxRelayAge` (120 s), the vault reports no price and nothing fills, rather than
filling at an old number.
