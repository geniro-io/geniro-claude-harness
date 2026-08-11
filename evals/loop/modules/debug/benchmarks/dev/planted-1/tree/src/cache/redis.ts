import Redis from "ioredis";

export const redis = new Redis(process.env.REDIS_URL ?? "redis://localhost:6379");

// Entries are short-lived on purpose: a workspace switch must not be able to
// serve data cached under the previous workspace.
export const PROFILE_TTL_MS = 30_000;

export async function getJSON<T>(key: string): Promise<T | null> {
  const raw = await redis.get(key);
  return raw ? (JSON.parse(raw) as T) : null;
}

export async function setJSON(key: string, value: unknown): Promise<void> {
  await redis.set(key, JSON.stringify(value), "PX", PROFILE_TTL_MS);
}
