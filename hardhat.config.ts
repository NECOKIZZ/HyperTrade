import { defineConfig } from "hardhat/config";

export default defineConfig({
  solidity: {
    version: "0.8.28",
    settings: { optimizer: { enabled: true, runs: 200 }, viaIR: true },
  },
  paths: { tests: { solidity: "test" } },
  test: {
    solidity: {
      // fork tests (test/fork/) only run with LIQUIDV_FORK=true
      forking: { rpcEndpoints: { hyperevm: "https://rpc.hyperliquid.xyz/evm" } },
    },
  },
});
