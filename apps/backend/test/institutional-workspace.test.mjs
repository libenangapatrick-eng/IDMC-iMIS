import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const frontend = new URL("../../frontend/", import.meta.url);

test("institutional pages use the dedicated workspace instead of generic CRUD", async () => {
  for (const name of ["library.html", "alumni.html", "graduation.html", "transcripts.html", "attendance.html", "examinations.html", "timetable.html", "academics/academics.html"]) {
    const html = await readFile(new URL(name, frontend), "utf8");
    assert.match(html, /institutional-workspace\.js/);
    assert.doesNotMatch(html, /Module Workspace|currently exposed as read-only|module-crud/);
  }
});

test("Admissions separates active, ready and completed application queues", async () => {
  const html = await readFile(new URL("admissions.html", frontend), "utf8");
  const script = await readFile(new URL("assets/js/admissions-workspace.js", frontend), "utf8");
  assert.match(html, /Pending Work/);
  assert.match(html, /Completed \/ Converted/);
  assert.match(html, /Repair Student Links/);
  assert.match(script, /CONVERTED_TO_STUDENT/);
  assert.match(script, /reconcile-converted/);
});
