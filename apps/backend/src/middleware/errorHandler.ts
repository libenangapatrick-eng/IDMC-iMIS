import type { NextFunction, Request, Response } from "express";
import { env } from "../config/env.js";
import { logError } from "../utils/logger.js";

type HttpError = Error & {
  statusCode?: number;
  status?: number;
  code?: string;
  details?: string;
};

const SAFE_MESSAGES: Record<string, { status: number; message: string }> = {
  "22P02": { status: 400, message: "One of the supplied identifiers is invalid." },
  "23502": { status: 400, message: "A required value is missing." },
  "23503": { status: 409, message: "This record depends on another record that is missing or still in use." },
  "23505": { status: 409, message: "The same record already exists." },
  "42501": { status: 403, message: "Your account is not permitted to complete this action." },
  "PGRST116": { status: 404, message: "The requested record was not found." },
  "42P01": { status: 503, message: "This module is waiting for its database update. Contact the system administrator." },
  "42703": { status: 503, message: "This module is not synchronized with the current database. Contact the system administrator." },
};

function safeFailure(err: HttpError | undefined, requestId: string | undefined) {
  const code = String(err?.code ?? "").toUpperCase();
  if (SAFE_MESSAGES[code]) return SAFE_MESSAGES[code];

  const text = String(err?.message ?? "").toLowerCase();
  if (/fetch failed|network|econn|timeout|timed out|socket/.test(text)) {
    return { status: 503, message: "The database service is temporarily unavailable. Please try again." };
  }

  return {
    status: 500,
    message: `The requested operation could not be completed. Please retry. Reference: ${requestId ?? "unavailable"}`,
  };
}

export function errorHandler(err: unknown, req: Request, res: Response, _next: NextFunction) {
  logError("request_failed", { requestId: req.requestId, method: req.method, path: req.originalUrl, error: err });
  const message = err instanceof Error ? err.message : "The requested operation could not be completed.";
  const httpError = err instanceof Error ? err as HttpError : undefined;
  const candidate = httpError?.statusCode ?? httpError?.status;
  const explicitStatus = typeof candidate === "number" && Number.isInteger(candidate) && candidate >= 400 && candidate <= 599 ? candidate : null;
  const safe = safeFailure(httpError, req.requestId);
  const statusCode = explicitStatus ?? safe.status;
  const publicMessage = statusCode >= 500 ? safe.message : message;
  return res.status(statusCode).json({
    success: false,
    message: env.NODE_ENV === "production" ? publicMessage : (statusCode >= 500 ? `${publicMessage} (${message})` : message),
    requestId: req.requestId,
  });
}
