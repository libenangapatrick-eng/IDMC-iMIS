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

const app = express();

app.disable("x-powered-by");

app.use(
  helmet({
    crossOriginResourcePolicy: false,
  })
);

app.use(
  cors({
    origin: env.CORS_ORIGIN === "*" ? true : env.CORS_ORIGIN,
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
      "payroll",
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
      "clinical-placement",
      "field-practical",
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
