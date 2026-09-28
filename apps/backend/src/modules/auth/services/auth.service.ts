import {
  createSupabaseAuthClient,
  getSupabase,
} from "../../../config/database.js";
import {
  isValidStudentNumber,
  normaliseStudentNumber,
  resolveStudentLoginEmail,
} from "./student-login.service.js";

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

  throw new Error("Invalid login credentials");
}

export async function login(identifier: string, password: string) {
  if (!String(password ?? "")) {
    throw new Error("Password is required");
  }

  const supabase = getSupabase();
  const authClient = createSupabaseAuthClient();
  const email = await resolveLoginEmail(identifier, String(password));
  const { data, error } = await authClient.auth.signInWithPassword({
    email,
    password: String(password),
  });

  if (error || !data.session) {
    throw new Error("Invalid login credentials");
  }

  // Keep the portal's Last Login information current without blocking sign-in
  // if the audit timestamp cannot be written.
  const { error: lastLoginError } = await supabase
    .from("users")
    .update({ last_login_at: new Date().toISOString() })
    .eq("auth_user_id", data.user.id);
  if (lastLoginError) {
    console.warn("Unable to update last_login_at", lastLoginError.message);
  }

  return {
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token,
    expires_at: data.session.expires_at,
    expires_in: data.session.expires_in,
    token_type: data.session.token_type,
  };
}

export async function studentLogin(studentNumber: string, password: string) {
  const number = normaliseStudentNumber(studentNumber);
  if (!isValidStudentNumber(number) || !String(password ?? "")) {
    throw new Error("Invalid login credentials");
  }

  const email = await resolveStudentLoginEmail(number, String(password));
  if (!email) {
    throw new Error("Invalid login credentials");
  }

  const supabase = getSupabase();
  const authClient = createSupabaseAuthClient();
  const { data, error } = await authClient.auth.signInWithPassword({
    email,
    password: String(password),
  });

  if (error || !data.session) {
    throw new Error("Invalid login credentials");
  }

  const { error: lastLoginError } = await supabase
    .from("users")
    .update({ last_login_at: new Date().toISOString() })
    .eq("auth_user_id", data.user.id);
  if (lastLoginError) {
    console.warn("Unable to update last_login_at", lastLoginError.message);
  }

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
