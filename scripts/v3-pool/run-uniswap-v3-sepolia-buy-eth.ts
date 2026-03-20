import { network } from "hardhat";
import { makeRuntime, randomEthAmount } from "./uniswap-v3-sepolia-runtime";
import { parseUnitsDecimal } from "./uniswap-v3-sepolia-config";
import { parseUnits } from "ethers";
import Decimal from "decimal.js";

async function main() {
  const { ethers } = await network.connect();
  const runtime = await makeRuntime(ethers);

  await runtime.ensurePoolExists();
  await runtime.ensureBalances();

  console.log("pool:", runtime.deployment.pool);
  console.log("mockUsdt:", runtime.deployment.mockUsdt);
  console.log("mode:", "single-shot");
  console.log("direction:", "USDT->WETH");
  console.log("startPrice:", (await runtime.readPrice()).toFixed(6));

  await runtime.ensureBalances();
  const startPrice = await runtime.readPrice();
  const ethAmount = randomEthAmount(new Decimal("0.15"), new Decimal("0.15"));
  const usdtAmount = ethAmount.mul(startPrice);
  const amountIn = parseUnitsDecimal(
    { parseUnits },
    usdtAmount.toFixed(6),
    runtime.deployment.quoteDecimals,
  );
  const executedAmountIn = await runtime.exactInputSingleSafe(
    runtime.deployment.mockUsdt,
    runtime.deployment.weth,
    amountIn,
  );
  const endPrice = await runtime.readPrice();
  console.log("afterPrice:", endPrice.toFixed(6));

  console.log(
    `[${new Date().toISOString()}] startPrice=${startPrice.toFixed(6)} endPrice=${endPrice.toFixed(6)} direction=USDT->WETH targetEth=${ethAmount.toFixed(6)} usdtIn=${usdtAmount.toFixed(6)} executedIn=${executedAmountIn.toString()}`,
  );
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
