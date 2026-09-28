export function parseAllowedOrigins(value: string): string[] {
  return [...new Set(value.split(",").map(item => item.trim().replace(/\/+$/, "")).filter(Boolean))];
}

export function isOriginAllowed(origin: string | undefined, allowedOrigins: string[]): boolean {
  if (!origin) return true;
  if (allowedOrigins.includes("*")) return true;
  return allowedOrigins.includes(origin.replace(/\/+$/, ""));
}

export function assertSafeProductionOrigins(nodeEnv: string, allowedOrigins: string[]): void {
  if (nodeEnv !== "production") return;
  if (!allowedOrigins.length || allowedOrigins.includes("*")) throw new Error("Production CORS_ORIGIN must contain explicit HTTPS frontend origins.");
  for (const origin of allowedOrigins) {
    const parsed = new URL(origin);
    if (parsed.protocol !== "https:") throw new Error(`Production CORS origin must use HTTPS: ${origin}`);
  }
}
