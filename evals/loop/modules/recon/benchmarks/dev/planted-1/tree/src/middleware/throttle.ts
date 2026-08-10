import type { Request, Response, NextFunction } from "express";
import { bumpCounter } from "../lib/redis";

export interface ThrottleOptions {
  /** Window length in seconds. */
  windowSeconds: number;
  /** Requests permitted per window. */
  max: number;
  /** Bucket discriminator. Defaults to the caller's IP. */
  keyBy?: (req: Request) => string;
}

/**
 * Fixed-window request limiter backed by Redis counters.
 *
 * The bucket key is `throttle:<route>:<discriminator>`. Callers that need a
 * dimension other than IP pass `keyBy`; nothing else about the middleware
 * changes.
 */
export function throttle(routeId: string, opts: ThrottleOptions) {
  const discriminate = opts.keyBy ?? ((req: Request) => req.ip ?? "unknown");
  return async function throttleMiddleware(req: Request, res: Response, next: NextFunction) {
    const bucket = `throttle:${routeId}:${discriminate(req)}`;
    const used = await bumpCounter(bucket, opts.windowSeconds);
    if (used > opts.max) {
      res.status(429).json({ error: { code: "rate_limited", message: "Too many requests" } });
      return;
    }
    res.setHeader("X-RateLimit-Remaining", String(Math.max(0, opts.max - used)));
    next();
  };
}
