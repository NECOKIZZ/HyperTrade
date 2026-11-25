import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { Abi, Hex } from "viem";

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

/** A compiled contract from `npx hardhat build`. */
export function artifact(source: string, name: string): { abi: Abi; bytecode: Hex } {
  const p = join(ROOT, "artifacts", "contracts", source, `${name}.json`);
  if (!existsSync(p)) throw new Error(`missing ${p}: run \`npx hardhat build\` first`);
  const a = JSON.parse(readFileSync(p, "utf8"));
  return { abi: a.abi, bytecode: a.bytecode };
}

export type SeriesDeployment = {
  key: string; //            "vANSEM-2x"
  name: string; //           "vANSEM 2x"
  symbol: string;
  trader: string; //         Hyperliquid wallet being mirrored
  traderName: string;
  sourceVault: string; //    the real LiquidV vault on HyperEVM
  market: string;
  vault: string; //          the vault this Series holds (MirrorVault on testnet)
  feed: string;
  feedMode: "vault" | "core"; // LiquidVNavFeed today, HyperCoreNavFeed once Elysium's precompile ships
  boost: number;
  maxPrice: number;
  stopPrice: number;
  hearthShare: number;
};

export type Deployment = {
  network: string;
  chainId: number;
  usdc: string;
  usdcIsTest: boolean; //    testnet USDC anyone can mint
  keeper: string;
  deployedAt: string;
  series: SeriesDeployment[];
};

export function deploymentPath(network: string) {
  return join(ROOT, "deployments", `${network}.json`);
}

export function readDeployment(network: string): Deployment {
  return JSON.parse(readFileSync(deploymentPath(network), "utf8"));
}

export function writeDeployment(d: Deployment) {
  mkdirSync(join(ROOT, "deployments"), { recursive: true });
  writeFileSync(deploymentPath(d.network), JSON.stringify(d, null, 2) + "\n");
  // the app reads every network's file
  const appDir = join(ROOT, "app", "src", "deployments");
  mkdirSync(appDir, { recursive: true });
  writeFileSync(join(appDir, `${d.network}.json`), JSON.stringify(d, null, 2) + "\n");
}
