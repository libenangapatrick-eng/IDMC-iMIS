import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const route = await readFile(new URL("../src/modules/finance/routes/finance-workflow.routes.ts", import.meta.url), "utf8");
const mount = await readFile(new URL("../src/modules/finance/routes/finance.routes.ts", import.meta.url), "utf8");
const migration = await readFile(new URL("../../../supabase/migrations/202609280006_finance_portal_complete_workflow.sql", import.meta.url), "utf8");

test("finance workflow router is mounted behind authenticated finance routes", () => {
  assert.match(mount, /router\.use\("\/workflow", financeWorkflowRoutes\)/);
});

test("student payment confirmation requires an uploaded receipt", () => {
  assert.match(route, /request_status !== "RECEIPT_UPLOADED"/);
  assert.match(route, /refresh_student_financial_account/);
});

test("expense workflow preserves finance and executive separation", () => {
  assert.match(route, /finance\.expenses\.review/);
  assert.match(route, /finance\.expenses\.approve/);
  assert.match(route, /FINANCE_REVIEWED/);
  assert.match(route, /PRINCIPAL_APPROVED/);
});

test("migration is additive and seeds the official fee catalogue", () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.institutional_fee_catalog/i);
  assert.match(migration, /Tuition Fee - Certificate/);
  assert.match(migration, /650000,1300000/);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.finance_expense_requests/i);
});
