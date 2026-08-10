const store = new Map<string, { v: string; exp: number }>();
export const CACHE_TTL_MS = 60_000;

export function get(k: string): string | null {
  const hit = store.get(k);
  if (!hit) return null;
  if (Date.now() > hit.exp) { store.delete(k); return null; }
  return hit.v;
}

export function set(k: string, v: string): void {
  store.set(k, { v, exp: Date.now() + CACHE_TTL_MS });
}
