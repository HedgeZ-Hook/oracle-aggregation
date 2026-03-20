// import hre from "hardhat";

// const PRICE_AGGREGATION_ADDRESS = "0xb5F2B687DE2666A37990b3C1DbBC505f4fb4F653";

// async function main() {
//   const unichain = await hre.network.connect("unichainSepolia");
//   const lasna = await hre.network.connect("lasna");

//   const { ethers: uniEthers } = unichain;
//   const { ethers: lasnaEthers } = lasna;

//   const uniNetwork = await uniEthers.provider.getNetwork();
//   const lasnaNetwork = await lasnaEthers.provider.getNetwork();

//   const aggregationFactory = await lasnaEthers.getContractFactory(
//     "PriceAggregationReactive",
//   );
//   const aggregation = aggregationFactory.attach(PRICE_AGGREGATION_ADDRESS);
//   aggregation.
// }

// main().catch((error: unknown) => {
//   console.error(error);
//   process.exitCode = 1;
// });
