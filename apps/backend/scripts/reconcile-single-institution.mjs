import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

const projectRoot = path.resolve(process.argv[2] || path.join(import.meta.dirname, "../../.."));
dotenv.config({ path: path.join(projectRoot, "apps", "backend", ".env") });
dotenv.config({ path: path.join(projectRoot, ".env") });

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) throw new Error("SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is missing.");

const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
const canonical = {
  institution_code: "IDMS",
  institution_name: "Institute of Development and Medical Sciences",
  short_name: "IDMS",
  status: "ACTIVE"
};
const tables = [
  "academic_calendar_events","academic_records","announcements","asset_categories","asset_maintenance","assets",
  "campuses","course_prerequisites","courses","dashboard_widgets","departments","documents","field_organizations",
  "helpdesk_categories","helpdesk_messages","helpdesk_tickets","hostel_fees","hostels","inventory_categories",
  "inventory_items","library_items","library_members","library_reservations","payroll_components","payroll_periods",
  "placement_sites","procurement_requests","programmes","purchase_orders","quality_actions","quality_reviews",
  "quality_standards","report_definitions","research_projects","schools","staff","staff_documents",
  "staff_leave_types","staff_lifecycle_events","students","suppliers","system_feature_flags",
  "system_maintenance_windows","system_number_sequences","system_settings","system_workflow_steps","system_workflows",
  "user_scopes"
];
const missingCodes = new Set(["42P01", "42703", "PGRST204", "PGRST205"]);

const { data: institutions, error: readError } = await db.from("institutions").select("*").order("created_at");
if (readError) throw readError;
let primary = institutions.find(x => String(x.institution_code).toUpperCase() === "IDMS");
if (!primary) {
  const { data, error } = await db.from("institutions").insert({ ...canonical, country: "Tanzania" }).select("*").single();
  if (error) throw error;
  primary = data;
}

const backupDirectory = path.join(projectRoot, "repair-backups");
fs.mkdirSync(backupDirectory, { recursive: true });
const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const backupPath = path.join(backupDirectory, `institutions-before-single-idms-${stamp}.json`);
fs.writeFileSync(backupPath, JSON.stringify({ captured_at: new Date().toISOString(), institutions }, null, 2));

const { error: canonicalError } = await db.from("institutions").update({ ...canonical, updated_at: new Date().toISOString() }).eq("id", primary.id);
if (canonicalError) throw canonicalError;
const extraIds = institutions.filter(x => x.id !== primary.id).map(x => x.id);

if (extraIds.length) {
  for (const table of tables) {
    const { error } = await db.from(table).update({ institution_id: primary.id }).in("institution_id", extraIds);
    if (error && !missingCodes.has(error.code)) {
      throw new Error(`Could not reassign ${table}: ${error.message}. No institution was deleted.`);
    }
  }
  const { error: deleteError } = await db.from("institutions").delete().in("id", extraIds);
  if (deleteError) throw new Error(`Could not delete duplicate institutions: ${deleteError.message}`);
}

const { data: verified, error: verifyError } = await db.from("institutions").select("id,institution_code,institution_name,status");
if (verifyError) throw verifyError;
if (verified.length !== 1 || verified[0].institution_code !== "IDMS") throw new Error("Final single-institution verification failed.");

console.log(JSON.stringify({ success: true, retained: verified[0], removed: extraIds.length, backup: backupPath }, null, 2));
