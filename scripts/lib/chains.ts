// Chains and addresses shared by the deploy script, the keeper and the watcher.
// Elysium values are from https://elysium.kinetiq.xyz/docs (connecting, contract addresses, bridging).

import { defineChain } from "viem";

export const elysiumTestnet = defineChain({
  id: 99801,
  name: "Elysium Testnet",
  nativeCurrency: { name: "HYPE", symbol: "HYPE", decimals: 18 },
  rpcUrls: { default: { http: [process.env.ELYSIUM_TESTNET_RPC ?? "https://testnet-rpc.elysium.kinetiq.xyz"] } },
  blockExplorers: { default: { name: "Elysium Explorer", url: "https://elysium.kinetiq.xyz/testnet-explorer" } },
  testnet: true,
});

export const elysium = defineChain({
  id: 99901,
  name: "Elysium",
  nativeCurrency: { name: "HYPE", symbol: "HYPE", decimals: 18 },
  rpcUrls: { default: { http: [process.env.ELYSIUM_RPC ?? "https://rpc.elysium.kinetiq.xyz"] } },
});

export const hyperEvm = defineChain({
  id: 999,
  name: "HyperEVM",
  nativeCurrency: { name: "HYPE", symbol: "HYPE", decimals: 18 },
  rpcUrls: { default: { http: [process.env.HYPEREVM_RPC ?? "https://rpc.hyperliquid.xyz/evm"] } },
});

export const local = defineChain({
  id: 31337,
  name: "Local",
  nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [process.env.LOCAL_RPC ?? "http://127.0.0.1:8545"] } },
});

export const networks = { elysiumTestnet, elysium, local } as const;
export type NetworkName = keyof typeof networks;

export function network(name = process.env.NETWORK ?? "elysiumTestnet") {
  const chain = (networks as Record<string, typeof elysium>)[name];
  if (!chain) throw new Error(`NETWORK must be one of ${Object.keys(networks).join(", ")}`);
  return { name: name as NetworkName, chain };
}

/** Elysium mainnet's canonical USDC (bridged from HyperEVM's 0xb88339CB...). */
export const ELYSIUM_USDC = "0xb47c4C8F73F009CC0C0d3f92B388d13E293F0B65";

/** LiquidV trader vaults we list. The vault's HyperCore account has the vault's own address. */
export const TRADERS = {
  vANSEM: {
    vault: "0xC7F1330ffa5644ED14FBD0ff0efa793669bCCe91",
    trader: "0xB2b7E6563c2EBa9113979AA04aD1b77313701a8c",
    name: "Ansem",
  },
} as const;

export const HL_API = process.env.HL_API ?? "https://api.hyperliquid.xyz/info";

export const liquidVVaultAbi = [
  { type: "function", name: "convertToAssets", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "totalAssets", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "totalSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "availableIdle", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "coreAssets", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "stale", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "paused", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "exitFeeBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "perpDexes", stateMutability: "view", inputs: [], outputs: [{ type: "uint32[]" }] },
] as const;
