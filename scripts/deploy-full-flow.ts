import hre from "hardhat";
import { optionalBigInt } from "./utils";

const LASNA_CHAIN_ID = 5318007n;
const UNICHAIN_SEPOLIA_CHAIN_ID = 1301n;
const UNICHAIN_SEPOLIA_CALLBACK_SENDER =
  "0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4";

const DEFAULT_DESTINATION_GAS_LIMIT = 1_000_000;
const DEFAULT_AGGREGATOR_INTERVAL = 1800;
const DEFAULT_AGGREGATOR_CALLBACK_GAS_LIMIT = 1_000_000;

const POOL_CONFIGS = [
  {
    sourceChainId: 11155111n,
    pool: "0x0ba21779B8870E75A1eF24A29e0ccc392559d38f",
    token0Decimals: 6,
    token1Decimals: 18,
    useQuoteAsBase: true,
    weight: 1n,
  },
] as const;

async function main() {
  const unichain = await hre.network.connect("unichainSepolia");
  const lasna = await hre.network.connect("lasna");

  const { ethers: uniEthers } = unichain;
  const { ethers: lasnaEthers } = lasna;

  const uniNetwork = await uniEthers.provider.getNetwork();
  const lasnaNetwork = await lasnaEthers.provider.getNetwork();

  if (uniNetwork.chainId !== UNICHAIN_SEPOLIA_CHAIN_ID) {
    throw new Error(
      `Unexpected Unichain Sepolia chain id: ${uniNetwork.chainId.toString()}`,
    );
  }
  if (lasnaNetwork.chainId !== LASNA_CHAIN_ID) {
    throw new Error(
      `Unexpected Lasna chain id: ${lasnaNetwork.chainId.toString()}`,
    );
  }

  const destinationFactory = await uniEthers.getContractFactory(
    "LiquidationDestinationCallback",
  );
  const destination = await destinationFactory.deploy(
    uniEthers.ZeroAddress,
    uniEthers.ZeroAddress,
    UNICHAIN_SEPOLIA_CALLBACK_SENDER,
  );
  await destination.waitForDeployment();
  const destinationAddress = await destination.getAddress();

  const deployValue = optionalBigInt("DEPLOY_VALUE_WEI", 5n * 10n ** 18n);

  const monitorFactory = await lasnaEthers.getContractFactory(
    "LiquidationMonitorReactive",
  );
  const monitor = await monitorFactory.deploy(
    0,
    lasnaEthers.ZeroAddress,
    lasnaEthers.ZeroAddress,
    UNICHAIN_SEPOLIA_CHAIN_ID,
    destinationAddress,
    DEFAULT_DESTINATION_GAS_LIMIT,
    { value: deployValue },
  );
  await monitor.waitForDeployment();
  const monitorAddress = await monitor.getAddress();

  const aggregationFactory = await lasnaEthers.getContractFactory(
    "PriceAggregationReactive",
  );
  const aggregation = await aggregationFactory.deploy(
    DEFAULT_AGGREGATOR_INTERVAL,
    POOL_CONFIGS,
    LASNA_CHAIN_ID,
    monitorAddress,
    DEFAULT_AGGREGATOR_CALLBACK_GAS_LIMIT,
    { value: deployValue },
  );
  await aggregation.waitForDeployment();
  const aggregationAddress = await aggregation.getAddress();

  const setAggTx =
    await monitor.setPriceAggregationContract(aggregationAddress);
  await setAggTx.wait();

  console.log("Unichain Sepolia:");
  console.log("  chainId:", uniNetwork.chainId.toString());
  console.log("  LiquidationDestinationCallback:", destinationAddress);
  console.log("  callbackSender:", UNICHAIN_SEPOLIA_CALLBACK_SENDER);
  console.log("Lasna:");
  console.log("  chainId:", lasnaNetwork.chainId.toString());
  console.log("  LiquidationMonitorReactive:", monitorAddress);
  console.log("  monitor.sourceChainId:", "0");
  console.log("  monitor.sourceContract:", lasnaEthers.ZeroAddress);
  console.log("  monitor.priceAggregationContract:", aggregationAddress);
  console.log(
    "  monitor.destinationChainId:",
    UNICHAIN_SEPOLIA_CHAIN_ID.toString(),
  );
  console.log("  monitor.destinationContract:", destinationAddress);
  console.log("  PriceAggregationReactive:", aggregationAddress);
  console.log("  aggregation.callbackChainId:", LASNA_CHAIN_ID.toString());
  console.log("  aggregation.callbackTarget:", monitorAddress);
  console.log("  poolCount:", POOL_CONFIGS.length.toString());
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
