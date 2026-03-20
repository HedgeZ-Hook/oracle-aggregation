import { network } from "hardhat";
import {
  loopIntervalMs,
  makeRuntime,
  printHeader,
  printTradeLine,
  randomEthAmount,
  sleep,
} from "./uniswap-v3-sepolia-runtime";
import { parseUnitsDecimal } from "./uniswap-v3-sepolia-config";
import { parseUnits } from "ethers";

async function main() {
  const { ethers } = await network.connect();
  const runtime = await makeRuntime(ethers);
  const intervalMs = loopIntervalMs();

  await runtime.ensurePoolExists();
  await runtime.ensureBalances();

  printHeader("Sepolia Swap Runner", {
    pool: runtime.deployment.pool,
    mockUsdt: runtime.deployment.mockUsdt,
    intervalMs,
    startPrice: (await runtime.readPrice()).toFixed(6),
  });

  let index = 0;
  for (;;) {
    await runtime.ensureBalances();
    const startPrice = await runtime.readPrice();
    const sellEth = Math.random() < 0.5;
    const ethAmount = randomEthAmount();

    if (sellEth) {
      const amountIn = parseUnitsDecimal(
        { parseUnits },
        ethAmount.toFixed(6),
        runtime.deployment.baseDecimals,
      );
      await runtime.exactInputSingleSafe(
        runtime.deployment.weth,
        runtime.deployment.mockUsdt,
        amountIn,
      );
      const after = await runtime.readPrice();
      printTradeLine({
        direction: "SELL ETH",
        amountLabel: "ethIn",
        amountValue: ethAmount.toFixed(6),
        priceBefore: startPrice.toFixed(6),
        priceAfter: after.toFixed(6),
      });
    } else {
      const usdtAmount = ethAmount.mul(startPrice);
      const amountIn = parseUnitsDecimal(
        { parseUnits },
        usdtAmount.toFixed(6),
        runtime.deployment.quoteDecimals,
      );
      await runtime.exactInputSingleSafe(
        runtime.deployment.mockUsdt,
        runtime.deployment.weth,
        amountIn,
      );
      const after = await runtime.readPrice();
      printTradeLine({
        direction: "BUY ETH",
        amountLabel: "usdtIn",
        amountValue: usdtAmount.toFixed(6),
        priceBefore: startPrice.toFixed(6),
        priceAfter: after.toFixed(6),
      });
    }
    index += 1;
    await sleep(intervalMs);
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
