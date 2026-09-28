import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const backend = new URL("../src/", import.meta.url);
const frontend = new URL("../../frontend/", import.meta.url);

test("institutional development is mounted and finance/payroll collection routes exist", async () => {
  const index = await readFile(new URL("routes/index.ts", backend), "utf8");
  const finance = await readFile(new URL("modules/finance/routes/finance.routes.ts", backend), "utf8");
  const hr = await readFile(new URL("modules/hr/hr.routes.ts", backend), "utf8");
  assert.match(index, /institutional-development/);
  for (const route of ["charges", "invoices", "payments", "scholarships", "refunds"]) assert.match(finance, new RegExp(`/${route}`));
  for (const route of ["periods", "components", "entries", "lines"]) assert.match(hr, new RegExp(`/payroll/${route}`));
});

test("academic reference endpoint supplies examination semester choices", async () => {
  const source = await readFile(new URL("modules/academic-core/academic-core.routes.ts", backend), "utf8");
  const workspace = await readFile(new URL("assets/js/institutional-workspace.js", frontend), "utf8");
  assert.match(source, /router\.get\("\/reference-data"/);
  assert.match(source, /semesters:"semesters"/);
  assert.match(workspace, /reference-data\?resource=semesters/);
});

test("repaired administration pages use modern workspaces", async () => {
  for (const name of ["finance.html", "hr.html", "payroll.html", "research.html", "hostel.html", "clinical-placement.html", "field-practical.html"]) {
    const html = await readFile(new URL(name, frontend), "utf8");
    assert.match(html, /institutional-workspace\.js/);
    assert.doesNotMatch(html, /Module Workspace|currently exposed as read-only|idmc-resource-page\.js/);
  }
});

test("finance sub-pages route to named modern workspace tabs", async () => {
  const pages = { "fee-structures.html":"feeStructures", "charges.html":"charges", "invoices.html":"invoices", "payments.html":"payments", "scholarships.html":"scholarships", "refunds.html":"refunds" };
  for (const [name, resource] of Object.entries(pages)) {
    const html = await readFile(new URL(name, frontend), "utf8");
    assert.match(html, new RegExp(`finance\\.html\\?resource=${resource}`));
  }
});
