import type { NextFunction, Request, Response } from "express";

type Entry = { count: number; resetAt: number };
const buckets = new Map<string, Entry>();

/** Small dependency-free limiter for authentication endpoints. */
export function rateLimit(options: { windowMs: number; max: number; name: string }) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const now = Date.now();
    const key = `${options.name}:${req.ip || req.socket.remoteAddress || "unknown"}`;
    const current = buckets.get(key);
    const entry = !current || current.resetAt <= now
      ? { count: 1, resetAt: now + options.windowMs }
      : { count: current.count + 1, resetAt: current.resetAt };
    buckets.set(key, entry);
    res.setHeader("RateLimit-Limit", String(options.max));
    res.setHeader("RateLimit-Remaining", String(Math.max(0, options.max - entry.count)));
    res.setHeader("RateLimit-Reset", String(Math.ceil(entry.resetAt / 1000)));
    if (entry.count > options.max) {
      res.status(429).json({ success: false, message: "Too many requests. Please try again later." });
      return;
    }
    if (buckets.size > 10_000) {
      for (const [bucketKey, value] of buckets) if (value.resetAt <= now) buckets.delete(bucketKey);
    }
    next();
  };
}
