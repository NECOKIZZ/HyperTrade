// Deploys one Asphodel Series per listed trader.
//
//   NETWORK=elysiumTestnet DEPLOYER_KEY=0x... npm run deploy
//
// Testnet: a test USDC anyone can mint, a MirrorVault per trader that follows the real LiquidV vault on
// HyperEVM (relayed by the keeper), LiquidVNavFeed, and the market.
// Mainnet: the Series must hold the real trader token. LiquidV's vaults live on HyperEVM; how a contract
// on Elysium mints and redeems them is being agreed with LiquidV (docs/ELYSIUM.md), so mainnet needs
// VAULT=<the ILiquidVVault on Elysium> and refuses to deploy without it.
//
// FEED=core uses HyperCoreNavFeed (the Elysium precompile slot) with CORE_READER=<adapter address>.

import { createPublicClient, createWalletClient, http, parseUnits, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { network, hyperEvm, TRADERS, ELYSIUM_USDC, liquidVVaultAbi } from "./lib/chains.ts";
import { artifact, writeDeployment, type SeriesDeployment } from "./lib/artifacts.ts";

const { name: net, chain } = network();
const key = process.env.DEPLOYER_KEY as Hex | undefined;
if (!key) throw new Error("set DEPLOYER_KEY");
const account = privateKeyToAccount(key);
const pub = createPublicClient({ chain, transport: http() });
const wallet = createWalletClient({ chain, transport: http(), account });
const keeper = (process.env.KEEPER ?? account.address) as Address;
const feedMode = (process.env.FEED ?? "vault") as "vault" | "core";
const testnet = net !== "elysium";

const WAD = 10n ** 18n;
const pct = (x: number) => (BigInt(Math.round(x * 1e6)) * WAD) / 1_000_000n;

// Series settings (spec v0.5): 2x, max ticket $3, stop $0.25, half the boost on Hearth.
const B = Number(process.env.BOOST ?? 2);
const C = Number(process.env.MAX_PRICE ?? 3);
const config = {
  B: pct(B),
  C: pct(C),
  stopPrice: pct(0.25),
  hearthShare: pct(0.5),
  buyFee: pct(0.003),
  sellFee: pct(0.003),
  lpFeeShare: pct(0.6),
  lvMintFee: pct(0.01),
  mintBoostLimit: pct(4),
  gapGuardK: pct(1),
  carryPerSecond: 0n,
  confirmUpdates: 2,
  gapWindow: 32,
  maxBatch: 50,
  maxOrderAge: Number(process.env.MAX_ORDER_AGE ?? 600), // blocks: 600 x 100 ms = 60 s on Elysium
};

async function deploy(source: string, name: string, args: unknown[]): Promise<Address> {
  const a = artifact(source, name);
  const hash = await wallet.deployContract({ abi: a.abi, bytecode: a.bytecode, args });
  const r = await pub.waitForTransactionReceipt({ hash });
  if (!r.contractAddress) throw new Error(`${name} failed`);
  console.log(`${name.padEnd(22)} ${r.contractAddress}`);
  return r.contractAddress;
}

async function send(address: Address, source: string, name: string, fn: string, args: unknown[]) {
  const a = artifact(source, name);
  const hash = await wallet.writeContract({ address, abi: a.abi, functionName: fn, args });
  await pub.waitForTransactionReceipt({ hash });
}

/** The real vault's NAV per share right now (USD, 18 dp), so testnet starts where the trader is. */
async function realPps(vault: Address): Promise<bigint> {
  if (process.env.PPS) return parseUnits(process.env.PPS, 18);
  const hl = createPublicClient({ chain: hyperEvm, transport: http() });
  const usd6 = await hl.readContract({ address: vault, abi: liquidVVaultAbi, functionName: "convertToAssets", args: [WAD] });
  return usd6 * 10n ** 12n;
}

console.log(`deploying to ${chain.name} (${chain.id}) from ${account.address}, keeper ${keeper}`);

let usdc: Address;
if (testnet) {
  usdc = await deploy("mocks/MockUSDC.sol", "MockUSDC", []);
} else {
  usdc = ELYSIUM_USDC;
  if (!process.env.VAULT) {
    throw new Error(
      "mainnet: set VAULT to the LiquidV trader-token vault (or LiquidV's adapter) on Elysium. " +
        "LiquidV's vaults are on HyperEVM; the Elysium route is pending LiquidV (docs/ELYSIUM.md).",
    );
  }
}

const series: SeriesDeployment[] = [];
for (const [ticker, t] of Object.entries(TRADERS)) {
  let vault: Address;
  if (testnet) {
    const pps = await realPps(t.vault as Address);
    vault = await deploy("elysium/MirrorVault.sol", "MirrorVault", [
      usdc,
      `LiquidV ${ticker} (testnet mirror)`,
      ticker,
      t.vault,
      999n,
      t.trader,
      pps,
      pct(0.01), // LiquidV's 1% mint fee
      30n, //       0.3% exit fee
      BigInt(process.env.MAX_RELAY_AGE ?? 120),
      keeper,
    ]);
    // the testnet vault pays the trader's gains out of test USDC
    await send(usdc, "mocks/MockUSDC.sol", "MockUSDC", "mint", [vault, parseUnits("10000000", 6)]);
  } else {
    vault = process.env.VAULT as Address;
  }

  let feed: Address;
  if (feedMode === "core") {
    if (!process.env.CORE_READER) throw new Error("FEED=core needs CORE_READER (Elysium's precompile adapter)");
    feed = await deploy("elysium/HyperCoreNavFeed.sol", "HyperCoreNavFeed", [
      process.env.CORE_READER,
      t.vault, //  the real vault's HyperCore account
      [0, 1], //   main dex and xyz, as the vault's perpDexes()
      BigInt(process.env.MAX_CORE_AGE ?? 2),
      BigInt(process.env.MAX_BOOK_AGE ?? 3600),
      keeper,
    ]);
  } else {
    feed = await deploy("liquidv/LiquidVNavFeed.sol", "LiquidVNavFeed", [vault]);
  }

  const name = `${ticker} ${B}x`;
  const symbol = `${ticker}${B}X`;
  const market = await deploy("liquidv/AsphodelLiquidVMarket.sol", "AsphodelLiquidVMarket", [
    name,
    symbol,
    vault,
    feed,
    config,
    account.address,
  ]);

  series.push({
    key: `${ticker}-${B}x`,
    name,
    symbol,
    trader: t.trader,
    traderName: t.name,
    sourceVault: t.vault,
    market,
    vault,
    feed,
    feedMode,
    boost: B,
    maxPrice: C,
    stopPrice: 0.25,
    hearthShare: 0.5,
  });
}

writeDeployment({
  network: net,
  chainId: chain.id,
  usdc,
  usdcIsTest: testnet,
  keeper,
  deployedAt: new Date().toISOString(),
  series,
});
console.log(`wrote deployments/${net}.json and app/src/deployments/${net}.json`);
