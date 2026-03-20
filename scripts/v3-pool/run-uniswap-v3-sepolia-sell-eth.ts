import { network } from "hardhat";
import {
  loopIntervalMs,
  makeRuntime,
  randomEthAmount,
  sleep,
} from "./uniswap-v3-sepolia-runtime";
import { parseUnitsDecimal } from "./uniswap-v3-sepolia-config";
import { parseUnits } from "ethers";
import Decimal from "decimal.js";

async function main() {
  const { ethers } = await network.connect();
  const runtime = await makeRuntime(ethers);
  // const intervalMs = loopIntervalMs();

  await runtime.ensurePoolExists();
  await runtime.ensureBalances();

  console.log("pool:", runtime.deployment.pool);
  console.log("mockUsdt:", runtime.deployment.mockUsdt);
  // console.log("intervalMs:", intervalMs);
  console.log("direction:", "WETH->USDT");
  console.log("startPrice:", (await runtime.readPrice()).toFixed(6));

  let index = 0;
  // for (;;) {
  await runtime.ensureBalances();
  const startPrice = await runtime.readPrice();
  const ethAmount = randomEthAmount(new Decimal("0.22"), new Decimal("0.22"));
  const amountIn = parseUnitsDecimal(
    { parseUnits },
    ethAmount.toFixed(6),
    runtime.deployment.baseDecimals,
  );
  const executedAmountIn = await runtime.exactInputSingleSafe(
    runtime.deployment.weth,
    runtime.deployment.mockUsdt,
    amountIn,
  );
  const endPrice = await runtime.readPrice();
  console.log("afterPrice:", endPrice.toFixed(6));

  console.log(
    `[${new Date().toISOString()}] step=${index} startPrice=${startPrice.toFixed(6)} endPrice=${endPrice.toFixed(6)} direction=WETH->USDT ethIn=${ethAmount.toFixed(6)} executedIn=${executedAmountIn.toString()}`,
  );

  index += 1;
  // await sleep(intervalMs);
  // }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
