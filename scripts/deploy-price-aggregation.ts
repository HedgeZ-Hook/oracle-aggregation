import { network } from "hardhat";
import { optionalBigInt } from "./utils";

const DEFAULT_INTERVAL = 1800;
const DEFAULT_CALLBACK_GAS_LIMIT = 400_000;

const POOL_CONFIGS = [
  {
    sourceChainId: 1n,
    pool: "0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36",
    token0Decimals: 18,
    token1Decimals: 6,
    useQuoteAsBase: false,
    weight: 50n,
  },
  {
    sourceChainId: 8453n,
    pool: "0x6c561B446416E1A00E8E93E221854d6eA4171372",
    token0Decimals: 18,
    token1Decimals: 6,
    useQuoteAsBase: false,
    weight: 50n,
  },
] as const;

// @dev: this is for deploying reactive mainnet for testing
async function main() {
  const { ethers } = await network.connect();
  const deployChainId = (await ethers.provider.getNetwork()).chainId;
  const interval = String(DEFAULT_INTERVAL);
  const callbackChainId = 1;
  const callbackTarget = ethers.ZeroAddress;
  const callbackGasLimit = String(DEFAULT_CALLBACK_GAS_LIMIT);
  const deployValue = optionalBigInt("DEPLOY_VALUE_WEI", 0n);

  const factory = await ethers.getContractFactory("PriceAggregationReactive");
  const contract = await factory.deploy(
    interval,
    POOL_CONFIGS,
    callbackChainId,
    callbackTarget,
    callbackGasLimit,
    { value: deployValue },
  );

  await contract.waitForDeployment();

  console.log("PriceAggregationReactive:", await contract.getAddress());
  console.log("deployChainId:", deployChainId.toString());
  console.log("defaultInterval:", interval);
  console.log("callbackChainId:", callbackChainId.toString());
  console.log("callbackTarget:", callbackTarget);
  console.log("callbackGasLimit:", callbackGasLimit);
  console.log("poolCount:", POOL_CONFIGS.length);
  for (const [index, pool] of POOL_CONFIGS.entries()) {
    console.log(
      `pool[${index}]`,
      pool.pool,
      "sourceChainId=",
      pool.sourceChainId.toString(),
      "token0Decimals=",
      pool.token0Decimals,
      "token1Decimals=",
      pool.token1Decimals,
      "useQuoteAsBase=",
      pool.useQuoteAsBase,
      "weight=",
      pool.weight.toString(),
    );
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
