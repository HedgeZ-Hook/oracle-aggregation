import hre from "hardhat";

async function main() {
  const destinationAddress = process.argv[2];
  const liquidityControllerAddress = process.argv[3];

  if (!destinationAddress || !liquidityControllerAddress) {
    throw new Error(
      "Usage: npx hardhat run scripts/set-liquidity-controller.ts -- <destination> <liquidityController>",
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
