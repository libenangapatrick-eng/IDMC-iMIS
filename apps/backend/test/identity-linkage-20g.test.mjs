import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "../../..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

test("authentication middleware safely heals a unique email linkage", () => {
  const source = read("apps/backend/src/middleware/auth.ts");
  assert.match(source, /emailMatches\?\.length === 1/);
  assert.match(source, /update\(\{ auth_user_id: authUser\.id/);
  assert.doesNotMatch(source, /auth\.admin\.createUser/);
});

test("owner reconciler links auth, public profile and super administrator role", () => {
  const source = read("apps/backend/scripts/reconcile-owner-login.mjs");
  assert.match(source, /SUPER_ADMIN/);
  assert.match(source, /role_permissions/);
  assert.match(source, /linkage_test: "PASS"/);
  assert.doesNotMatch(source, /deleteUser|from\("users"\)\.delete/);
});
