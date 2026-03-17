import fs from "node:fs";
import path from "node:path";
import Decimal from "decimal.js";
import { Contract, MaxUint256, parseUnits } from "ethers";
import type { HardhatEthersHelpers } from "@nomicfoundation/hardhat-ethers/types";
import {
  decodeQuotePerBase,
  DEFAULT_RANDOM_ETH_MAX,
  DEFAULT_RANDOM_ETH_MIN,
  ERC20_ABI,
  FACTORY_ABI,
  parseUnitsDecimal,
  POOL_ABI,
  POSITION_MANAGER_ABI,
  SWAP_ROUTER_ABI,
  WETH9_ABI,
} from "./uniswap-v3-sepolia-config";

export const DEFAULT_DEPLOYMENT_PATH =
  "scripts/v3-pool/uniswap-v3-sepolia-demo.json";
const DEFAULT_MIN_USDT_BALANCE = "1000";
const DEFAULT_TOPUP_USDT = "10000";
const DEFAULT_MIN_WETH_BALANCE = "0.6";
const DEFAULT_TOPUP_WETH = "2.0";
const DEFAULT_SWAP_INTERVAL_MS = 60_000;
const MIN_SWAP_SCALE = new Decimal("0.125");
const ERC20_ALLOWANCE_ABI = [
  ...ERC20_ABI,
  "function allowance(address owner, address spender) external view returns (uint256)",
];

export type SepoliaDeployment = {
  mockUsdt: string;
  weth: string;
  factory: string;
  positionManager: string;
  swapRouter: string;
  pool: string;
  token0: string;
  token1: string;
  token0IsBase: boolean;
  fee: number;
  baseDecimals: number;
  quoteDecimals: number;
};

export function deploymentPath(): string {
  return DEFAULT_DEPLOYMENT_PATH;
}

export function saveDeployment(deployment: SepoliaDeployment) {
  const targetPath = deploymentPath();
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(targetPath, JSON.stringify(deployment, null, 2));
}

export function loadDeployment(): SepoliaDeployment {
  return JSON.parse(
    fs.readFileSync(deploymentPath(), "utf8"),
  ) as SepoliaDeployment;
}

export async function makeRuntime(ethers: HardhatEthersHelpers) {
  const [deployer] = await ethers.getSigners();
  const deployment = loadDeployment();

  const usdt = new Contract(deployment.mockUsdt, ERC20_ALLOWANCE_ABI, deployer);
  const weth = new Contract(deployment.weth, WETH9_ABI, deployer);
  const factory = new Contract(deployment.factory, FACTORY_ABI, deployer);
  const positionManager = new Contract(
    deployment.positionManager,
    POSITION_MANAGER_ABI,
    deployer,
  );
  const router = new Contract(deployment.swapRouter, SWAP_ROUTER_ABI, deployer);
  const pool = new Contract(deployment.pool, POOL_ABI, deployer);

  async function readPrice(): Promise<Decimal> {
    const slot0 = await pool.slot0();
    return decodeQuotePerBase(
      slot0.sqrtPriceX96,
      deployment.baseDecimals,
      deployment.quoteDecimals,
      deployment.token0IsBase,
    );
  }

  async function ensureBalances() {
    const owner = await deployer.getAddress();
    const minUsdt = parseUnitsDecimal(
      { parseUnits },
      DEFAULT_MIN_USDT_BALANCE,
      deployment.quoteDecimals,
    );
    const topUpUsdt = parseUnitsDecimal(
      { parseUnits },
      DEFAULT_TOPUP_USDT,
      deployment.quoteDecimals,
    );
    const minWeth = parseUnitsDecimal(
      { parseUnits },
      DEFAULT_MIN_WETH_BALANCE,
      deployment.baseDecimals,
    );
    const topUpWeth = parseUnitsDecimal(
      { parseUnits },
      DEFAULT_TOPUP_WETH,
      deployment.baseDecimals,
    );

    const [usdtBalance, wethBalance] = await Promise.all([
      usdt.balanceOf(owner),
      weth.balanceOf(owner),
    ]);

    if (usdtBalance < minUsdt) {
      await (await usdt.mint(owner, topUpUsdt)).wait();
    }

    if (wethBalance < minWeth) {
      await (await weth.deposit({ value: topUpWeth })).wait();
    }

    const [usdtAllowance, wethAllowance] = await Promise.all([
      usdt.allowance(owner, deployment.swapRouter),
      weth.allowance(owner, deployment.swapRouter),
    ]);

    if (usdtAllowance < topUpUsdt) {
      await (await usdt.approve(deployment.swapRouter, MaxUint256)).wait();
    }

    if (wethAllowance < topUpWeth) {
      await (await weth.approve(deployment.swapRouter, MaxUint256)).wait();
    }
  }

  async function swapVolumeCycle() {
    const currentPrice = await readPrice();
    const randomEthA = randomEthAmount();
    const randomEthB = randomEthAmount();
    const usdtAmountA = randomEthA.mul(currentPrice);
    const usdtAmountB = randomEthB.mul(currentPrice);
    const startWithWeth = Math.random() < 0.5;
    let executedAmountInA = 0n;
    let executedAmountInB = 0n;

    if (startWithWeth) {
      executedAmountInA = await exactInputSingleSafe(
        deployment.weth,
        deployment.mockUsdt,
        parseUnitsDecimal(
          { parseUnits },
          randomEthA.toFixed(6),
          deployment.baseDecimals,
        ),
      );

      executedAmountInB = await exactInputSingleSafe(
        deployment.mockUsdt,
        deployment.weth,
        parseUnitsDecimal(
          { parseUnits },
          usdtAmountB.toFixed(6),
          deployment.quoteDecimals,
        ),
      );
    } else {
      executedAmountInA = await exactInputSingleSafe(
        deployment.mockUsdt,
        deployment.weth,
        parseUnitsDecimal(
          { parseUnits },
          usdtAmountA.toFixed(6),
          deployment.quoteDecimals,
        ),
      );

      executedAmountInB = await exactInputSingleSafe(
        deployment.weth,
        deployment.mockUsdt,
        parseUnitsDecimal(
          { parseUnits },
          randomEthB.toFixed(6),
          deployment.baseDecimals,
        ),
      );
    }

    return {
      currentPrice,
      startWithWeth,
      randomEthA,
      randomEthB,
      usdtAmountA,
      usdtAmountB,
      executedAmountInA,
      executedAmountInB,
    };
  }

  async function ensurePoolExists() {
    const poolAddress = await factory.getPool(
      deployment.token0,
      deployment.token1,
      deployment.fee,
    );
    if (poolAddress.toLowerCase() !== deployment.pool.toLowerCase()) {
      throw new Error("Deployment file pool does not match factory pool");
    }
  }

  async function exactInputSingleSafe(
    tokenIn: string,
    tokenOut: string,
    amountIn: bigint,
  ): Promise<bigint> {
    let currentAmountIn = amountIn;

    for (;;) {
      try {
        const tx = await router.exactInputSingle([
          tokenIn,
          tokenOut,
          deployment.fee,
          await deployer.getAddress(),
          currentAmountIn,
          0,
          0,
        ]);
        await tx.wait();
        return currentAmountIn;
      } catch (error) {
        const nextAmountIn = currentAmountIn / 2n;
        const scaled = new Decimal(nextAmountIn.toString()).div(
          new Decimal(amountIn.toString()),
        );

        if (nextAmountIn === 0n || scaled.lt(MIN_SWAP_SCALE)) {
          throw error;
        }

        currentAmountIn = nextAmountIn;
      }
    }
  }

  return {
    deployment,
    usdt,
    weth,
    positionManager,
    router,
    pool,
    deployer,
    ensureBalances,
    ensurePoolExists,
    readPrice,
    swapVolumeCycle,
    exactInputSingleSafe,
  };
}

export function randomEthAmount(): Decimal {
  const min = new Decimal(DEFAULT_RANDOM_ETH_MIN);
  const max = new Decimal(DEFAULT_RANDOM_ETH_MAX);
  const ratio = new Decimal(Math.random().toString());
  return min.plus(max.minus(min).mul(ratio));
}

export function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function loopIntervalMs(): number {
  return DEFAULT_SWAP_INTERVAL_MS;
}
