import type { User } from "../types/user";

const TTL_MS = 30 * 60 * 1000;
const store = new Map<string, { user: User; issuedAt: number }>();

export function createSession(user: User): string {
  const token = crypto.randomUUID();
  store.set(token, { user, issuedAt: Date.now() });
  return token;
}

export function touchSession(token: string): User | null {
  const row = store.get(token);
  if (!row) return null;
  if (Date.now() - row.issuedAt > TTL_MS) {
    store.delete(token);
    return null;
  }
  return row.user;
}

export function endSession(token: string): void {
  store.delete(token);
}
