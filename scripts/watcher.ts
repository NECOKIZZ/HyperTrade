// The tracking watcher: how closely does a LiquidV token follow its trader?
//
//   npm run watcher            (serves http://localhost:8787/api/tracking?vault=0x...)
//
// Every SAMPLE_MS it reads, for each listed trader:
//   - the trader's Hyperliquid account: positions on every dex the vault trades, account value;
//   - the vault's own Hyperliquid account (same address as the vault): positions, account value;
//   - the vault on HyperEVM: NAV per share, idle cash, supply (LiquidV's own numbers);
//   - mark prices (what Hyperliquid values accounts at).
// and computes, with LiquidV's published rule (the vault holds the trader's positions scaled 1 : N):
//   ratio      1/N, measured: the vault's position size / the trader's, over the markets they hold
//   expected   the NAV per share the vault WOULD have if it had held exactly ratio x the trader's
//              positions since the first sample (marked to the same mark prices)
//   deviation  actual NAV / expected - 1, in basis points: fees, funding, late fills, missed markets
//   match      per market: the vault's size / (ratio x the trader's size)
// Points are appended to data/tracking/<vault>.jsonl and served to the app.

import { createServer } from "node:http";
import { appendFileSync, mkdirSync, readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { createPublicClient, http, type Address } from "viem";
import { hyperEvm, HL_API, TRADERS, liquidVVaultAbi } from "./lib/chains.ts";
import { ROOT } from "./lib/artifacts.ts";

const SAMPLE_MS = Number(process.env.SAMPLE_MS ?? 10_000);
const PORT = Number(process.env.PORT ?? 8787);
const KEEP = Number(process.env.KEEP_POINTS ?? 8640); // a day at 10 s
const DIR = join(ROOT, "data", "tracking");
mkdirSync(DIR, { recursive: true });

const hl = createPublicClient({ chain: hyperEvm, transport: http() });
const WAD = 10n ** 18n;

async function info<T>(body: object): Promise<T> {
  const r = await fetch(HL_API, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  if (!r.ok) throw new Error(`hyperliquid ${r.status}`);
  return r.json() as Promise<T>;
}

type Clearinghouse = {
  marginSummary: { accountValue: string; totalNtlPos: string };
  assetPositions: { position: { coin: string; szi: string; positionValue: string; entryPx: string; liquidationPx: string | null; leverage: { type: string; value: number } } }[];
};

type Position = { coin: string; szi: number; value: number; entryPx: number; liqPx: number | null; leverage: string };
type Account = { value: number; positions: Position[] };

/** Perp dex names by index (0 = the main dex, ""). */
let dexNames: string[] = [""];
async function loadDexNames() {
  const list = await info<({ name: string } | null)[]>({ type: "perpDexs" });
  dexNames = list.map((d) => (d ? d.name : ""));
}

async function account(user: string, dexes: number[]): Promise<Account> {
  const out: Account = { value: 0, positions: [] };
  for (const i of dexes) {
    const ch = await info<Clearinghouse>({ type: "clearinghouseState", user, dex: dexNames[i] ?? "" });
    out.value += Number(ch.marginSummary.accountValue);
    for (const { position: p } of ch.assetPositions) {
      out.positions.push({
        coin: p.coin,
        szi: Number(p.szi),
        value: Number(p.positionValue),
        entryPx: Number(p.entryPx),
        liqPx: p.liquidationPx ? Number(p.liquidationPx) : null,
        leverage: `${p.leverage.value}x ${p.leverage.type}`,
      });
    }
  }
  return out;
}

/** Mark prices: what Hyperliquid values accounts (and so LiquidV's NAV) at. */
async function marks(dexes: number[]): Promise<Record<string, number>> {
  const out: Record<string, number> = {};
  for (const i of dexes) {
    const [meta, ctxs] = await info<[{ universe: { name: string }[] }, { markPx: string }[]]>({
      type: "metaAndAssetCtxs",
      dex: dexNames[i] ?? "",
    });
    meta.universe.forEach((u, j) => {
      if (ctxs[j]?.markPx) out[u.name] = Number(ctxs[j].markPx);
    });
  }
  return out;
}

export type Point = {
  t: number;
  nav: number; //          actual NAV per share (LiquidV's convertToAssets)
  expected: number; //     NAV per share if the vault held exactly ratio x the trader's book
  devBps: number; //       nav / expected - 1
  ratio: number | null; // vault size / trader size
  traderValue: number;
  vaultCore: number;
  idle: number;
  supply: number;
  traderLev: number; //    trader's real exposure: positions / account value
  vaultLev: number; //     the token's real exposure: vault positions / everything the vault holds
};

type State = {
  key: string;
  vault: Address;
  trader: string;
  name: string;
  dexes: number[];
  points: Point[];
  prev?: { mids: Record<string, number>; trader: Account; ratio: number | null; supply: number };
  latest?: { trader: Account; vault: Account; mids: Record<string, number>; ratio: number | null; at: number; stale: boolean; paused: boolean };
};

const states: State[] = Object.entries(TRADERS).map(([key, t]) => {
  const file = join(DIR, `${t.vault.toLowerCase()}.jsonl`);
  const points: Point[] = existsSync(file)
    ? readFileSync(file, "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l)).slice(-KEEP)
    : [];
  return { key, vault: t.vault as Address, trader: t.trader, name: t.name, dexes: [0], points };
});

function notional(a: Account, px: Record<string, number>) {
  return a.positions.reduce((s, p) => s + Math.abs(p.szi) * (px[p.coin] ?? 0), 0);
}

/** 1/N: the vault's total size over the trader's, on the markets both hold. */
function measureRatio(trader: Account, vault: Account, px: Record<string, number>): number | null {
  let t = 0;
  let v = 0;
  for (const vp of vault.positions) {
    const tp = trader.positions.find((p) => p.coin === vp.coin);
    if (!tp) continue;
    t += Math.abs(tp.szi) * (px[vp.coin] ?? 0);
    v += Math.abs(vp.szi) * (px[vp.coin] ?? 0);
  }
  return t > 0 ? v / t : null;
}

async function sample(s: State) {
  const read = (fn: string, args: unknown[] = []) =>
    hl.readContract({ address: s.vault, abi: liquidVVaultAbi, functionName: fn as never, args: args as never });
  const [pps6, idle6, supplyW, dexes, stale, paused] = await Promise.all([
    read("convertToAssets", [WAD]),
    read("availableIdle"),
    read("totalSupply"),
    read("perpDexes"),
    read("stale"),
    read("paused"),
  ]);
  s.dexes = (dexes as number[]).map(Number);
  const [trader, vault, px] = await Promise.all([account(s.trader, s.dexes), account(s.vault, s.dexes), marks(s.dexes)]);
  const nav = Number(pps6 as bigint) / 1e6;
  const idle = Number(idle6 as bigint) / 1e6;
  const supply = Number(supplyW as bigint) / 1e18;
  const ratio = measureRatio(trader, vault, px);

  // expected NAV: carry the last expected value forward by what ratio x the trader's book made
  const lastPoint = s.points.at(-1);
  let expected = nav;
  if (lastPoint && s.prev && s.prev.supply > 0 && t0Gap(lastPoint)) {
    let pnl = 0;
    for (const p of s.prev.trader.positions) {
      const a = s.prev.mids[p.coin];
      const b = px[p.coin];
      if (a && b) pnl += p.szi * (s.prev.ratio ?? 0) * (b - a);
    }
    expected = lastPoint.expected + pnl / s.prev.supply;
  }
  const total = idle + vault.value;
  const point: Point = {
    t: Date.now(),
    nav,
    expected,
    devBps: expected > 0 ? (nav / expected - 1) * 1e4 : 0,
    ratio,
    traderValue: trader.value,
    vaultCore: vault.value,
    idle,
    supply,
    traderLev: trader.value > 0 ? notional(trader, px) / trader.value : 0,
    vaultLev: total > 0 ? notional(vault, px) / total : 0,
  };
  s.points.push(point);
  if (s.points.length > KEEP) s.points.shift();
  appendFileSync(join(DIR, `${s.vault.toLowerCase()}.jsonl`), JSON.stringify(point) + "\n");
  s.prev = { mids: px, trader, ratio, supply };
  s.latest = { trader, vault, mids: px, ratio, at: point.t, stale: stale as boolean, paused: paused as boolean };
}

/** A gap of more than 5 samples (the watcher was down) restarts the expected line at the actual NAV. */
function t0Gap(p: Point) {
  return Date.now() - p.t < SAMPLE_MS * 5;
}

function view(s: State, since = 0) {
  const l = s.latest;
  const coins = new Set([...(l?.trader.positions ?? []), ...(l?.vault.positions ?? [])].map((p) => p.coin));
  const positions = [...coins].map((coin) => {
    const t = l?.trader.positions.find((p) => p.coin === coin);
    const v = l?.vault.positions.find((p) => p.coin === coin);
    const want = t && l?.ratio ? t.szi * l.ratio : 0;
    return {
      coin,
      mid: l?.mids[coin] ?? null,
      trader: t ?? null,
      vault: v ?? null,
      expectedVaultSzi: want,
      match: want ? (v?.szi ?? 0) / want : null,
    };
  });
  return {
    key: s.key,
    name: s.name,
    vault: s.vault,
    trader: s.trader,
    dexes: s.dexes.map((i) => dexNames[i] || "main"),
    updatedAt: l?.at ?? null,
    stale: l?.stale ?? null,
    paused: l?.paused ?? null,
    ratio: l?.ratio ?? null,
    positions,
    points: s.points.filter((p) => p.t >= since),
  };
}

createServer((req, res) => {
  const u = new URL(req.url ?? "/", "http://x");
  res.setHeader("access-control-allow-origin", "*");
  res.setHeader("content-type", "application/json");
  if (u.pathname === "/api/health") return res.end(JSON.stringify({ ok: true, traders: states.map((s) => s.key) }));
  if (u.pathname === "/api/tracking") {
    const v = (u.searchParams.get("vault") ?? "").toLowerCase();
    const s = states.find((x) => x.vault.toLowerCase() === v || x.key === u.searchParams.get("key")) ?? (v ? undefined : states[0]);
    if (!s) {
      res.statusCode = 404;
      return res.end(JSON.stringify({ error: "unknown vault" }));
    }
    return res.end(JSON.stringify(view(s, Number(u.searchParams.get("since") ?? 0))));
  }
  res.statusCode = 404;
  res.end(JSON.stringify({ error: "not found" }));
}).listen(PORT, () => console.log(`watcher on http://localhost:${PORT}/api/tracking`));

await loadDexNames();
for (;;) {
  const t = Date.now();
  for (const s of states) {
    try {
      await sample(s);
      const p = s.points.at(-1)!;
      console.log(
        `${s.key}: nav $${p.nav.toFixed(6)} expected $${p.expected.toFixed(6)} (${p.devBps >= 0 ? "+" : ""}${p.devBps.toFixed(1)} bps), ` +
          `ratio 1:${p.ratio ? Math.round(1 / p.ratio) : "-"}, trader ${p.traderLev.toFixed(2)}x, token ${p.vaultLev.toFixed(2)}x`,
      );
    } catch (e) {
      console.error(`${s.key}: ${(e as Error).message.split("\n")[0]}`);
    }
  }
  await new Promise((r) => setTimeout(r, Math.max(0, SAMPLE_MS - (Date.now() - t))));
}
