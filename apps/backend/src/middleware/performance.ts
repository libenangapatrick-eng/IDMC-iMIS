import { gzipSync } from "node:zlib";
import type { NextFunction, Request, Response } from "express";

const MINIMUM_COMPRESSION_BYTES = 1024;

/**
 * Compress JSON responses without adding another runtime dependency.
 * Small responses are left untouched because gzip headers would cost more
 * bytes than they save.
 */
export function compressJson(req: Request, res: Response, next: NextFunction): void {
  const originalJson = res.json.bind(res);

  res.json = ((payload: unknown) => {
    if (res.headersSent || req.method === "HEAD" || !req.acceptsEncodings("gzip")) {
      return originalJson(payload);
    }

    const body = Buffer.from(JSON.stringify(payload));
    if (body.byteLength < MINIMUM_COMPRESSION_BYTES) return originalJson(payload);

    const compressed = gzipSync(body, { level: 6 });
    res.setHeader("Content-Type", "application/json; charset=utf-8");
    res.setHeader("Content-Encoding", "gzip");
    res.setHeader("Content-Length", String(compressed.byteLength));
    res.setHeader("Vary", "Accept-Encoding");
    return res.send(compressed);
  }) as Response["json"];

  next();
}

/**
 * Authenticated API responses may be cached only by the user's browser.
 * The short lifetime speeds repeated navigation without serving stale data
 * for long. Mutations always bypass the cache.
 */
export function apiCachePolicy(req: Request, res: Response, next: NextFunction): void {
  if (req.method === "GET" && !req.path.endsWith("/health") && !req.path.endsWith("/ready")) {
    res.setHeader("Cache-Control", "private, max-age=5, stale-while-revalidate=15");
  } else {
    res.setHeader("Cache-Control", "no-store");
  }
  next();
}
