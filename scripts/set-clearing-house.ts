import hre from "hardhat";

async function main() {
  const separatorIndex = process.argv.indexOf("--");
  const cliArgs =
    separatorIndex >= 0 ? process.argv.slice(separatorIndex + 1) : [];
  const destinationAddress =
    cliArgs[0] || "0xE6D19cBA9e4c978688dfbFEf1D63805e4f3D71Be";
  const clearingHouseAddress =
    cliArgs[1] || "0xa6a32f26eB837f4c9636688812efDef1Aa3ac8a6";

  if (!destinationAddress || !clearingHouseAddress) {
    throw new Error(
      "Usage: npx hardhat run scripts/set-clearing-house.ts --network unichainSepolia -- <destination> <clearingHouse>",
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
