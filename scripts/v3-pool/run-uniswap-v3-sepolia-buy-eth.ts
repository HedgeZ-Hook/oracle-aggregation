import { network } from "hardhat";
import {
  makeRuntime,
  printHeader,
  printTradeLine,
  randomEthAmount,
} from "./uniswap-v3-sepolia-runtime";
import { parseUnitsDecimal } from "./uniswap-v3-sepolia-config";
import { parseUnits } from "ethers";
import Decimal from "decimal.js";

async function main() {
  const { ethers } = await network.connect();
  const runtime = await makeRuntime(ethers);

  await runtime.ensurePoolExists();
  await runtime.ensureBalances();

  printHeader("Buy ETH", {
    pool: runtime.deployment.pool,
    mockUsdt: runtime.deployment.mockUsdt,
    mode: "single-shot",
    direction: "USDT->WETH",
    startPrice: (await runtime.readPrice()).toFixed(6),
  });

  await runtime.ensureBalances();
  const balancesBefore = await runtime.readBalances();
  const startPrice = await runtime.readPrice();
  const ethAmount = randomEthAmount(new Decimal("0.1"), new Decimal("0.1"));
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
  void balancesBefore;
  void executedAmountIn;
  printTradeLine({
    direction: "BUY ETH",
    amountLabel: "usdtIn",
    amountValue: usdtAmount.toFixed(6),
    priceBefore: startPrice.toFixed(6),
    priceAfter: endPrice.toFixed(6),
  });
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
