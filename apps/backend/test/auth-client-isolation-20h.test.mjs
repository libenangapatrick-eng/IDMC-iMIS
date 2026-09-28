import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "../../..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

test("end-user sign-in uses a disposable client and never mutates the admin database client", () => {
  const database = read("apps/backend/src/config/database.ts");
  const auth = read("apps/backend/src/modules/auth/services/auth.service.ts");

  assert.match(database, /export function createSupabaseAuthClient/);
  assert.match(database, /detectSessionInUrl: false/);
  assert.equal((auth.match(/authClient\.auth\.signInWithPassword/g) || []).length, 2);
  assert.doesNotMatch(auth, /supabase\.auth\.signInWithPassword/);
});
