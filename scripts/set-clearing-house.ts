import hre from "hardhat";

async function main() {
  const destinationAddress = process.argv[2];
  const clearingHouseAddress = process.argv[3];

  if (!destinationAddress || !clearingHouseAddress) {
    throw new Error(
      "Usage: npx hardhat run scripts/set-clearing-house.ts -- <destination> <clearingHouse>",
    );
  }

  const unichain = await hre.network.connect("unichainSepolia");
  const { ethers } = unichain;

  const destination = await ethers.getContractAt(
    "LiquidationDestinationCallback",
    destinationAddress,
  );

  const tx = await destination.setClearingHouseContract(clearingHouseAddress);
  await tx.wait();

  console.log("LiquidationDestinationCallback:", destinationAddress);
  console.log("clearingHouseContract:", clearingHouseAddress);
  console.log("txHash:", tx.hash);
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
