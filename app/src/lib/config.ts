import { createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";
import { defineChain, parseAbi, type Address } from "viem";

export const elysiumTestnet = defineChain({
  id: 99801,
  name: "Elysium Testnet",
  nativeCurrency: { name: "HYPE", symbol: "HYPE", decimals: 18 },
  rpcUrls: { default: { http: [import.meta.env.VITE_ELYSIUM_TESTNET_RPC ?? "https://testnet-rpc.elysium.kinetiq.xyz"] } },
  blockExplorers: { default: { name: "Elysium Explorer", url: "https://elysium.kinetiq.xyz/testnet-explorer" } },
  testnet: true,
});

export const elysium = defineChain({
  id: 99901,
  name: "Elysium",
  nativeCurrency: { name: "HYPE", symbol: "HYPE", decimals: 18 },
  rpcUrls: { default: { http: [import.meta.env.VITE_ELYSIUM_RPC ?? "https://rpc.elysium.kinetiq.xyz"] } },
});

export const localChain = defineChain({
  id: 31337,
  name: "Local",
  nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["http://127.0.0.1:8545"] } },
  testnet: true,
});

export const wagmiConfig = createConfig({
  chains: [elysiumTestnet, elysium, localChain],
  connectors: [injected()],
  transports: {
    [elysiumTestnet.id]: http(),
    [elysium.id]: http(),
    [localChain.id]: http(),
  },
});

export const WATCHER_URL: string = import.meta.env.VITE_WATCHER_URL ?? "http://localhost:8787";

// ---------------------------------------------------------------- deployments
export type Series = {
  key: string;
  name: string;
  symbol: string;
  trader: Address;
  traderName: string;
  sourceVault: Address;
  market: Address;
  vault: Address;
  feed: Address;
  feedMode: "vault" | "core";
  boost: number;
  maxPrice: number;
  stopPrice: number;
  hearthShare: number;
};

export type Deployment = {
  network: string;
  chainId: number;
  usdc: Address;
  usdcIsTest: boolean;
  keeper: Address;
  deployedAt: string;
  series: Series[];
};

const files = import.meta.glob<Deployment>("../deployments/*.json", { eager: true, import: "default" });
const byName: Record<string, Deployment> = {};
for (const d of Object.values(files)) byName[d.network] = d;

export type NetKey = "elysiumTestnet" | "elysium" | "local";

export const NETWORKS: { key: NetKey; label: string; chainId: number }[] = [
  { key: "elysiumTestnet", label: "Elysium Testnet", chainId: elysiumTestnet.id },
  { key: "elysium", label: "Elysium", chainId: elysium.id },
  ...(byName.local && import.meta.env.DEV ? [{ key: "local" as const, label: "Local", chainId: localChain.id }] : []),
];

export function deployment(net: NetKey): Deployment | undefined {
  return byName[net];
}

// ---------------------------------------------------------------- ABIs (the parts the app uses)
export const marketAbi = parseAbi([
  "function price() view returns (uint256)",
  "function x() view returns (uint256)",
  "function nav() view returns (uint256)",
  "function nav0() view returns (uint256)",
  "function status() view returns (uint8)",
  "function maxBoost() view returns (uint256)",
  "function xCrown() view returns (uint256)",
  "function effectiveBoost() view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function claimable(address) view returns (uint256)",
  "function shares(uint256, address) view returns (uint256)",
  "function totalShares(uint256) view returns (uint256)",
  "function equity(uint256) view returns (int256)",
  "function free(uint256) view returns (int256)",
  "function lpValue(uint256, address) view returns (int256)",
  "function pendingOrders() view returns (uint256)",
  "function requestBuy(uint256 usdcIn, uint256 minTickets) returns (uint256)",
  "function requestSell(uint256 tickets, uint256 minUsdc) returns (uint256)",
  "function requestDeposit(bool hearth, uint256 usdcIn) returns (uint256)",
  "function requestWithdraw(bool hearth, uint256 poolShares) returns (uint256)",
  "function redeem(uint256 tickets) returns (uint256)",
  "function claim() returns (uint256)",
]);

export const usdcAbi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address, address) view returns (uint256)",
  "function approve(address, uint256) returns (bool)",
  "function mint(address, uint256)",
]);

export const vaultAbi = parseAbi([
  "function stale() view returns (bool)",
  "function paused() view returns (bool)",
  "function activated() view returns (bool)",
  "function availableIdle() view returns (uint256)",
]);

export const STATUS = ["Live", "Ending", "Crowned", "Stopped"] as const;
