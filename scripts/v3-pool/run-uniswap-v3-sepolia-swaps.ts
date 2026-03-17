import { network } from "hardhat";
import {
  loopIntervalMs,
  makeRuntime,
  sleep,
} from "./uniswap-v3-sepolia-runtime";

async function main() {
  const { ethers } = await network.connect();
  const runtime = await makeRuntime(ethers);
  const intervalMs = loopIntervalMs();

  await runtime.ensurePoolExists();
  await runtime.ensureBalances();

  console.log("pool:", runtime.deployment.pool);
  console.log("mockUsdt:", runtime.deployment.mockUsdt);
  console.log("intervalMs:", intervalMs);
  console.log("startPrice:", (await runtime.readPrice()).toFixed(6));

  let index = 0;
  for (;;) {
    await runtime.ensureBalances();
    const cycle = await runtime.swapVolumeCycle();
    const after = await runtime.readPrice();
    console.log(
      `[${new Date().toISOString()}] step=${index} startPrice=${cycle.currentPrice.toFixed(6)} endPrice=${after.toFixed(6)} firstLeg=${cycle.startWithWeth ? "WETH->USDT" : "USDT->WETH"} ethA=${cycle.randomEthA.toFixed(6)} ethB=${cycle.randomEthB.toFixed(6)} usdtA=${cycle.usdtAmountA.toFixed(6)} usdtB=${cycle.usdtAmountB.toFixed(6)} executedA=${cycle.executedAmountInA.toString()} executedB=${cycle.executedAmountInB.toString()}`,
    );
    index += 1;
    await sleep(intervalMs);
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
