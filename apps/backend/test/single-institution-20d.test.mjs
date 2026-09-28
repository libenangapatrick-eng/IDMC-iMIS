import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const projectRoot = path.resolve(import.meta.dirname, "../../..");
const read = relative => fs.readFileSync(path.join(projectRoot, relative), "utf8");

test("IDMS is enforced as the only institution across API and database", () => {
    const controller = read("apps/backend/src/modules/institution-management/institutions/institutions.controller.ts");
    const service = read("apps/backend/src/modules/institution-management/institutions/institutions.service.ts");
    const middleware = read("apps/backend/src/modules/institution-management/shared/single-institution.ts");
    const migration = read("supabase/migrations/202609270001_single_institution_idms.sql");

    assert.match(controller, /locked to one institution/);
    assert.match(service, /PRIMARY_INSTITUTION_CODE/);
    assert.match(middleware, /Institute of Development and Medical Sciences/);
    assert.match(migration, /delete from public\.institutions where id <> primary_id/i);
    assert.match(migration, /idmc_bind_primary_institution/);
});

test("institution UI is singular and contains one integrated structure workspace", () => {
    const page = read("apps/frontend/institutions.html");
    const script = read("apps/frontend/assets/js/institution-workspace.js");
    const dashboard = read("apps/frontend/assets/js/dashboard.js");

    assert.match(page, /<h1>Institution<\/h1>/);
    assert.doesNotMatch(page, /Add Institution/);
    assert.match(page, /readonly aria-readonly="true"/);
    assert.match(page, /data-tab="campuses"/);
    assert.match(page, /data-tab="schools"/);
    assert.match(page, /data-tab="departments"/);
    assert.match(script, /\/institutions\/primary\/structure/);
    assert.match(script, /kind==="campus"\?"campuses"/);
    assert.match(dashboard, /title: "Institution"/);
});
