import { APP_NAME, API_BASE } from "./constants.js";

export const openApiDocument = {
  openapi: "3.1.0",
  info: { title: `${APP_NAME} API`, version: "1.0.0", description: "Core API contract; generated route inventory is shipped in docs/api." },
  servers: [{ url: API_BASE }],
  components: { securitySchemes: { bearerAuth: { type: "http", scheme: "bearer", bearerFormat: "JWT" } } },
  paths: {
    "/health": { get: { summary: "Liveness check", responses: { "200": { description: "Alive" } } } },
    "/ready": { get: { summary: "Dependency readiness", responses: { "200": { description: "Ready" }, "503": { description: "Dependency unavailable" } } } },
    "/auth/login": { post: { summary: "Sign in", responses: { "200": { description: "Session" }, "401": { description: "Invalid credentials" }, "429": { description: "Rate limited" } } } },
    "/auth/me": { get: { summary: "Current identity", security: [{ bearerAuth: [] }], responses: { "200": { description: "Identity" } } } },
    "/students/me/summary": { get: { summary: "Student dashboard", security: [{ bearerAuth: [] }], responses: { "200": { description: "Summary" } } } },
    "/student-results/me": { get: { summary: "Published examination results", security: [{ bearerAuth: [] }], responses: { "200": { description: "Results" } } } },
    "/self-service/student/registration": { get: { summary: "Own registration", security: [{ bearerAuth: [] }], responses: { "200": { description: "Registration" } } } },
    "/payment-provider/callback": { post: { summary: "Provider event", parameters: [{ in: "header", name: "X-IDMC-Provider-Secret", required: true, schema: { type: "string" } }], responses: { "200": { description: "Processed" }, "401": { description: "Invalid credential" } } } },
  },
} as const;
