import hre from "hardhat";
import { optionalBigInt } from "./utils";

const LASNA_CHAIN_ID = 5318007n;
const UNICHAIN_SEPOLIA_CHAIN_ID = 1301n;
const UNICHAIN_SEPOLIA_CALLBACK_SENDER =
  "0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4";
const AGGREGATION_ADDRESS = "0xb5F2B687DE2666A37990b3C1DbBC505f4fb4F653";
const CLEARING_HOUSE_ADDRESS = "0xC33Ea3fE367D12aC097a80Db9469e47DD6aAB16e";
const VAULT_ADDRESS = "0x8E4E07959155B7e03871bf8c93E605268578308C";

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

  const destinationDeployValue = optionalBigInt(
    "DEPLOY_VALUE_WEI",
    1n * 10n ** 17n,
  );
  const destinationFactory = await uniEthers.getContractFactory(
    "LiquidationDestinationCallback",
  );
  const destination = await destinationFactory.deploy(
    uniEthers.ZeroAddress,
    uniEthers.ZeroAddress,
    UNICHAIN_SEPOLIA_CALLBACK_SENDER,
    {
      value: destinationDeployValue,
    },
  );
  await destination.waitForDeployment();
  const destinationAddress = await destination.getAddress();

  const setClearingHouseTx = await destination.setClearingHouseContract(
    CLEARING_HOUSE_ADDRESS,
  );
  await setClearingHouseTx.wait();

  const setVaultTx = await destination.setVaultContract(VAULT_ADDRESS);
  await setVaultTx.wait();

  const setTrustedAggregatorTx =
    await destination.setTrustedAggregator(AGGREGATION_ADDRESS);
  await setTrustedAggregatorTx.wait();

  console.log("Unichain Sepolia:");
  console.log("  chainId:", uniNetwork.chainId.toString());
  console.log("  LiquidationDestinationCallback:", destinationAddress);
  console.log("  callbackSender:", UNICHAIN_SEPOLIA_CALLBACK_SENDER);
  console.log("  destination.clearingHouseContract:", CLEARING_HOUSE_ADDRESS);
  console.log("  destination.trustedAggregator:", AGGREGATION_ADDRESS);
  console.log("  destination.vaultContract:", VAULT_ADDRESS);
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
