import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "../../..");
const read = relative => fs.readFileSync(path.join(root, relative), "utf8");

test("Student Panel home uses the real self-service summary and institutional layout", () => {
    const page = read("apps/frontend/student-portal.html");
    const script = read("apps/frontend/assets/js/student-portal-home.js");
    const style = read("apps/frontend/assets/css/student-portal-home.css");

    assert.match(page, /<h1>Student Panel<\/h1>/);
    assert.doesNotMatch(page, /Student Self-Service/);
    assert.doesNotMatch(page, /Open Registration/);
    assert.doesNotMatch(page, /href="dashboard\.html"/);
    assert.match(page, /Latest Timetable/);
    assert.match(page, /Academic Profile/);
    assert.match(script, /\/students\/me\/summary/);
    assert.match(script, /panel\.programme/);
    assert.match(style, /--maroon:#641229/);
});

test("Student Panel summary supplies academic identity from linked records", () => {
    const routes = read("apps/backend/src/modules/student-management/students/student-self-service.routes.ts");

    for (const field of [
        "current_year", "last_login_at", "year_of_study", "stream",
        "entry_year", "intake", "session", "programme", "department",
        "school", "campus"
    ]) assert.match(routes, new RegExp(`${field}:`));
});
