import express from "express";
import cors from "cors";
import helmet from "helmet";

import { env } from "./config/env.js";
import { APP_NAME, API_BASE } from "./config/constants.js";
import { notFoundHandler } from "./middleware/notFound.js";
import { errorHandler } from "./middleware/errorHandler.js";
import apiRouter from "./routes/index.js";
import institutionManagementRoutes from "./modules/institution-management/institution-management.routes.js";
import studentManagementRoutes from "./modules/student-management/student-management.routes.js";
import { requestContext } from "./middleware/requestContext.js";
import { assertSafeProductionOrigins, isOriginAllowed, parseAllowedOrigins } from "./config/cors.js";
import { getSupabase } from "./config/database.js";
import { openApiDocument } from "./config/openapi.js";
import { apiCachePolicy, compressJson } from "./middleware/performance.js";

const app = express();
const allowedOrigins = parseAllowedOrigins(env.CORS_ORIGIN);
assertSafeProductionOrigins(env.NODE_ENV, allowedOrigins);

app.disable("x-powered-by");
app.set("etag", "strong");

app.use(
  helmet({
    crossOriginResourcePolicy: false,
  })
);

app.use(requestContext);
app.use(apiCachePolicy);
app.use(compressJson);

app.use(
  cors({
    origin(origin, callback) {
      const allowed = isOriginAllowed(origin, allowedOrigins);
      callback(allowed ? null : new Error("CORS origin is not allowed."), allowed);
    },
    credentials: true,
  })
);

app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ extended: true, limit: "10mb" }));

app.get("/", (_req, res) => {
  res.json({
    success: true,
    application: APP_NAME,
    version: "1.0.0",
    status: "online",
  });
});

app.get(`${API_BASE}/health`, (_req, res) => {
  res.json({
    success: true,
    application: APP_NAME,
    status: "healthy",
    environment: env.NODE_ENV,
    timestamp: new Date().toISOString(),
  });
});

app.get(`${API_BASE}/ready`, async (req, res) => {
  const startedAt = Date.now();
  try {
    const result = await getSupabase().from("institutions").select("id", { count: "exact", head: true });
    if (result.error) throw result.error;
    res.json({ success: true, status: "ready", dependencies: { database: "ready" }, latencyMs: Date.now() - startedAt, requestId: req.requestId });
  } catch {
    res.status(503).json({ success: false, status: "not_ready", dependencies: { database: "unavailable" }, requestId: req.requestId });
  }
});

app.get(`${API_BASE}/openapi.json`, (_req, res) => res.json(openApiDocument));

app.get(API_BASE, (_req, res) => {
  res.json({
    success: true,
    application: APP_NAME,
    apiVersion: "v1",
    status: "online",
    modules: [
      "authentication",
      "users",
      "roles",
      "institution-management",
      "applications",
      "admissions",
      "students",
      "academics",
      "finance",
      "human-resources",
      "operations",
      "procurement",
      "inventory",
      "assets",
      "hostel",
      "library",
      "examinations",
      "results",
      "research",
      "quality-assurance",
      "graduation",
      "alumni",
      "communications",
      "documents",
      "helpdesk",
      "audit",
    ],
  });
});

app.use(API_BASE, apiRouter);
app.use(API_BASE, institutionManagementRoutes);
app.use(API_BASE, studentManagementRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

export default app;
