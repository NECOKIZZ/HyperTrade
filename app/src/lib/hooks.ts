import { useEffect, useState } from "react";
import { useAccount, useReadContracts, useSwitchChain, useWriteContract } from "wagmi";
import { waitForTransactionReceipt } from "wagmi/actions";
import { useQueryClient } from "@tanstack/react-query";
import type { Abi, Address } from "viem";
import { marketAbi, usdcAbi, vaultAbi, wagmiConfig, WATCHER_URL, type Deployment, type Series } from "./config";
import { wad, usdc6 } from "./format";

const ZERO = "0x0000000000000000000000000000000000000000" as Address;

/** Everything the pages show about one Series, refreshed every 2 s. */
export function useSeries(d: Deployment | undefined, s: Series | undefined) {
  const { address } = useAccount();
  const me = address ?? ZERO;
  const chainId = d?.chainId;
  const m = { address: s?.market, abi: marketAbi, chainId } as const;
  const { data, refetch } = useReadContracts({
    allowFailure: true,
    query: { enabled: !!s && !!d, refetchInterval: 2000 },
    contracts: [
      { ...m, functionName: "price" },
      { ...m, functionName: "x" },
      { ...m, functionName: "status" },
      { ...m, functionName: "xCrown" },
      { ...m, functionName: "maxBoost" },
      { ...m, functionName: "totalSupply" },
      { ...m, functionName: "balanceOf", args: [me] },
      { ...m, functionName: "claimable", args: [me] },
      { ...m, functionName: "equity", args: [0n] },
      { ...m, functionName: "equity", args: [1n] },
      { ...m, functionName: "free", args: [0n] },
      { ...m, functionName: "free", args: [1n] },
      { ...m, functionName: "totalShares", args: [0n] },
      { ...m, functionName: "totalShares", args: [1n] },
      { ...m, functionName: "shares", args: [0n, me] },
      { ...m, functionName: "shares", args: [1n, me] },
      { ...m, functionName: "lpValue", args: [0n, me] },
      { ...m, functionName: "lpValue", args: [1n, me] },
      { ...m, functionName: "pendingOrders" },
      { address: d?.usdc, abi: usdcAbi, chainId, functionName: "balanceOf", args: [me] },
      { address: d?.usdc, abi: usdcAbi, chainId, functionName: "allowance", args: [me, s?.market ?? ZERO] },
      { address: s?.vault, abi: vaultAbi, chainId, functionName: "stale" },
      { address: s?.vault, abi: vaultAbi, chainId, functionName: "paused" },
      { address: s?.vault, abi: vaultAbi, chainId, functionName: "activated" },
    ],
  });
  const r = (i: number) => data?.[i]?.result as bigint | boolean | number | undefined;
  return {
    refetch,
    loaded: !!data && data[0]?.status === "success",
    price: wad(r(0) as bigint),
    x: wad(r(1) as bigint),
    status: r(2) as number | undefined,
    xCrown: wad(r(3) as bigint),
    maxBoost: wad(r(4) as bigint),
    supply: wad(r(5) as bigint),
    tickets: r(6) as bigint | undefined,
    claimable: wad(r(7) as bigint),
    equity: [wad(r(8) as bigint), wad(r(9) as bigint)],
    free: [wad(r(10) as bigint), wad(r(11) as bigint)],
    totalShares: [r(12) as bigint | undefined, r(13) as bigint | undefined],
    myShares: [r(14) as bigint | undefined, r(15) as bigint | undefined],
    myValue: [wad(r(16) as bigint), wad(r(17) as bigint)],
    pending: r(18) as bigint | undefined,
    usdcBalance: r(19) as bigint | undefined,
    usdcBalanceNum: usdc6(r(19) as bigint),
    allowance: r(20) as bigint | undefined,
    vaultStale: r(21) as boolean | undefined,
    vaultPaused: r(22) as boolean | undefined,
    priceFresh: r(23) as boolean | undefined,
  };
}

/** Sends a transaction on the Series' chain (switching the wallet first), waits for it, refreshes reads. */
export function useTx(chainId: number | undefined) {
  const { chainId: walletChain } = useAccount();
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();
  const qc = useQueryClient();
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function send(label: string, address: Address, abi: Abi, functionName: string, args: unknown[]) {
    if (!chainId) return;
    setBusy(label);
    setError(null);
    try {
      if (walletChain !== chainId) await switchChainAsync({ chainId: chainId as (typeof wagmiConfig)["chains"][number]["id"] });
      const hash = await writeContractAsync({ address, abi, functionName, args, chainId } as never);
      await waitForTransactionReceipt(wagmiConfig, { hash, chainId: chainId as (typeof wagmiConfig)["chains"][number]["id"] });
      await qc.invalidateQueries();
      return true;
    } catch (e) {
      const msg = (e as { shortMessage?: string }).shortMessage ?? (e as Error).message;
      setError(msg.split("\n")[0]);
      return false;
    } finally {
      setBusy(null);
    }
  }

  return { send, busy, error };
}

export type TrackingPoint = {
  t: number;
  nav: number;
  expected: number;
  devBps: number;
  ratio: number | null;
  traderValue: number;
  vaultCore: number;
  idle: number;
  supply: number;
  traderLev: number;
  vaultLev: number;
};

type Pos = { coin: string; szi: number; value: number; entryPx: number; liqPx: number | null; leverage: string };

export type Tracking = {
  key: string;
  name: string;
  vault: string;
  trader: string;
  dexes: string[];
  updatedAt: number | null;
  stale: boolean | null;
  paused: boolean | null;
  ratio: number | null;
  positions: { coin: string; mid: number | null; trader: Pos | null; vault: Pos | null; expectedVaultSzi: number; match: number | null }[];
  points: TrackingPoint[];
};

/** The watcher's view of a trader and their LiquidV token (scripts/watcher.ts). */
export function useTracking(vault: string | undefined) {
  const [data, setData] = useState<Tracking | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    if (!vault) return;
    let stop = false;
    const load = async () => {
      try {
        const r = await fetch(`${WATCHER_URL}/api/tracking?vault=${vault}`);
        if (!r.ok) throw new Error(`watcher ${r.status}`);
        const j = (await r.json()) as Tracking;
        if (!stop) {
          setData(j);
          setError(null);
        }
      } catch {
        if (!stop) setError("Can’t reach the tracking watcher right now. Retrying.");
      }
    };
    load();
    const id = setInterval(load, 10_000);
    return () => {
      stop = true;
      clearInterval(id);
    };
  }, [vault]);
  return { data, error };
}
