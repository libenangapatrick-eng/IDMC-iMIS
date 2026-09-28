import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../../../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("staff access accepts mixed-role staff accounts and blocks student-only accounts", async () => {
  const login = await read("apps/frontend/login.html");
  assert.match(login, /hasStaffRole/);
  assert.match(login, /isStudentOnly/);
  assert.match(login, /accessMode === "staff" && isStudentOnly/);
});

test("student management exposes authorized activation without granting it to lecturers", async () => {
  const page = await read("apps/frontend/students.html");
  const workflow = await read("apps/backend/src/modules/workflows/workflow.routes.ts");
  const roles = await read("supabase/migrations/202609210029_staff_role_workspaces.sql");
  assert.match(page, /data-activate/);
  assert.match(page, /can\("students\.activate"\)/);
  assert.match(workflow, /requirePermission\("students\.activate"\)/);
  assert.match(roles, /and r\.role_code='LECTURER'[\s\S]*'students\.activate'/);
});

test("pending students cannot create a portal account before staff activation", async () => {
  const login = await read("apps/backend/src/modules/auth/services/student-login.service.ts");
  assert.match(login, /BLOCKED_STUDENT_STATUSES[\s\S]*"PENDING_ACTIVATION"/);
});

test("student workspace includes programme, cohort, account and lifecycle summary", async () => {
  const service = await read("apps/backend/src/modules/student-management/students/students.service.ts");
  const page = await read("apps/frontend/students.html");
  assert.match(service, /programmes\(programme_code, programme_name\)/);
  assert.match(service, /student_cohorts\(cohort_code, cohort_name, entry_year\)/);
  assert.match(service, /getStudentsSummary/);
  assert.match(page, /Portal Accounts Linked/);
  assert.match(page, /Programme \/ Cohort/);
});
