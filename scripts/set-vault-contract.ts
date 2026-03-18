import hre from "hardhat";

async function main() {
  const separatorIndex = process.argv.indexOf("--");
  const cliArgs =
    separatorIndex >= 0 ? process.argv.slice(separatorIndex + 1) : [];
  const destinationAddress =
    cliArgs[0] || "0x2c4FC7a951c8182e7b2e18BfEb70930D2E96b74d";
  const vaultContractAddress =
    cliArgs[1] || "0x8d8d238ac27859a61debeeca4bbd4a4598cbbf8d";

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
