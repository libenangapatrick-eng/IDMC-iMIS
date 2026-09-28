import test from "node:test";
import assert from "node:assert/strict";
import { parseAllowedOrigins, isOriginAllowed, assertSafeProductionOrigins } from "../dist/config/cors.js";
import { parseBearerToken, rolesGrantPermission, rolesGrantRole } from "../dist/utils/security.js";
import { sanitizeLogData } from "../dist/utils/logger.js";

test("bearer parser accepts one token and rejects malformed headers", () => {
  assert.equal(parseBearerToken("Bearer abc.def.ghi"), "abc.def.ghi");
  assert.equal(parseBearerToken("bearer token"), "token");
  assert.equal(parseBearerToken("Basic token"), null);
  assert.equal(parseBearerToken("Bearer token extra"), null);
});

test("permission and role checks reject expired or inactive assignments", () => {
  const now = new Date("2026-09-26T12:00:00Z");
  const active = [{ status: "ACTIVE", expires_at: "2026-09-27T12:00:00Z", roles: { status: "ACTIVE", role_code: "STUDENT", role_permissions: [{ permissions: { status: "ACTIVE", permission_code: "students.self.view" } }] } }];
  assert.equal(rolesGrantPermission(active, "students.self.view", now), true);
  assert.equal(rolesGrantRole(active, ["STUDENT"], now), true);
  assert.equal(rolesGrantPermission([{ ...active[0], expires_at: "2026-09-25T12:00:00Z" }], "students.self.view", now), false);
  assert.equal(rolesGrantPermission([{ ...active[0], status: "INACTIVE" }], "students.self.view", now), false);
  assert.equal(rolesGrantPermission(active, "finance.manage", now), false);
});

test("CORS uses an exact allowlist and production requires HTTPS", () => {
  const origins = parseAllowedOrigins("https://imis.example.ac.tz, https://admin.example.ac.tz/");
  assert.deepEqual(origins, ["https://imis.example.ac.tz", "https://admin.example.ac.tz"]);
  assert.equal(isOriginAllowed("https://imis.example.ac.tz", origins), true);
  assert.equal(isOriginAllowed("https://evil.example", origins), false);
  assert.throws(() => assertSafeProductionOrigins("production", ["*"]));
  assert.throws(() => assertSafeProductionOrigins("production", ["http://imis.example.ac.tz"]));
  assert.doesNotThrow(() => assertSafeProductionOrigins("production", ["https://imis.example.ac.tz"]));
});

test("structured logs redact secrets recursively", () => {
  assert.deepEqual(sanitizeLogData({ email: "user@example.test", password: "hidden", nested: { accessToken: "hidden" } }), { email: "user@example.test", password: "[REDACTED]", nested: { accessToken: "[REDACTED]" } });
});
