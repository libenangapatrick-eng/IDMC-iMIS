import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = path => readFile(new URL(path, import.meta.url), "utf8");

test("backend has gzip, private cache policy and bounded keep-alive", async () => {
  const [app, middleware, server] = await Promise.all([
    source("../src/app.ts"),
    source("../src/middleware/performance.ts"),
    source("../src/server.ts"),
  ]);
  assert.match(app, /compressJson/);
  assert.match(middleware, /Content-Encoding/);
  assert.match(middleware, /private, max-age=5/);
  assert.match(server, /keepAliveTimeout = 65_000/);
});

test("API client deduplicates, caches and retries safe GET requests", async () => {
  const api = await source("../../frontend/assets/js/api.js");
  assert.match(api, /inFlightGets/);
  assert.match(api, /responseCache/);
  assert.match(api, /MAX_GET_ATTEMPTS = 3/);
  assert.match(api, /requestOptions\.method === "GET"/);
  assert.doesNotMatch(api, /new Error\(\s*"Internal server error"/);
});

test("student examination results use partial-data fallback and retry UI", async () => {
  const [route, frontend] = await Promise.all([
    source("../src/modules/student-self-service/student-results.routes.ts"),
    source("../../frontend/assets/js/student-exam-results.js"),
  ]);
  assert.match(route, /const warnings: string\[\] = \[\]/);
  assert.match(route, /warnings,/);
  assert.match(frontend, /retryResults/);
  assert.doesNotMatch(frontend, /Unable to load examination results/);
});

test("500 responses expose safe reference while logs retain the real error", async () => {
  const handler = await source("../src/middleware/errorHandler.ts");
  assert.match(handler, /Reference:/);
  assert.match(handler, /request_failed/);
  assert.match(handler, /42P01/);
  assert.match(handler, /42703/);
});
