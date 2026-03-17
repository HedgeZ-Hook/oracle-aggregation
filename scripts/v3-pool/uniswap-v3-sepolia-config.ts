import Decimal from "decimal.js";

Decimal.set({
  precision: 80,
  rounding: Decimal.ROUND_FLOOR,
  toExpNeg: -100,
  toExpPos: 100,
});

export const Q96 = new Decimal(2).pow(96);
export const FEE = 3_000;
export const TICK_SPACING = 60;
export const DEADLINE_WINDOW_SECONDS = 3_600;
export const DEFAULT_INITIAL_PRICE = 2_300;
export const DEFAULT_RANGE_LOWER = 1_800;
export const DEFAULT_RANGE_UPPER = 2_800;
export const DEFAULT_LP_ETH = "2.0";
export const DEFAULT_LP_USDT = "4600";
export const DEFAULT_SWAP_WETH_BUDGET = "3.0";
export const DEFAULT_SWAP_USDT_BUDGET = "12000";
export const DEFAULT_RANDOM_ETH_MIN = "0.02";
export const DEFAULT_RANDOM_ETH_MAX = "0.05";

export const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) external view returns (uint256)",
  "function balanceOf(address owner) external view returns (uint256)",
  "function mint(address to, uint256 amount) external",
];

export const WETH9_ABI = [...ERC20_ABI, "function deposit() external payable"];

export const FACTORY_ABI = [
  "function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address)",
];

export const POSITION_MANAGER_ABI = [
  "function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96) external payable returns (address pool)",
  "function mint((address token0,address token1,uint24 fee,int24 tickLower,int24 tickUpper,uint256 amount0Desired,uint256 amount1Desired,uint256 amount0Min,uint256 amount1Min,address recipient,uint256 deadline) params) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)",
];

export const SWAP_ROUTER_ABI = [
  "function exactInputSingle((address tokenIn,address tokenOut,uint24 fee,address recipient,uint256 amountIn,uint256 amountOutMinimum,uint160 sqrtPriceLimitX96) params) external payable returns (uint256 amountOut)",
];

export const POOL_ABI = [
  "function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)",
];

export function envNumber(name: string, fallback: number): number {
  const value = process.env[name];
  return value ? Number(value) : fallback;
}

export function envString(name: string, fallback: string): string {
  return process.env[name] || fallback;
}

export function alignTick(tick: number, tickSpacing: number): number {
  return Math.floor(tick / tickSpacing) * tickSpacing;
}

export function tokenPow(decimals: number): Decimal {
  return new Decimal(10).pow(decimals);
}

export function encodeSqrtPriceX96(
  quotePerBase: number,
  baseDecimals: number,
  quoteDecimals: number,
  token0IsBase: boolean,
): bigint {
  const marketPrice = new Decimal(quotePerBase);
  const rawRatio = token0IsBase
    ? marketPrice.mul(tokenPow(quoteDecimals)).div(tokenPow(baseDecimals))
    : tokenPow(baseDecimals).div(tokenPow(quoteDecimals).mul(marketPrice));

  return BigInt(rawRatio.sqrt().mul(Q96).floor().toFixed(0));
}

export function quotePerBaseToTick(
  quotePerBase: number,
  baseDecimals: number,
  quoteDecimals: number,
  token0IsBase: boolean,
): number {
  const marketPrice = new Decimal(quotePerBase);
  const rawRatio = token0IsBase
    ? marketPrice.mul(tokenPow(quoteDecimals)).div(tokenPow(baseDecimals))
    : tokenPow(baseDecimals).div(tokenPow(quoteDecimals).mul(marketPrice));

  return Math.floor(Math.log(rawRatio.toNumber()) / Math.log(1.0001));
}

export function decodeQuotePerBase(
  sqrtPriceX96: bigint,
  baseDecimals: number,
  quoteDecimals: number,
  token0IsBase: boolean,
): Decimal {
  const sqrt = new Decimal(sqrtPriceX96.toString()).div(Q96);
  const rawRatio = sqrt.pow(2);

  return token0IsBase
    ? rawRatio.mul(tokenPow(baseDecimals)).div(tokenPow(quoteDecimals))
    : tokenPow(baseDecimals).div(tokenPow(quoteDecimals).mul(rawRatio));
}

export function parseUnitsDecimal(
  ethersLike: { parseUnits(value: string, decimals: number): bigint },
  value: string,
  decimals: number,
): bigint {
  return ethersLike.parseUnits(value, decimals);
}
