import { getSupabase } from "../../../config/database.js";
import { env } from "../../../config/env.js";
import {
  createAuditLog,
} from "../../../services/audit.service.js";
import {
  sendWelcomeEmail,
} from "../../../services/email.service.js";

export interface CreateUserInput {
  firstName: string;
  middleName?: string;
  lastName: string;

  displayName?: string;

  username?: string;

  phone?: string;

  email: string;
  password: string;

  initialRole?: string;

  /**
   * Administrative provisioning may deliberately suppress email delivery
   * when SMTP is not configured. The temporary password is still never
   * logged or persisted outside Supabase Auth.
   */
  sendWelcomeMessage?: boolean;

  status?:
    | "PENDING"
    | "ACTIVE"
    | "SUSPENDED"
    | "LOCKED"
    | "INACTIVE"
    | "DISABLED";
}

export interface UpdateUserInput {
  firstName?: string;
  middleName?: string;
  lastName?: string;

  displayName?: string;

  username?: string;

  phone?: string;

  status?:
    | "PENDING"
    | "ACTIVE"
    | "SUSPENDED"
    | "LOCKED"
    | "INACTIVE"
    | "DISABLED";
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function normalizeUsername(username?: string): string | null {
  if (!username) {
    return null;
  }

  const value = username.trim().toLowerCase();

  return value || null;
}

function generateDisplayName(
  firstName: string,
  middleName: string | undefined,
  lastName: string
): string {
  return [
    firstName.trim(),
    middleName?.trim(),
    lastName.trim(),
  ]
    .filter(Boolean)
    .join(" ");
}

async function generateUserNumber(): Promise<string> {
  const supabase = getSupabase();

  const year = new Date().getFullYear();

  const prefix = `IDMC/USER/${year}/`;

  const { data, error } = await supabase
    .from("users")
    .select("user_number")
    .like("user_number", `${prefix}%`)
    .order("user_number", {
      ascending: false,
    })
    .limit(1);

  if (error) {
    throw new Error(
      `Unable to generate user number: ${error.message}`
    );
  }

  let sequence = 1;

  if (data && data.length > 0) {
    const lastNumber = data[0]?.user_number;

    if (lastNumber) {
      const lastSequence = Number(
        lastNumber.replace(prefix, "")
      );

      if (
        Number.isInteger(lastSequence) &&
        lastSequence > 0
      ) {
        sequence = lastSequence + 1;
      }
    }
  }

  return `${prefix}${String(sequence).padStart(5, "0")}`;
}

async function findRoleByCode(
  roleCodeOrId: string
) {
  const supabase = getSupabase();

  const value = String(roleCodeOrId ?? "").trim();

  if (!value) {
    throw new Error("Role is required.");
  }

  // The frontend may send either:
  // 1. role_code  e.g. STORE_OFFICER
  // 2. role UUID   e.g. AB82A1DA-5C50-4410-AC94-D5403B5172BB
  const isUuid =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value
    );

  let query = supabase
    .from("roles")
    .select("id, role_code, role_name, status")
    .eq("status", "ACTIVE");

  if (isUuid) {
    query = query.eq("id", value);
  } else {
    query = query.eq("role_code", value);
  }

  const { data, error } = await query.maybeSingle();

  if (error) {
    throw new Error(
      `Unable to find role: ${error.message}`
    );
  }

  if (!data) {
    throw new Error(
      `Role '${value}' does not exist or is inactive.`
    );
  }

  return data;
}

export async function listUsers() {
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
      profile_photo_url,
      status,
      last_login_at,
      created_at,
      updated_at,
      user_roles!user_roles_user_id_fkey (
        id,
        status,
        expires_at,
        roles (
          id,
          role_code,
          role_name
        )
      )
    `)
    .order("created_at", {
      ascending: false,
    });

  if (error) {
    throw new Error(
      `Unable to load users: ${error.message}`
    );
  }

  return data ?? [];
}

export async function getUserById(id: string) {
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
      profile_photo_url,
      status,
      last_login_at,
      password_changed_at,
      failed_login_attempts,
      locked_until,
      email_verified_at,
      phone_verified_at,
      created_at,
      updated_at,
      user_roles!user_roles_user_id_fkey (
        id,
        status,
        expires_at,
        assigned_at,
        roles (
          id,
          role_code,
          role_name,
          description
        )
      )
    `)
    .eq("id", id)
    .maybeSingle();

  if (error) {
    throw new Error(
      `Unable to load user: ${error.message}`
    );
  }

  if (!data) {
    throw new Error("User not found.");
  }

  return data;
}

export async function listRoles() {
  const supabase = getSupabase();

  const { data, error } = await supabase
    .from("roles")
    .select(`
      id,
      role_code,
      role_name,
      description,
      status
    `)
    .eq("status", "ACTIVE")
    .order("role_name", {
      ascending: true,
    });

  if (error) {
    throw new Error(
      `Unable to load roles: ${error.message}`
    );
  }

  return data ?? [];
}

export async function createUser(
  input: CreateUserInput,
  actorUserId: string,
  ipAddress?: string | null,
  requestId?: string | null
) {
  const supabase = getSupabase();

  const email = normalizeEmail(input.email);

  const username = normalizeUsername(
    input.username
  );

  const firstName = input.firstName.trim();
  const middleName = input.middleName?.trim() || null;
  const lastName = input.lastName.trim();

  const displayName =
    input.displayName?.trim() ||
    generateDisplayName(
      firstName,
      middleName ?? undefined,
      lastName
    );

  const status = input.status ?? "ACTIVE";

  let authUserId: string | null = null;
  let publicUserId: string | null = null;
  let roleAssignmentId: string | null = null;

  await createAuditLog({
    actorUserId,

    actionCode: "USER_CREATE_STARTED",
    moduleCode: "users",

    entityType: "user",

    newValues: {
      email,
      username,
      display_name: displayName,
      status,
      initial_role: input.initialRole ?? null,
    },

    ipAddress,
    requestId,
  });

  try {
    const { data: duplicateEmail } = await supabase
      .from("users")
      .select("id")
      .eq("email", email)
      .maybeSingle();

    if (duplicateEmail) {
      throw new Error(
        "A user with this email already exists."
      );
    }

    if (username) {
      const { data: duplicateUsername } =
        await supabase
          .from("users")
          .select("id")
          .eq("username", username)
          .maybeSingle();

      if (duplicateUsername) {
        throw new Error(
          "A user with this username already exists."
        );
      }
    }

    let role = null;

    if (input.initialRole) {
      role = await findRoleByCode(
        input.initialRole.trim().toUpperCase()
      );
    }

    /*
     * -------------------------------------------------------
     * 1. CREATE SUPABASE AUTH USER
     * -------------------------------------------------------
     */

    const {
      data: authData,
      error: authError,
    } = await supabase.auth.admin.createUser({
      email,

      password: input.password,

      email_confirm: true,

      user_metadata: {
        first_name: firstName,
        middle_name: middleName,
        last_name: lastName,
        display_name: displayName,
        username,
      },
    });

    if (authError || !authData.user) {
      throw new Error(
        authError?.message ||
          "Unable to create authentication account."
      );
    }

    authUserId = authData.user.id;

    await createAuditLog({
      actorUserId,

      actionCode: "USER_AUTH_CREATED",
      moduleCode: "users",

      entityType: "auth_user",
      entityId: authUserId,

      newValues: {
        email,
        email_confirmed: true,
      },

      ipAddress,
      requestId,
    });

    /*
     * -------------------------------------------------------
     * 2. GENERATE USER NUMBER
     * -------------------------------------------------------
     */

    const userNumber =
      await generateUserNumber();

    /*
     * -------------------------------------------------------
     * 3. CREATE public.users
     * -------------------------------------------------------
     */

    const {
      data: publicUser,
      error: publicUserError,
    } = await supabase
      .from("users")
      .insert({
        auth_user_id: authUserId,

        user_number: userNumber,

        username,

        first_name: firstName,
        middle_name: middleName,
        last_name: lastName,

        display_name: displayName,

        email,
        phone: input.phone?.trim() || null,

        status,

        email_verified_at:
          new Date().toISOString(),
      })
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
        created_at
      `)
      .single();

    if (
      publicUserError ||
      !publicUser
    ) {
      throw new Error(
        publicUserError?.message ||
          "Unable to create public user profile."
      );
    }

    publicUserId = publicUser.id;

    await createAuditLog({
      actorUserId,

      actionCode: "USER_PROFILE_CREATED",
      moduleCode: "users",

      entityType: "user",
      entityId: publicUserId,

      newValues: {
        user_number: userNumber,
        email,
        username,
        status,
      },

      ipAddress,
      requestId,
    });

    /*
     * -------------------------------------------------------
     * 4. ASSIGN INITIAL ROLE
     * -------------------------------------------------------
     */

    if (role) {
      const {
        data: roleAssignment,
        error: roleError,
      } = await supabase
        .from("user_roles")
        .insert({
          user_id: publicUserId,

          role_id: role.id,

          assigned_by: actorUserId,

          status: "ACTIVE",
        })
        .select("id")
        .single();

      if (
        roleError ||
        !roleAssignment
      ) {
        throw new Error(
          roleError?.message ||
            "Unable to assign initial role."
        );
      }

      roleAssignmentId =
        roleAssignment.id;

      await createAuditLog({
        actorUserId,

        actionCode: "USER_ROLE_ASSIGNED",
        moduleCode: "users",

        entityType: "user_role",
        entityId: roleAssignmentId,

        newValues: {
          user_id: publicUserId,
          role_id: role.id,
          role_code: role.role_code,
        },

        ipAddress,
        requestId,
      });
    }

    /*
     * -------------------------------------------------------
     * 5. GENERATE PASSWORD SETUP LINK
     * -------------------------------------------------------
     */

    const shouldSendWelcome = input.sendWelcomeMessage !== false;

    if (shouldSendWelcome) {
      const {
        data: linkData,
        error: linkError,
      } = await supabase.auth.admin.generateLink({
        type: "recovery",
        email,
        options: {
          redirectTo: `${env.FRONTEND_URL}/set-password.html`,
        },
      });

      if (linkError || !linkData?.properties?.action_link) {
        throw new Error(
          linkError?.message ||
            "Unable to generate secure password setup link."
        );
      }

      const setupPasswordUrl = linkData.properties.action_link;

      try {
        await sendWelcomeEmail({
          recipientEmail: email,
          recipientName: displayName,
          userNumber,
          username: username || email,
          setupPasswordUrl,
        });
      } catch (emailError) {
        await createAuditLog({
          actorUserId,
          actionCode: "USER_WELCOME_EMAIL_FAILED",
          moduleCode: "users",
          entityType: "user",
          entityId: publicUserId,
          newValues: {
            email,
            user_number: userNumber,
            reason:
              emailError instanceof Error
                ? emailError.message
                : "Unknown email error",
          },
          ipAddress,
          requestId,
        });

        throw new Error(
          emailError instanceof Error
            ? emailError.message
            : "Welcome email could not be sent."
        );
      }

      await createAuditLog({
        actorUserId,
        actionCode: "USER_WELCOME_EMAIL_SENT",
        moduleCode: "users",
        entityType: "user",
        entityId: publicUserId,
        newValues: { email, user_number: userNumber },
        ipAddress,
        requestId,
      });
    }

    /*
     * -------------------------------------------------------
     * 7. FINAL AUDIT
     * -------------------------------------------------------
     */

    await createAuditLog({
      actorUserId,

      actionCode:
        "USER_CREATE_COMPLETED",

      moduleCode: "users",

      entityType: "user",
      entityId: publicUserId,

      newValues: {
        user_number: userNumber,
        email,
        username,
        status,
        role: role?.role_code ?? null,
      },

      ipAddress,
      requestId,
    });

    return {
      user: publicUser,

      role: role
        ? {
            id: role.id,
            role_code: role.role_code,
            role_name: role.role_name,
          }
        : null,

      onboarding: {
        welcome_email_sent: shouldSendWelcome,
        password_setup_required: true,
      },
    };
  } catch (error) {
    /*
     * =======================================================
     * ROLLBACK
     * =======================================================
     *
     * Order:
     *
     * 1. Remove role assignment
     * 2. Remove public.users
     * 3. Remove Supabase Auth user
     *
     * Password is NEVER logged.
     */

    if (roleAssignmentId) {
      await supabase
        .from("user_roles")
        .delete()
        .eq("id", roleAssignmentId);
    }

    if (publicUserId) {
      await supabase
        .from("users")
        .delete()
        .eq("id", publicUserId);
    }

    if (authUserId) {
      await supabase.auth.admin.deleteUser(
        authUserId
      );
    }

    await createAuditLog({
      actorUserId,

      actionCode:
        "USER_CREATE_ROLLBACK",

      moduleCode: "users",

      entityType: "user",

      entityId: publicUserId,

      newValues: {
        email,
        auth_user_id: authUserId,
        reason:
          error instanceof Error
            ? error.message
            : "Unknown user creation error",
      },

      ipAddress,
      requestId,
    });

    throw error;
  }
}

export async function updateUser(
  id: string,
  input: UpdateUserInput,
  actorUserId: string,
  ipAddress?: string | null,
  requestId?: string | null
) {
  const supabase = getSupabase();

  const current =
    await getUserById(id);

  const updates: Record<
    string,
    unknown
  > = {};

  if (input.firstName !== undefined) {
    updates.first_name =
      input.firstName.trim();
  }

  if (input.middleName !== undefined) {
    updates.middle_name =
      input.middleName.trim() || null;
  }

  if (input.lastName !== undefined) {
    updates.last_name =
      input.lastName.trim();
  }

  if (input.displayName !== undefined) {
    updates.display_name =
      input.displayName.trim();
  }

  if (input.username !== undefined) {
    updates.username =
      normalizeUsername(
        input.username
      );
  }

  if (input.phone !== undefined) {
    updates.phone =
      input.phone.trim() || null;
  }

  if (input.status !== undefined) {
    updates.status =
      input.status;
  }

  const { data, error } =
    await supabase
      .from("users")
      .update(updates)
      .eq("id", id)
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
      .single();

  if (error || !data) {
    throw new Error(
      error?.message ||
        "Unable to update user."
    );
  }

  await createAuditLog({
    actorUserId,

    actionCode:
      "USER_UPDATE",

    moduleCode: "users",

    entityType: "user",
    entityId: id,

    oldValues: {
      username: current.username,
      display_name: current.display_name,
      phone: current.phone,
      status: current.status,
    },

    newValues: {
      username: data.username,
      display_name: data.display_name,
      phone: data.phone,
      status: data.status,
    },

    ipAddress,
    requestId,
  });

  return data;
}

export async function assignRole(
  userId: string,
  roleCode: string,
  actorUserId: string,
  ipAddress?: string | null,
  requestId?: string | null
) {
  const supabase = getSupabase();

  const user =
    await getUserById(userId);

  const role =
    await findRoleByCode(
      roleCode.trim().toUpperCase()
    );

  const {
    data,
    error,
  } = await supabase
    .from("user_roles")
    .insert({
      user_id: userId,
      role_id: role.id,
      assigned_by: actorUserId,
      status: "ACTIVE",
    })
    .select(`
      id,
      user_id,
      role_id,
      status,
      assigned_at,
      expires_at,
      roles (
        id,
        role_code,
        role_name
      )
    `)
    .single();

  if (error || !data) {
    throw new Error(
      error?.message ||
        "Unable to assign role."
    );
  }

  await createAuditLog({
    actorUserId,

    actionCode:
      "USER_ROLE_ASSIGNED",

    moduleCode: "users",

    entityType: "user_role",
    entityId: data.id,

    newValues: {
      user_id: userId,
      user_number:
        user.user_number,
      role_code:
        role.role_code,
    },

    ipAddress,
    requestId,
  });

  return data;
}

export async function removeRole(
  userId: string,
  roleId: string,
  actorUserId: string,
  ipAddress?: string | null,
  requestId?: string | null
) {
  const supabase = getSupabase();

  const {
    data: existing,
  } = await supabase
    .from("user_roles")
    .select(`
      id,
      user_id,
      role_id,
      roles (
        role_code,
        role_name
      )
    `)
    .eq("id", roleId)
    .eq("user_id", userId)
    .maybeSingle();

  if (!existing) {
    throw new Error(
      "User role assignment not found."
    );
  }

  const {
    error,
  } = await supabase
    .from("user_roles")
    .delete()
    .eq("id", roleId)
    .eq("user_id", userId);

  if (error) {
    throw new Error(
      `Unable to remove role: ${error.message}`
    );
  }

  await createAuditLog({
    actorUserId,

    actionCode:
      "USER_ROLE_REMOVED",

    moduleCode: "users",

    entityType: "user_role",
    entityId: roleId,

    oldValues: {
      user_id: userId,
      role_id: existing.role_id,
      role:
        existing.roles,
    },

    ipAddress,
    requestId,
  });

  return {
    success: true,
  };
}


