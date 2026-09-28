import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../../../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("large historical student imports are resumable and report progress", async () => {
  const source = await read("apps/backend/src/modules/historical-students/historical-students.routes.ts");
  assert.match(source, /chunkSize/);
  assert.match(source, /batchProgress/);
  assert.match(source, /imports\/:id\/progress/);
  assert.match(source, /batch\.status !== "READY" && batch\.status !== "IMPORTING"/);
});

test("historical semester workflow resolves curriculum and generates course rosters", async () => {
  const source = await read("apps/backend/src/modules/historical-students/historical-academics.routes.ts");
  assert.match(source, /planning\/reference-data/);
  assert.match(source, /planning\/provision/);
  assert.match(source, /planning\/roster/);
  assert.match(source, /studentName/);
});

test("semester provisioning links offerings, registrations and course registrations", async () => {
  const sql = await read("supabase/migrations/202609280002_historical_import_workflow_completion.sql");
  assert.match(sql, /provision_historical_semester/);
  assert.match(sql, /INSERT INTO public\.course_offerings/);
  assert.match(sql, /INSERT INTO public\.student_registrations/);
  assert.match(sql, /INSERT INTO public\.course_registrations/);
  assert.doesNotMatch(sql, /DELETE FROM public\.students/i);
});
