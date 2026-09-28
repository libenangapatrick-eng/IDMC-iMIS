type LogLevel = "INFO" | "ERROR" | "WARN";

const REDACTED_KEYS = /authorization|cookie|password|secret|token|service.?role|api.?key/i;

function sanitize(value: unknown, depth = 0): unknown {
  if (depth > 5) return "[MAX_DEPTH]";
  if (value instanceof Error) return { name: value.name, message: value.message, stack: process.env.NODE_ENV === "production" ? undefined : value.stack };
  if (Array.isArray(value)) return value.slice(0, 100).map(item => sanitize(item, depth + 1));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>).map(([key, item]) => [key, REDACTED_KEYS.test(key) ? "[REDACTED]" : sanitize(item, depth + 1)]));
  }
  return value;
}

function write(level: LogLevel, message: string, data?: unknown): void {
  const record = JSON.stringify({ timestamp: new Date().toISOString(), level, message, ...(data === undefined ? {} : { data: sanitize(data) }) });
  if (level === "ERROR") console.error(record);
  else if (level === "WARN") console.warn(record);
  else console.log(record);
}

export function logInfo(message: string, data?: unknown) { write("INFO", message, data); }
export function logWarn(message: string, data?: unknown) { write("WARN", message, data); }
export function logError(message: string, error?: unknown) { write("ERROR", message, error); }
export { sanitize as sanitizeLogData };
