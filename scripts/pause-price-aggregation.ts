import hre from "hardhat";

async function main() {
  const aggregationAddress = "0x60d7a73D5533F1c904daFEc34dBA188adEF83E74";

  if (!aggregationAddress) {
    throw new Error(
      "Usage: npx hardhat run scripts/pause-price-aggregation.ts --network lasna -- <priceAggregationReactive>",
    );
  }

  const lasna = await hre.network.connect("lasna");
  const { ethers } = lasna;

  const aggregation = await ethers.getContractAt(
    "PriceAggregationReactive",
    aggregationAddress,
  );

  const tx = await aggregation.pause();
  await tx.wait();

  console.log("PriceAggregationReactive:", aggregationAddress);
  console.log("action:", "pause");
  console.log("txHash:", tx.hash);
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
