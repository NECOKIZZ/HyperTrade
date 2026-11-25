import { formatUnits } from "viem";

export const wad = (v: bigint | undefined) => (v === undefined ? undefined : Number(formatUnits(v, 18)));
export const usdc6 = (v: bigint | undefined) => (v === undefined ? undefined : Number(formatUnits(v, 6)));

export function usd(v: number | undefined, digits = 2) {
  if (v === undefined || !Number.isFinite(v)) return "–";
  return v.toLocaleString("en-US", { style: "currency", currency: "USD", minimumFractionDigits: digits, maximumFractionDigits: digits });
}

export function num(v: number | undefined, digits = 2) {
  if (v === undefined || !Number.isFinite(v)) return "–";
  return v.toLocaleString("en-US", { minimumFractionDigits: digits, maximumFractionDigits: digits });
}

export function pct(v: number | undefined, digits = 1) {
  if (v === undefined || !Number.isFinite(v)) return "–";
  return `${v >= 0 ? "+" : ""}${(v * 100).toFixed(digits)}%`;
}

export const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;
