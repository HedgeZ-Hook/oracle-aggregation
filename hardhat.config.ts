import dotenv from "dotenv";
import { defineConfig } from "hardhat/config";
import hardhatEthers from "@nomicfoundation/hardhat-ethers";
import hardhatFoundry from "@nomicfoundation/hardhat-foundry";
import hardhatMocha from "@nomicfoundation/hardhat-mocha";

dotenv.config();

const privateKey = process.env.PRIVATE_KEY;

function httpNetwork(url: string, chainId: number) {
  return {
    type: "http" as const,
    chainId,
    url,
    accounts: privateKey ? [privateKey] : [],
  };
}

const networks = {
  hardhatMainnet: {
    type: "edr-simulated" as const,
    chainType: "l1" as const,
  },
  lasna: httpNetwork("https://lasna-rpc.rnk.dev/", 5318007),
  reactiveMainnet: httpNetwork("https://mainnet-rpc.rnk.dev/", 1597),
};

export default defineConfig({
  plugins: [hardhatEthers, hardhatFoundry, hardhatMocha],
  solidity: {
    version: "0.8.30",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  networks,
  paths: {
    sources: "./src",
    tests: "./hardhat-test",
    cache: "./hardhat-cache",
    artifacts: "./artifacts",
  },
});
