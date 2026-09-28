import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { runInNewContext } from "node:vm";

const project = resolve(import.meta.dirname, "../../..");
const read = relative => readFileSync(resolve(project, relative), "utf8");

test("frontend API config derives its target at runtime", () => {
  const config = read("apps/frontend/assets/js/config.js");
  assert.doesNotMatch(config, /API_BASE_URL\s*:\s*["']http:\/\//);
  assert.match(config, /__IDMC_RUNTIME_CONFIG__/);
  assert.match(config, /window\.location\.origin/);
});

test("runtime API defaults to port 4000 locally and same-origin in deployment", () => {
  const source = read("apps/frontend/assets/js/config.js");
  const execute = location => {
    const window = { location, IDMC_CONFIG: undefined, __IDMC_RUNTIME_CONFIG__: undefined };
    runInNewContext(source, { window, document: { querySelector() { return null; } }, Set });
    return window.IDMC_CONFIG.API_BASE_URL;
  };
  assert.equal(execute({ protocol: "http:", hostname: "127.0.0.1", port: "5500", origin: "http://127.0.0.1:5500" }), "http://127.0.0.1:4000/api/v1");
  assert.equal(execute({ protocol: "https:", hostname: "imis.example.ac.tz", port: "", origin: "https://imis.example.ac.tz" }), "https://imis.example.ac.tz/api/v1");
});

test("login route is served by the deterministic frontend server", () => {
  const login = read("apps/frontend/login.html");
  const frontendServer = read("apps/frontend/server.mjs");
  const starter = read("Start-IDMC.ps1");

  assert.match(login, /<base href="\/">/);
  assert.match(login, /id="loginForm"/);
  assert.match(frontendServer, /pathname === "\/login"/);
  assert.match(frontendServer, /pathname === "\/login\/"/);
  assert.match(starter, /node server\.mjs/);
  assert.match(starter, /loginForm/);
  assert.doesNotMatch(starter, /npx --yes live-server/);
});

test("applicant forms use the shared API configuration", () => {
  assert.match(read("apps/frontend/assets/js/applicant-live-forms.js"), /IDMC_CONFIG\?\.API_BASE_URL/);
});

test("distribution has an environment template and ignores real environments", () => {
  assert.equal(existsSync(resolve(project, "apps/backend/.env.example")), true);
  assert.match(read(".gitignore"), /\.env/);
});

test("student ownership, scoped aliases and callback contracts are mounted", () => {
  const routes = read("apps/backend/src/routes/index.ts");
  assert.match(routes, /scopedAliasPrefix\("\/procurement"\)/);
  assert.match(routes, /router\.use\("\/self-service"/);
  assert.match(routes, /router\.use\("\/payment-provider"/);
  assert.match(read("apps/backend/src/modules/student-management/students/student-self-service.routes.ts"), /requirePermission\("students\.self\.view"\)/);
});
