import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

const projectRoot = path.resolve(process.argv[2] || path.join(import.meta.dirname, "../../.."));
const ownerEmail = String(process.argv[3] || "libenangapatrick@gmail.com").trim().toLowerCase();
if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(ownerEmail)) throw new Error("A valid owner email is required.");

dotenv.config({ path: path.join(projectRoot, "apps", "backend", ".env") });
dotenv.config({ path: path.join(projectRoot, ".env") });
const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) throw new Error("SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is missing.");

const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

async function listAuthUsers() {
  const all = [];
  for (let page = 1; page <= 100; page += 1) {
    const { data, error } = await db.auth.admin.listUsers({ page, perPage: 100 });
    if (error) throw error;
    all.push(...(data?.users || []));
    if ((data?.users || []).length < 100) break;
  }
  return all;
}

const authUsers = await listAuthUsers();
const authUser = authUsers.find((row) => String(row.email || "").toLowerCase() === ownerEmail);
if (!authUser) throw new Error(`Supabase Auth account ${ownerEmail} was not found.`);

const { data: byAuth, error: byAuthError } = await db.from("users").select("*").eq("auth_user_id", authUser.id).maybeSingle();
if (byAuthError) throw byAuthError;
const { data: byEmailRows, error: byEmailError } = await db.from("users").select("*").ilike("email", ownerEmail).limit(2);
if (byEmailError) throw byEmailError;
if ((byEmailRows || []).length > 1) throw new Error(`More than one public.users row uses ${ownerEmail}; automatic repair stopped safely.`);

const existing = byAuth || byEmailRows?.[0] || null;
const { data: role, error: roleError } = await db.from("roles").select("id,status").eq("role_code", "SUPER_ADMIN").maybeSingle();
if (roleError) throw roleError;
if (!role) throw new Error("SUPER_ADMIN role is missing.");

const backupDir = path.join(projectRoot, "repair-backups");
fs.mkdirSync(backupDir, { recursive: true });
const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const backupPath = path.join(backupDir, `owner-login-${stamp}.json`);
fs.writeFileSync(backupPath, JSON.stringify({
  captured_at: new Date().toISOString(),
  project_url: url,
  auth_user: { id: authUser.id, email: authUser.email, last_sign_in_at: authUser.last_sign_in_at },
  public_user: existing,
}, null, 2));

const meta = authUser.user_metadata || {};
const emailPrefix = ownerEmail.split("@")[0].replace(/[^a-z0-9]/gi, "").toLowerCase() || "owner";
const firstName = String(existing?.first_name || meta.first_name || meta.given_name || "Patrick").trim();
const lastName = String(existing?.last_name || meta.last_name || meta.family_name || "Libenanga").trim();
const userNumber = String(existing?.user_number || `ADMIN-${authUser.id.slice(0, 8).toUpperCase()}`);
const username = String(existing?.username || `${emailPrefix}-${authUser.id.slice(0, 6)}`).toLowerCase();

const profile = {
  auth_user_id: authUser.id,
  user_number: userNumber,
  username,
  first_name: firstName,
  middle_name: existing?.middle_name || null,
  last_name: lastName,
  display_name: existing?.display_name || [firstName, lastName].join(" "),
  email: ownerEmail,
  phone: existing?.phone || meta.phone || null,
  status: "ACTIVE",
  email_verified_at: existing?.email_verified_at || new Date().toISOString(),
  updated_at: new Date().toISOString(),
};

let publicUser;
if (existing) {
  const { data, error } = await db.from("users").update(profile).eq("id", existing.id).select("*").single();
  if (error) throw error;
  publicUser = data;
} else {
  const { data, error } = await db.from("users").insert(profile).select("*").single();
  if (error) throw error;
  publicUser = data;
}

const { error: assignmentError } = await db.from("user_roles").upsert({
  user_id: publicUser.id,
  role_id: role.id,
  status: "ACTIVE",
  expires_at: null,
}, { onConflict: "user_id,role_id" });
if (assignmentError) throw assignmentError;

/* SUPER_ADMIN must receive every active permission, including later modules. */
const { data: permissions, error: permissionsError } = await db.from("permissions").select("id").eq("status", "ACTIVE");
if (permissionsError) throw permissionsError;
if (permissions?.length) {
  const { error } = await db.from("role_permissions").upsert(
    permissions.map((permission) => ({ role_id: role.id, permission_id: permission.id })),
    { onConflict: "role_id,permission_id", ignoreDuplicates: true },
  );
  if (error) throw error;
}

/* Attach an existing HR staff record only when its email is an exact match. */
const { data: staffRows, error: staffError } = await db.from("staff").select("id,user_id,email").ilike("email", ownerEmail).limit(2);
if (staffError && !["42P01", "42703", "PGRST204", "PGRST205"].includes(staffError.code)) throw staffError;
if ((staffRows || []).length === 1) {
  const { error } = await db.from("staff").update({ user_id: publicUser.id, updated_at: new Date().toISOString() }).eq("id", staffRows[0].id);
  if (error) throw error;
}

const { data: verified, error: verifyError } = await db.from("users").select("id,auth_user_id,user_number,email,status").eq("auth_user_id", authUser.id).single();
if (verifyError) throw verifyError;
const { data: verifiedRole, error: verifiedRoleError } = await db.from("user_roles").select("status,roles!inner(role_code,status)").eq("user_id", verified.id).eq("status", "ACTIVE");
if (verifiedRoleError) throw verifiedRoleError;
const hasRole = (verifiedRole || []).some((row) => row.roles?.role_code === "SUPER_ADMIN" && row.roles?.status === "ACTIVE");
if (!hasRole) throw new Error("Final SUPER_ADMIN role verification failed.");

console.log(JSON.stringify({
  success: true,
  project_url: url,
  email: ownerEmail,
  public_user_id: verified.id,
  auth_user_id: verified.auth_user_id,
  public_status: verified.status,
  role: "SUPER_ADMIN",
  permissions: permissions?.length || 0,
  linkage_test: "PASS",
  backup: backupPath,
}, null, 2));
