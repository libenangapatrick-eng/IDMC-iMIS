import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "../../..");
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");

test("student authentication has a dedicated endpoint", () => {
  const routes = read("apps/backend/src/modules/auth/routes/auth.routes.ts");
  assert.match(routes, /router\.post\("\/student-login"/);
  const authService = read("apps/backend/src/modules/auth/services/auth.service.ts");
  const genericResolver = authService.slice(0, authService.indexOf("export async function login"));
  assert.doesNotMatch(genericResolver, /resolveStudentLoginEmail\(/);
});

test("student number has an exact institutional format", () => {
  const service = read("apps/backend/src/modules/auth/services/student-login.service.ts");
  assert.match(service, /\^IDMC\\\/\\d\{4\}\\\/\\d\{5\}\$/);
  assert.doesNotMatch(service, /Application Number ->/);
});

test("linked Supabase auth identity is authoritative", () => {
  const service = read("apps/backend/src/modules/auth/services/student-login.service.ts");
  assert.match(service, /auth\.admin\.getUserById/);
  assert.match(service, /auth_user_id, email, status/);
});

test("login form separates Student Access from Staff Access", () => {
  const html = read("apps/frontend/login.html");
  assert.match(html, /Student Access/);
  assert.match(html, /Staff Access/);
  assert.match(html, /IDMCAuth\.studentLogin/);
  assert.doesNotMatch(html, /Registration No\., Application No\. or Email/);
});

test("reconciliation preserves a dedicated student identity", () => {
  const script = read("apps/backend/scripts/reconcile-student-login.mjs");
  assert.match(script, /@students\.idmc\.local/);
  assert.match(script, /role_code.*STUDENT/s);
  assert.match(script, /signInWithPassword/);
  assert.doesNotMatch(script, /deleteUser/);
});
