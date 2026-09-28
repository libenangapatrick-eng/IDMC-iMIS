import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "../../..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

test("21B migration is additive and preserves each academic attempt", () => {
  const sql = read("supabase/migrations/202609270003_historical_academic_records_lifecycle.sql");
  assert.match(sql, /historical_academic_import_batches/);
  assert.match(sql, /historical_academic_import_rows/);
  assert.match(sql, /student_academic_lifecycle_v/);
  assert.match(sql, /confirmed_by <> created_by/);
  assert.match(sql, /historical_academics\.rollback/);
  assert.doesNotMatch(sql, /DROP\s+TABLE|TRUNCATE|DELETE\s+FROM/i);
});

test("historical academic imports validate curriculum, attempts and four-eyes approval", () => {
  const source = read("apps/backend/src/modules/historical-students/historical-academics.routes.ts");
  const index = read("apps/backend/src/routes/index.ts");
  for (const contract of ["COURSE_NOT_IN_STUDENT_CURRICULUM", "DUPLICATE_COURSE_ATTEMPT", "GRADE_DOES_NOT_MATCH_TOTAL", "Four-eyes control"]) {
    assert.match(source, new RegExp(contract));
  }
  assert.match(source, /recalculateStudent/);
  assert.match(source, /HISTORICAL-1\.0/);
  assert.match(index, /historical-academics/);
});

test("Student Results merges only historical attempts that have no official course result", () => {
  const source = read("apps/backend/src/modules/student-self-service/student-results.routes.ts");
  assert.match(source, /student_course_attempts/);
  assert.match(source, /\.is\("course_result_id", null\)/);
  assert.match(source, /historical_course_id/);
});

test("21B workspace includes import approval and lifecycle reporting", () => {
  const html = read("apps/frontend/historical-academics.html");
  const script = read("apps/frontend/assets/js/historical-academics.js");
  const dashboard = read("apps/frontend/assets/js/dashboard.js");
  assert.match(html, /Academic Import/);
  assert.match(html, /Student Academic Lifecycle Report/);
  assert.match(script, /historical-academics\/lifecycle-detail/);
  assert.match(script, /Confirm as second officer/);
  assert.match(dashboard, /historical-academics\.html/);
});
