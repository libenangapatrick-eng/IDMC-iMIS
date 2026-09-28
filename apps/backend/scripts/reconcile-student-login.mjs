import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

const projectRoot = path.resolve(process.argv[2] || path.join(import.meta.dirname, "../../.."));
const studentNumber = String(process.argv[3] || "IDMC/2026/00001").trim().toUpperCase();

if (!/^IDMC\/\d{4}\/\d{5}$/.test(studentNumber)) {
  throw new Error("Student Number must use the format IDMC/YYYY/NNNNN.");
}

dotenv.config({ path: path.join(projectRoot, "apps", "backend", ".env") });
dotenv.config({ path: path.join(projectRoot, ".env") });

const url = process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !serviceKey) {
  throw new Error("SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is missing from apps/backend/.env.");
}

const admin = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
});

const internalEmail = `${studentNumber.replace(/[^a-z0-9]/gi, "").toLowerCase()}@students.idmc.local`;
const username = studentNumber.toLowerCase();

async function listAllAuthUsers() {
  const users = [];
  for (let page = 1; page <= 100; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 100 });
    if (error) throw error;
    const batch = data?.users || [];
    users.push(...batch);
    if (batch.length < 100) break;
  }
  return users;
}

const { data: student, error: studentError } = await admin
  .from("students")
  .select("id,student_number,user_id,student_status,first_name,middle_name,last_name,email,phone")
  .eq("student_number", studentNumber)
  .maybeSingle();

if (studentError) throw studentError;
if (!student) throw new Error(`Student ${studentNumber} does not exist in public.students.`);

const blocked = new Set(["SUSPENDED", "WITHDRAWN", "EXPELLED", "DECEASED", "INACTIVE"]);
if (blocked.has(String(student.student_status || "").toUpperCase())) {
  throw new Error(`Student ${studentNumber} has blocked status ${student.student_status}.`);
}

const authUsers = await listAllAuthUsers();
let authUser = authUsers.find((item) => String(item.email || "").toLowerCase() === internalEmail);

const { data: linkedPublicUser, error: linkedError } = student.user_id
  ? await admin.from("users").select("*").eq("id", student.user_id).maybeSingle()
  : { data: null, error: null };
if (linkedError) throw linkedError;

const { data: numberPublicUser, error: numberError } = await admin
  .from("users")
  .select("*")
  .eq("user_number", studentNumber)
  .maybeSingle();
if (numberError) throw numberError;

const { data: authPublicUser, error: authPublicError } = authUser
  ? await admin.from("users").select("*").eq("auth_user_id", authUser.id).maybeSingle()
  : { data: null, error: null };
if (authPublicError) throw authPublicError;

const { data: studentRole, error: roleError } = await admin
  .from("roles")
  .select("id,role_code,status")
  .eq("role_code", "STUDENT")
  .maybeSingle();
if (roleError) throw roleError;
if (!studentRole) throw new Error("The STUDENT role is missing from public.roles.");

const backupDirectory = path.join(projectRoot, "repair-backups");
fs.mkdirSync(backupDirectory, { recursive: true });
const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const backupPath = path.join(backupDirectory, `student-login-${studentNumber.replaceAll("/", "-")}-${stamp}.json`);
fs.writeFileSync(backupPath, JSON.stringify({
  captured_at: new Date().toISOString(),
  student,
  linked_public_user: linkedPublicUser,
  number_public_user: numberPublicUser,
  auth_public_user: authPublicUser,
  internal_auth_user: authUser ? {
    id: authUser.id,
    email: authUser.email,
    created_at: authUser.created_at,
    last_sign_in_at: authUser.last_sign_in_at,
  } : null,
}, null, 2));

const firstName = String(student.first_name || linkedPublicUser?.first_name || "Student").trim();
const middleName = String(student.middle_name || linkedPublicUser?.middle_name || "").trim() || null;
const lastName = String(student.last_name || linkedPublicUser?.last_name || studentNumber).trim();
const displayName = [firstName, middleName, lastName].filter(Boolean).join(" ");

if (!authUser) {
  const { data, error } = await admin.auth.admin.createUser({
    email: internalEmail,
    password: studentNumber,
    email_confirm: true,
    user_metadata: { student_number: studentNumber, display_name: displayName, account_type: "STUDENT" },
  });
  if (error || !data?.user) throw error || new Error("Could not create the student authentication account.");
  authUser = data.user;
} else {
  const { data, error } = await admin.auth.admin.updateUserById(authUser.id, {
    email: internalEmail,
    password: studentNumber,
    email_confirm: true,
    user_metadata: {
      ...(authUser.user_metadata || {}),
      student_number: studentNumber,
      display_name: displayName,
      account_type: "STUDENT",
    },
  });
  if (error || !data?.user) throw error || new Error("Could not synchronise the student authentication account.");
  authUser = data.user;
}

let publicUser = authPublicUser || numberPublicUser;

/* Resolve an old duplicate Student Number without deleting any identity. */
if (authPublicUser && numberPublicUser && authPublicUser.id !== numberPublicUser.id) {
  const legacySuffix = String(numberPublicUser.id).slice(0, 8);
  const { error } = await admin.from("users").update({
    user_number: `LEGACY-${legacySuffix}`,
    username: null,
    status: numberPublicUser.id === linkedPublicUser?.id ? "INACTIVE" : numberPublicUser.status,
  }).eq("id", numberPublicUser.id);
  if (error) throw new Error(`Could not preserve the duplicate legacy profile: ${error.message}`);
  publicUser = authPublicUser;
}

const profile = {
  auth_user_id: authUser.id,
  user_number: studentNumber,
  username,
  first_name: firstName,
  middle_name: middleName,
  last_name: lastName,
  display_name: displayName,
  email: internalEmail,
  phone: student.phone || linkedPublicUser?.phone || null,
  status: "ACTIVE",
  email_verified_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
};

if (publicUser) {
  const { data, error } = await admin.from("users").update(profile).eq("id", publicUser.id).select("*").single();
  if (error) throw error;
  publicUser = data;
} else {
  const { data, error } = await admin.from("users").insert(profile).select("*").single();
  if (error) throw error;
  publicUser = data;
}

const { error: roleAssignmentError } = await admin.from("user_roles").upsert({
  user_id: publicUser.id,
  role_id: studentRole.id,
  status: "ACTIVE",
  expires_at: null,
}, { onConflict: "user_id,role_id" });
if (roleAssignmentError) throw roleAssignmentError;

const { error: linkError } = await admin.from("students").update({
  user_id: publicUser.id,
  updated_at: new Date().toISOString(),
}).eq("id", student.id);
if (linkError) throw linkError;

/* End-to-end credential verification without revealing the internal email. */
const verifier = createClient(url, process.env.SUPABASE_ANON_KEY || serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
});
const { data: signIn, error: signInError } = await verifier.auth.signInWithPassword({
  email: internalEmail,
  password: studentNumber,
});
if (signInError || !signIn?.session) {
  throw new Error(`Credential verification failed: ${signInError?.message || "no session returned"}`);
}
await verifier.auth.signOut();

const { data: finalRoles, error: finalRolesError } = await admin
  .from("user_roles")
  .select("status,roles!inner(role_code,status)")
  .eq("user_id", publicUser.id)
  .eq("status", "ACTIVE");
if (finalRolesError) throw finalRolesError;

const hasStudentRole = (finalRoles || []).some((row) => row.roles?.role_code === "STUDENT" && row.roles?.status === "ACTIVE");
if (!hasStudentRole) throw new Error("Final STUDENT role verification failed.");

console.log(JSON.stringify({
  success: true,
  student_number: studentNumber,
  student_status: student.student_status,
  public_user_id: publicUser.id,
  auth_user_id: authUser.id,
  role: "STUDENT",
  credential_test: "PASS",
  backup: backupPath,
}, null, 2));
