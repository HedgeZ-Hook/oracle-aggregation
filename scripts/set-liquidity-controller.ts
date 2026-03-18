import hre from "hardhat";

async function main() {
  const separatorIndex = process.argv.indexOf("--");
  const cliArgs =
    separatorIndex >= 0 ? process.argv.slice(separatorIndex + 1) : [];
  const destinationAddress =
    cliArgs[0] || "0x2c4FC7a951c8182e7b2e18BfEb70930D2E96b74d";
  const liquidityControllerAddress =
    cliArgs[1] || "0xaDa34B52112C682E9b5d783f1B664b2cf8976dfE";

  if (!destinationAddress || !liquidityControllerAddress) {
    throw new Error(
      "Usage: npx hardhat run scripts/set-liquidity-controller.ts --network unichainSepolia -- <destination> <liquidityController>",
    );
  }

  const unichain = await hre.network.connect("unichainSepolia");
  const { ethers } = unichain;

  const destination = await ethers.getContractAt(
    "LiquidationDestinationCallback",
    destinationAddress,
  );

  const tx = await destination.setLiquidityControllerContract(
    liquidityControllerAddress,
  );
  await tx.wait();

  console.log("LiquidationDestinationCallback:", destinationAddress);
  console.log("liquidityControllerContract:", liquidityControllerAddress);
  console.log("txHash:", tx.hash);
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
