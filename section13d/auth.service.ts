import {
  createLoginClient,
  getSupabase,
} from "../../../config/database.js";
import { resolveStudentLoginEmail } from "./student-login.service.js";

function normaliseIdentifier(value: string): string {
  return String(value ?? "").trim();
}

async function resolveLoginEmail(
  identifier: string,
  password = ""
): Promise<string> {
  const supabase = getSupabase();
  const value = normaliseIdentifier(identifier);

  if (!value) {
    throw new Error("Email, username or student number is required");
  }

  if (value.includes("@")) {
    return value.toLowerCase();
  }

  // Students sign in with Registration Number or Application Number.
  const studentEmail = await resolveStudentLoginEmail(value, password);

  if (studentEmail) {
    return studentEmail;
  }

  const { data: usernameUser, error: usernameError } = await supabase
    .from("users")
    .select("id, email, status")
    .ilike("username", value)
    .maybeSingle();

  if (usernameError) throw usernameError;

  if (usernameUser) {
    if (usernameUser.status !== "ACTIVE") {
      throw new Error(`User account is ${usernameUser.status}`);
    }
    return String(usernameUser.email).toLowerCase();
  }

  const { data: numberedUser, error: numberError } = await supabase
    .from("users")
    .select("id, email, status")
    .ilike("user_number", value)
    .maybeSingle();

  if (numberError) throw numberError;

  if (numberedUser) {
    if (numberedUser.status !== "ACTIVE") {
      throw new Error(`User account is ${numberedUser.status}`);
    }
    return String(numberedUser.email).toLowerCase();
  }

  const { data: student, error: studentError } = await supabase
    .from("students")
    .select("user_id")
    .ilike("student_number", value)
    .maybeSingle();

  if (studentError) throw studentError;

  if (student?.user_id) {
    const { data: studentUser, error: studentUserError } = await supabase
      .from("users")
      .select("email, status")
      .eq("id", student.user_id)
      .maybeSingle();

    if (studentUserError) throw studentUserError;
    if (studentUser) {
      if (studentUser.status !== "ACTIVE") {
        throw new Error(`User account is ${studentUser.status}`);
      }
      return String(studentUser.email).toLowerCase();
    }
  }

  throw new Error("Invalid login credentials");
}

export type LoginAccountType = "AUTO" | "STAFF" | "STUDENT";

async function enforceAccountType(
  authUserId: string,
  accountType: LoginAccountType
): Promise<void> {
  if (accountType === "AUTO") return;

  const supabase = getSupabase();
  const { data: applicationUser, error: userError } = await supabase
    .from("users")
    .select("id, status")
    .eq("auth_user_id", authUserId)
    .maybeSingle();

  if (userError) throw userError;
  if (!applicationUser || applicationUser.status !== "ACTIVE") {
    throw new Error("Invalid login credentials");
  }

  const { data: assignments, error: roleError } = await supabase
    .from("user_roles")
    .select("status, expires_at, roles!inner(role_code, status)")
    .eq("user_id", applicationUser.id)
    .eq("status", "ACTIVE");

  if (roleError) throw roleError;

  const now = Date.now();
  const roleCodes = (assignments ?? [])
    .filter((assignment: any) =>
      assignment.roles?.status === "ACTIVE" &&
      (!assignment.expires_at || new Date(assignment.expires_at).getTime() > now)
    )
    .map((assignment: any) => String(assignment.roles.role_code));

  if (accountType === "STUDENT") {
    const { data: linkedStudent, error: studentError } = await supabase
      .from("students")
      .select("id")
      .eq("user_id", applicationUser.id)
      .limit(1)
      .maybeSingle();

    if (studentError) throw studentError;
    if (!roleCodes.includes("STUDENT") || !linkedStudent) {
      throw new Error("Invalid login credentials");
    }
    return;
  }

  /* Staff/Admin identities must have at least one non-student role. */
  if (!roleCodes.some((roleCode) => roleCode !== "STUDENT")) {
    throw new Error("Invalid login credentials");
  }
}

export async function login(
  identifier: string,
  password: string,
  accountType: LoginAccountType = "AUTO"
) {
  if (!String(password ?? "")) {
    throw new Error("Password is required");
  }

  const supabase = createLoginClient();
  const email = await resolveLoginEmail(identifier, String(password));
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password: String(password),
  });

  if (error || !data.session || !data.user) {
    throw new Error("Invalid login credentials");
  }

  await enforceAccountType(data.user.id, accountType);

  return {
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token,
    expires_at: data.session.expires_at,
    expires_in: data.session.expires_in,
    token_type: data.session.token_type,
  };
}

export async function getCurrentUser(userId: string) {
  const supabase = getSupabase();

  const { data: user, error: userError } = await supabase
    .from("users")
    .select(`
      id,
      auth_user_id,
      user_number,
      username,
      first_name,
      middle_name,
      last_name,
      display_name,
      email,
      phone,
      profile_photo_url,
      status,
      last_login_at,
      password_changed_at,
      email_verified_at,
      phone_verified_at,
      created_at,
      updated_at
    `)
    .eq("id", userId)
    .maybeSingle();

  if (userError) throw userError;
  if (!user) throw new Error("IDMC user account was not found");

  const { data: userRoles, error: rolesError } = await supabase
    .from("user_roles")
    .select(`
      id,
      status,
      assigned_at,
      expires_at,
      roles!inner (
        id,
        role_code,
        role_name,
        description,
        status
      )
    `)
    .eq("user_id", userId)
    .eq("status", "ACTIVE");

  if (rolesError) throw rolesError;

  const now = new Date();
  const roles = (userRoles ?? [])
    .filter((item: any) =>
      item.status === "ACTIVE" &&
      item.roles?.status === "ACTIVE" &&
      (!item.expires_at || new Date(item.expires_at) > now)
    )
    .map((item: any) => ({
      id: item.roles.id,
      roleCode: item.roles.role_code,
      roleName: item.roles.role_name,
      description: item.roles.description,
      assignedAt: item.assigned_at,
      expiresAt: item.expires_at,
    }));

  const permissionSet = new Set<string>();
  for (const role of roles) {
    const { data: rolePermissions, error: permissionError } = await supabase
      .from("role_permissions")
      .select(`
        permissions!inner (
          permission_code,
          status
        )
      `)
      .eq("role_id", role.id);

    if (permissionError) throw permissionError;

    for (const item of rolePermissions ?? []) {
      const permission = item.permissions as any;
      if (permission?.status === "ACTIVE") {
        permissionSet.add(permission.permission_code);
      }
    }
  }

  return {
    user: {
      id: user.id,
      authUserId: user.auth_user_id,
      userNumber: user.user_number,
      username: user.username,
      firstName: user.first_name,
      middleName: user.middle_name,
      lastName: user.last_name,
      displayName: user.display_name,
      email: user.email,
      phone: user.phone,
      profilePhotoUrl: user.profile_photo_url,
      status: user.status,
      lastLoginAt: user.last_login_at,
      passwordChangedAt: user.password_changed_at,
      emailVerifiedAt: user.email_verified_at,
      phoneVerifiedAt: user.phone_verified_at,
      createdAt: user.created_at,
      updatedAt: user.updated_at,
    },
    roles,
    permissions: Array.from(permissionSet).sort(),
  };
}

export async function getUserByAuthUserId(authUserId: string) {
  const supabase = getSupabase();
  const { data, error } = await supabase
    .from("users")
    .select(`
      id,
      auth_user_id,
      user_number,
      username,
      first_name,
      middle_name,
      last_name,
      display_name,
      email,
      phone,
      status,
      created_at,
      updated_at
    `)
    .eq("auth_user_id", authUserId)
    .maybeSingle();

  if (error) throw error;
  return data;
}
