import app from "./app.js";
import { env } from "./config/env.js";
import { logInfo } from "./utils/logger.js";

const server = app.listen(env.PORT, () => {
  logInfo(
    `IDMC iMIS API running on http://localhost:${env.PORT}`
  );

  logInfo(
    `Health check: http://localhost:${env.PORT}/api/v1/health`
  );
});

// Keep connections reusable on slow or high-latency networks while still
// placing a hard upper bound on stalled requests.
server.keepAliveTimeout = 65_000;
server.headersTimeout = 66_000;
server.requestTimeout = 60_000;

function shutdown(signal: string) {
  logInfo(`${signal} received. Shutting down server...`);

  server.close(() => {
    logInfo("HTTP server closed.");
    process.exit(0);
  });
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
