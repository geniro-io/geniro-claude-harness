export function rateLimit(_opts: { perMinute: number }) {
  return (_req: unknown, _res: unknown, next: () => void) => next();
}
