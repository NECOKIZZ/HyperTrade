// The keeper: one loop that keeps every Series updated.
//
//   NETWORK=elysiumTestnet KEEPER_KEY=0x... npm run keeper
//
// Each round, for each Series:
//   1. reads the real LiquidV vault on HyperEVM (NAV per share, idle cash, supply, stale, paused);
//   2. testnet: relays that to the Series' MirrorVault, so tickets follow the real trader;
//      FEED=core: relays idle cash and supply to HyperCoreNavFeed (the HyperCore part is read live by
//      Elysium's precompile, so it needs no relay);
//   3. calls poke() on the market: settles the orders waiting for this update, checks the stop and Crown.
// poke() is open to anyone; this is just the bot that does it every round.

import { createPublicClient, createWalletClient, http, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { network, hyperEvm, liquidVVaultAbi } from "./lib/chains.ts";
import { artifact, readDeployment } from "./lib/artifacts.ts";

const { name: net, chain } = network();
const key = (process.env.KEEPER_KEY ?? process.env.DEPLOYER_KEY) as Hex | undefined;
if (!key) throw new Error("set KEEPER_KEY");
const account = privateKeyToAccount(key);
const pub = createPublicClient({ chain, transport: http() });
const wallet = createWalletClient({ chain, transport: http(), account });
const hl = createPublicClient({ chain: hyperEvm, transport: http() });
const dep = readDeployment(net);

const ROUND_MS = Number(process.env.ROUND_MS ?? 1000);
const RELAY_EVERY_MS = Number(process.env.RELAY_EVERY_MS ?? 30_000); // relay at least this often, even if unchanged
const WAD = 10n ** 18n;

const mirror = artifact("elysium/MirrorVault.sol", "MirrorVault");
const coreFeed = artifact("elysium/HyperCoreNavFeed.sol", "HyperCoreNavFeed");
const market = artifact("liquidv/AsphodelLiquidVMarket.sol", "AsphodelLiquidVMarket");

type Real = { pps: bigint; idle: bigint; total: bigint; supply: bigint; stale: boolean; paused: boolean };

async function readReal(vault: Address): Promise<Real> {
  const call = (functionName: string, args: unknown[] = []) =>
    hl.readContract({ address: vault, abi: liquidVVaultAbi, functionName: functionName as never, args: args as never });
  const [pps6, idle, total, supply, stale, paused] = await Promise.all([
    call("convertToAssets", [WAD]),
    call("availableIdle"),
    call("totalAssets"),
    call("totalSupply"),
    call("stale"),
    call("paused"),
  ]);
  return {
    pps: (pps6 as bigint) * 10n ** 12n,
    idle: idle as bigint,
    total: total as bigint,
    supply: supply as bigint,
    stale: stale as boolean,
    paused: paused as boolean,
  };
}

const last = new Map<string, { pps: bigint; at: number }>();

async function round() {
  for (const s of dep.series) {
    try {
      const real = await readReal(s.sourceVault as Address);
      const prev = last.get(s.key);
      const due = !prev || prev.pps !== real.pps || Date.now() - prev.at > RELAY_EVERY_MS;

      if (s.feedMode === "core") {
        if (due) {
          await write(s.feed, coreFeed.abi, "setBook", [real.idle, real.supply]);
          last.set(s.key, { pps: real.pps, at: Date.now() });
        }
      } else if (dep.usdcIsTest && due) {
        // The real vault keeps part of its money as idle cash; give the mirror the same share of its own
        // assets, so big testnet exits queue the way real ones do.
        const mirrorAssets = (await pub.readContract({ address: s.vault as Address, abi: mirror.abi, functionName: "totalAssets" })) as bigint;
        const idle = real.total > 0n ? (mirrorAssets * real.idle) / real.total : 0n;
        await write(s.vault, mirror.abi, "relay", [real.pps, real.stale, real.paused, idle]);
        last.set(s.key, { pps: real.pps, at: Date.now() });
        console.log(`${s.key}: relayed $${(Number(real.pps) / 1e18).toFixed(6)} per share${real.stale ? " (stale)" : ""}${real.paused ? " (paused)" : ""}`);
      }

      await write(s.market, market.abi, "poke", []);
    } catch (e) {
      const msg = (e as Error).message.split("\n")[0];
      if (!msg.includes("AlreadyPoked")) console.error(`${s.key}: ${msg}`);
    }
  }
}

async function write(address: string, abi: typeof market.abi, functionName: string, args: unknown[]) {
  const hash = await wallet.writeContract({ address: address as Address, abi, functionName, args });
  await pub.waitForTransactionReceipt({ hash });
}

console.log(`keeper on ${chain.name} as ${account.address}: ${dep.series.map((s) => s.key).join(", ")}`);
for (;;) {
  const t = Date.now();
  await round();
  await new Promise((r) => setTimeout(r, Math.max(0, ROUND_MS - (Date.now() - t))));
}
