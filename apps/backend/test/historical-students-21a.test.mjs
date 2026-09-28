import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "../../..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

test("historical student migration is additive and preserves institutional records", () => {
  const sql = read("supabase/migrations/202609270002_historical_students_cohorts_foundation.sql");
  for (const table of ["student_cohorts", "historical_import_batches", "historical_import_rows", "student_course_attempts"]) {
    assert.match(sql, new RegExp(`CREATE TABLE IF NOT EXISTS public\\.${table}`));
  }
  assert.match(sql, /generate_series\(2023, 2026\)/);
  assert.match(sql, /NORMAL_ADMISSION','HISTORICAL_IMPORT','MANUAL_ENTRY/);
  assert.match(sql, /historical_students\.rollback/);
  assert.doesNotMatch(sql, /DROP\s+TABLE|TRUNCATE|DELETE\s+FROM/i);
});

test("historical students remain separate from Admissions and require clean confirmation", () => {
  const route = read("apps/backend/src/modules/historical-students/historical-students.routes.ts");
  const index = read("apps/backend/src/routes/index.ts");
  assert.match(index, /router\.use\("\/historical-students", historicalStudentsRoutes\)/);
  assert.match(route, /batch\.status !== "READY"/);
  assert.match(route, /allExistingStudentNumbers/);
  assert.match(route, /MANUAL_ENTRY/);
  assert.match(route, /historical_students\.rollback/);
  assert.doesNotMatch(route, /admission_offers|applications|applicants/);
});

test("CSV parser supports quoted data and rejects unsafe file types", async () => {
  const { parseSpreadsheet } = await import("../dist/modules/historical-students/spreadsheet.js");
  const csv = 'studentNumber,firstName,lastName,cohortYear\r\n"IDMC/2023/00001","Jane, Mary",Doe,2023\r\n';
  const rows = parseSpreadsheet("students.csv", Buffer.from(csv).toString("base64"));
  assert.equal(rows.length, 1);
  assert.equal(rows[0].firstName, "Jane, Mary");
  assert.throws(() => parseSpreadsheet("students.exe", Buffer.from("unsafe").toString("base64")), /Only \.csv and \.xlsx/);
});

test("historical student workspace exposes validate-preview-confirm and reconciliation", () => {
  const html = read("apps/frontend/historical-students.html");
  const script = read("apps/frontend/assets/js/historical-students.js");
  const dashboard = read("apps/frontend/assets/js/dashboard.js");
  for (const step of ["Upload", "Validate", "Preview", "Fix errors", "Confirm", "Report"]) assert.match(html, new RegExp(step));
  assert.match(script, /\/historical-students\/quality/);
  assert.match(script, /\/historical-students\/imports/);
  assert.match(dashboard, /historical-students\.html/);
});
