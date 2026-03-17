import { network } from "hardhat";
import { Contract, parseUnits } from "ethers";
import {
  alignTick,
  DEADLINE_WINDOW_SECONDS,
  DEFAULT_INITIAL_PRICE,
  DEFAULT_LP_ETH,
  DEFAULT_LP_USDT,
  DEFAULT_RANGE_LOWER,
  DEFAULT_RANGE_UPPER,
  ERC20_ABI,
  parseUnitsDecimal,
  POSITION_MANAGER_ABI,
  quotePerBaseToTick,
  TICK_SPACING,
  WETH9_ABI,
} from "./uniswap-v3-sepolia-config";
import { loadDeployment } from "./uniswap-v3-sepolia-runtime";

async function main() {
  const { ethers } = await network.connect();
  const [deployer] = await ethers.getSigners();
  const deployment = loadDeployment();

  const wethAmount = DEFAULT_LP_ETH;
  const usdtAmount = DEFAULT_LP_USDT;
  const rangeLower = DEFAULT_RANGE_LOWER;
  const rangeUpper = DEFAULT_RANGE_UPPER;
  const referencePrice = DEFAULT_INITIAL_PRICE;

  const weth = new Contract(deployment.weth, WETH9_ABI, deployer);
  const usdt = new Contract(deployment.mockUsdt, ERC20_ABI, deployer);
  const positionManager = new Contract(
    deployment.positionManager,
    POSITION_MANAGER_ABI,
    deployer,
  );

  const lpEthRaw = parseUnitsDecimal(
    { parseUnits },
    wethAmount,
    deployment.baseDecimals,
  );
  const lpUsdtRaw = parseUnitsDecimal(
    { parseUnits },
    usdtAmount,
    deployment.quoteDecimals,
  );

  const rawTickA = alignTick(
    quotePerBaseToTick(
      rangeLower,
      deployment.baseDecimals,
      deployment.quoteDecimals,
      deployment.token0IsBase,
    ),
    TICK_SPACING,
  );
  const rawTickB = alignTick(
    quotePerBaseToTick(
      rangeUpper,
      deployment.baseDecimals,
      deployment.quoteDecimals,
      deployment.token0IsBase,
    ),
    TICK_SPACING,
  );
  const tickLower = Math.min(rawTickA, rawTickB);
  const tickUpper = Math.max(rawTickA, rawTickB);

  const [wethBalance, usdtBalance] = await Promise.all([
    weth.balanceOf(await deployer.getAddress()),
    usdt.balanceOf(await deployer.getAddress()),
  ]);

  if (wethBalance < lpEthRaw) {
    const shortfall = lpEthRaw - wethBalance;
    await (await weth.deposit({ value: shortfall })).wait();
  }

  if (usdtBalance < lpUsdtRaw) {
    const shortfall = lpUsdtRaw - usdtBalance;
    await (await usdt.mint(await deployer.getAddress(), shortfall)).wait();
  }

  await (await weth.approve(deployment.positionManager, lpEthRaw)).wait();
  await (await usdt.approve(deployment.positionManager, lpUsdtRaw)).wait();

  const latestBlock = await ethers.provider.getBlock("latest");
  const deadline = BigInt(
    (latestBlock?.timestamp || Math.floor(Date.now() / 1000)) +
      DEADLINE_WINDOW_SECONDS,
  );

  const amount0Desired = deployment.token0IsBase ? lpEthRaw : lpUsdtRaw;
  const amount1Desired = deployment.token0IsBase ? lpUsdtRaw : lpEthRaw;

  const tx = await positionManager.mint([
    deployment.token0,
    deployment.token1,
    deployment.fee,
    tickLower,
    tickUpper,
    amount0Desired,
    amount1Desired,
    0,
    0,
    await deployer.getAddress(),
    deadline,
  ]);
  const receipt = await tx.wait();

  console.log("pool:", deployment.pool);
  console.log("referencePrice:", referencePrice);
  console.log("tickLower:", tickLower);
  console.log("tickUpper:", tickUpper);
  console.log("addedWeth:", wethAmount);
  console.log("addedUsdt:", usdtAmount);
  console.log("txHash:", receipt?.hash);
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
