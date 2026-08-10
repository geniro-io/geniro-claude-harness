import { redis } from "./store";

export const SESSION_TTL_SECONDS = 1800;

export type Session = { id: string; userId: string; issuedAt: number };

export async function loadSession(id: string): Promise<Session | null> {
  const raw = await redis.get(`sess:${id}`);
  return raw ? (JSON.parse(raw) as Session) : null;
}

export async function touchSession(s: Session): Promise<Session> {
  const ageSeconds = (Date.now() - s.issuedAt) / 1000;
  // Only re-issue once the session is more than halfway to expiry. A refresh on
  // every request would rewrite Redis on each call for no benefit.
  if (ageSeconds < SESSION_TTL_SECONDS / 2) {
    return s;
  }
  const next = { ...s, issuedAt: Date.now() };
  await redis.set(`sess:${next.id}`, JSON.stringify(next), "EX", SESSION_TTL_SECONDS);
  return next;
}
