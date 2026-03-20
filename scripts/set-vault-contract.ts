import hre from "hardhat";

async function main() {
  const separatorIndex = process.argv.indexOf("--");
  const cliArgs =
    separatorIndex >= 0 ? process.argv.slice(separatorIndex + 1) : [];
  const destinationAddress =
    cliArgs[0] || "0xE6D19cBA9e4c978688dfbFEf1D63805e4f3D71Be";
  const vaultContractAddress =
    cliArgs[1] || "0x9748001645bF1FCafddDD1FA354e729d51B31861";

  if (!destinationAddress || !vaultContractAddress) {
    throw new Error(
      "Usage: npx hardhat run scripts/set-vault-contract.ts --network unichainSepolia -- <destination> <vault>",
    );
  }

  const unichain = await hre.network.connect("unichainSepolia");
  const { ethers } = unichain;

  const destination = await ethers.getContractAt(
    "LiquidationDestinationCallback",
    destinationAddress,
  );

  const tx = await destination.setVaultContract(vaultContractAddress);
  await tx.wait();

  console.log("LiquidationDestinationCallback:", destinationAddress);
  console.log("Vault Contract:", vaultContractAddress);
  console.log("txHash:", tx.hash);
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
