import fs from "node:fs";

export type PoolConfigInput = {
  sourceChainId: number | string;
  pool: string;
  token0Decimals: number | string;
  token1Decimals: number | string;
  useQuoteAsBase: boolean;
  weight: number | string;
};

export function requiredEnv(name: string): string {
  const value = process.env[name];
  if (value === undefined || value === "") {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

export function optionalBigInt(name: string, fallback: bigint): bigint {
  const value = process.env[name];
  return value ? BigInt(value) : fallback;
}

export function loadPoolConfigs(): PoolConfigInput[] {
  const json = process.env.POOL_CONFIGS_JSON;
  const path = process.env.POOL_CONFIGS_FILE;

  if (json) {
    return JSON.parse(json) as PoolConfigInput[];
  }

  if (path) {
    return JSON.parse(fs.readFileSync(path, "utf8")) as PoolConfigInput[];
  }

  throw new Error("Set POOL_CONFIGS_JSON or POOL_CONFIGS_FILE");
}

export function normalizePoolConfig(pool: PoolConfigInput) {
  return {
    sourceChainId: BigInt(pool.sourceChainId),
    pool: pool.pool,
    token0Decimals: Number(pool.token0Decimals),
    token1Decimals: Number(pool.token1Decimals),
    useQuoteAsBase: Boolean(pool.useQuoteAsBase),
    weight: BigInt(pool.weight),
  };
}
