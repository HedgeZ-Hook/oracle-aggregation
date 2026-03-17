import { network } from "hardhat";
import { Contract, parseUnits } from "ethers";
import Decimal from "decimal.js";
import {
  alignTick,
  DEADLINE_WINDOW_SECONDS,
  decodeQuotePerBase,
  DEFAULT_INITIAL_PRICE,
  DEFAULT_LP_ETH,
  DEFAULT_LP_USDT,
  DEFAULT_RANGE_LOWER,
  DEFAULT_RANGE_UPPER,
  DEFAULT_SWAP_USDT_BUDGET,
  DEFAULT_SWAP_WETH_BUDGET,
  encodeSqrtPriceX96,
  envNumber,
  envString,
  ERC20_ABI,
  FACTORY_ABI,
  FEE,
  parseUnitsDecimal,
  POOL_ABI,
  POSITION_MANAGER_ABI,
  quotePerBaseToTick,
  TICK_SPACING,
  WETH9_ABI,
} from "./uniswap-v3-sepolia-config";
import { saveDeployment } from "./uniswap-v3-sepolia-runtime";

const SEPOLIA_WETH9 = "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14";
const SEPOLIA_V3_FACTORY = "0x0227628f3F023bb0B980b67D528571c95c6DaC1c";
const SEPOLIA_V3_POSITION_MANAGER =
  "0x1238536071E1c677A632429e3655c799b22cDA52";
// @dev Sepolia docs list SwapRouter02 rather than legacy SwapRouter.
const SEPOLIA_V3_SWAP_ROUTER = "0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E";
const USDT_ADDRESS = "0xe8B07Ab06513B3d5354eEc6Ef739d3Eb5E540d9f";

async function main() {
  const { ethers } = await network.connect();
  const [deployer] = await ethers.getSigners();

  const wethAddress = SEPOLIA_WETH9;
  const factoryAddress = SEPOLIA_V3_FACTORY;
  const positionManagerAddress = SEPOLIA_V3_POSITION_MANAGER;
  const swapRouterAddress = SEPOLIA_V3_SWAP_ROUTER;

  const initialPrice = envNumber(
    "SEPOLIA_V3_INITIAL_PRICE",
    DEFAULT_INITIAL_PRICE,
  );
  const rangeLower = envNumber("SEPOLIA_V3_RANGE_LOWER", DEFAULT_RANGE_LOWER);
  const rangeUpper = envNumber("SEPOLIA_V3_RANGE_UPPER", DEFAULT_RANGE_UPPER);
  const lpEthAmount = envString("SEPOLIA_V3_LP_ETH_AMOUNT", DEFAULT_LP_ETH);
  const lpUsdtAmount = envString("SEPOLIA_V3_LP_USDT_AMOUNT", DEFAULT_LP_USDT);
  const swapWethBudget = envString(
    "SEPOLIA_V3_SWAP_WETH_BUDGET",
    DEFAULT_SWAP_WETH_BUDGET,
  );
  const swapUsdtBudget = envString(
    "SEPOLIA_V3_SWAP_USDT_BUDGET",
    DEFAULT_SWAP_USDT_BUDGET,
  );

  const baseDecimals = 18;
  const quoteDecimals = 6;

  const usdt = new Contract(USDT_ADDRESS, ERC20_ABI, deployer);
  const usdtAddress = await usdt.getAddress();
  const weth = new Contract(wethAddress, WETH9_ABI, deployer);
  const factory = new Contract(factoryAddress, FACTORY_ABI, deployer);
  const positionManager = new Contract(
    positionManagerAddress,
    POSITION_MANAGER_ABI,
    deployer,
  );
  const token0IsBase = wethAddress.toLowerCase() < usdtAddress.toLowerCase();
  const token0 = token0IsBase ? wethAddress : usdtAddress;
  const token1 = token0IsBase ? usdtAddress : wethAddress;

  const sqrtPriceX96 = encodeSqrtPriceX96(
    initialPrice,
    baseDecimals,
    quoteDecimals,
    token0IsBase,
  );
  const initialTick = quotePerBaseToTick(
    initialPrice,
    baseDecimals,
    quoteDecimals,
    token0IsBase,
  );
  const rawTickA = alignTick(
    quotePerBaseToTick(rangeLower, baseDecimals, quoteDecimals, token0IsBase),
    TICK_SPACING,
  );
  const rawTickB = alignTick(
    quotePerBaseToTick(rangeUpper, baseDecimals, quoteDecimals, token0IsBase),
    TICK_SPACING,
  );
  const tickLower = Math.min(rawTickA, rawTickB);
  const tickUpper = Math.max(rawTickA, rawTickB);

  if (tickLower >= tickUpper) {
    throw new Error("Invalid tick range");
  }

  const lpEthRaw = parseUnitsDecimal({ parseUnits }, lpEthAmount, baseDecimals);
  const lpUsdtRaw = parseUnitsDecimal(
    { parseUnits },
    lpUsdtAmount,
    quoteDecimals,
  );
  const wethBudgetRaw = parseUnitsDecimal(
    { parseUnits },
    swapWethBudget,
    baseDecimals,
  );
  const usdtBudgetRaw = parseUnitsDecimal(
    { parseUnits },
    swapUsdtBudget,
    quoteDecimals,
  );
  const usdtMintAmount = lpUsdtRaw + usdtBudgetRaw;
  const wethWrapAmount = lpEthRaw + wethBudgetRaw;

  const mintTx = await usdt.mint(await deployer.getAddress(), usdtMintAmount);
  await mintTx.wait();

  const wrapTx = await weth.deposit({ value: wethWrapAmount });
  await wrapTx.wait();

  await (await usdt.approve(positionManagerAddress, usdtMintAmount)).wait();
  await (await usdt.approve(swapRouterAddress, usdtMintAmount)).wait();
  await (await weth.approve(positionManagerAddress, wethWrapAmount)).wait();
  await (await weth.approve(swapRouterAddress, wethWrapAmount)).wait();

  const createTx = await positionManager.createAndInitializePoolIfNecessary(
    token0,
    token1,
    FEE,
    sqrtPriceX96,
  );
  await createTx.wait();

  const poolAddress = await factory.getPool(token0, token1, FEE);
  if (poolAddress === ethers.ZeroAddress) {
    throw new Error("Pool was not created");
  }

  const latestBlock = await ethers.provider.getBlock("latest");
  const deadline = BigInt(
    (latestBlock?.timestamp || Math.floor(Date.now() / 1000)) +
      DEADLINE_WINDOW_SECONDS,
  );

  const amount0Desired = token0IsBase ? lpEthRaw : lpUsdtRaw;
  const amount1Desired = token0IsBase ? lpUsdtRaw : lpEthRaw;

  const mintPositionTx = await positionManager.mint([
    token0,
    token1,
    FEE,
    tickLower,
    tickUpper,
    amount0Desired,
    amount1Desired,
    0,
    0,
    await deployer.getAddress(),
    deadline,
  ]);
  await mintPositionTx.wait();

  const pool = new Contract(poolAddress, POOL_ABI, deployer);

  async function readPrice(): Promise<Decimal> {
    const [slot0] = await Promise.all([pool.slot0()]);
    return decodeQuotePerBase(
      slot0.sqrtPriceX96,
      baseDecimals,
      quoteDecimals,
      token0IsBase,
    );
  }

  console.log("MockUSDT:", usdtAddress);
  console.log("WETH:", wethAddress);
  console.log("token0:", token0);
  console.log("token1:", token1);
  console.log("token0IsBase:", token0IsBase);
  console.log("pool:", poolAddress);
  console.log("initialPriceTarget:", initialPrice);
  console.log("initialTickApprox:", initialTick);
  console.log("tickLower:", tickLower);
  console.log("tickUpper:", tickUpper);
  console.log("lpEthAmount:", lpEthAmount);
  console.log("lpUsdtAmount:", lpUsdtAmount);
  console.log("initialSpotPrice:", (await readPrice()).toFixed(6));
  saveDeployment({
    mockUsdt: usdtAddress,
    weth: wethAddress,
    factory: factoryAddress,
    positionManager: positionManagerAddress,
    swapRouter: swapRouterAddress,
    pool: poolAddress,
    token0,
    token1,
    token0IsBase,
    fee: FEE,
    baseDecimals,
    quoteDecimals,
  });
  console.log("swapRouter:", swapRouterAddress);
  console.log("positionManager:", positionManagerAddress);
  console.log("factory:", factoryAddress);
  console.log("deploymentFile:", "scripts/v3-pool/uniswap-v3-sepolia-demo.json");
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
