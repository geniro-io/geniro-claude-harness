import Redis from "ioredis";

export const redis = new Redis(process.env.REDIS_URL ?? "redis://127.0.0.1:6379");

/** Increment `key` and return the new count. Sets `ttlSeconds` only on creation. */
export async function bumpCounter(key: string, ttlSeconds: number): Promise<number> {
  const n = await redis.incr(key);
  if (n === 1) await redis.expire(key, ttlSeconds);
  return n;
}
