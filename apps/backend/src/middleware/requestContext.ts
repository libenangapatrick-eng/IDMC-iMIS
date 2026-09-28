import { randomUUID } from "node:crypto";
import type { NextFunction, Request, Response } from "express";
import { logInfo } from "../utils/logger.js";

declare global {
  namespace Express {
    interface Request {
      requestId?: string;
    }
  }
}

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._:-]{1,80}$/;

export function normalizeRequestId(value: unknown): string {
  const candidate = typeof value === "string" ? value.trim() : "";
  return REQUEST_ID_PATTERN.test(candidate) ? candidate : randomUUID();
}

export function requestContext(req: Request, res: Response, next: NextFunction): void {
  const startedAt = Date.now();
  req.requestId = normalizeRequestId(req.header("x-request-id"));
  res.setHeader("X-Request-Id", req.requestId);
  res.on("finish", () => {
    logInfo("http_request", {
      requestId: req.requestId,
      method: req.method,
      path: req.originalUrl,
      statusCode: res.statusCode,
      durationMs: Date.now() - startedAt,
      actorUserId: req.user?.id ?? null,
    });
  });
  next();
}
