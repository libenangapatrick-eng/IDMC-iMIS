import { getSupabase } from "../../../config/database.js";

export interface CreateRoleInput {
  roleCode: string;
  roleName: string;
  description?: string | null | undefined;
  status?: "ACTIVE" | "INACTIVE" | undefined;
}

export interface UpdateRoleInput {
  roleName?: string | undefined;
  description?: string | null | undefined;
  status?: "ACTIVE" | "INACTIVE" | undefined;
}

export interface AssignPermissionInput {
  permissionId: string;
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
      is_system_role,
      status,
      created_at,
      updated_at,
      role_permissions (
        id,
        permission_id,
        permissions (
          id,
          permission_code,
          permission_name,
          module_code,
          action_code,
          description,
          status
        )
      )
    `)
    .order("role_name", { ascending: true });

  if (error) {
    throw new Error(`Failed to load roles: ${error.message}`);
  }

  return data ?? [];
}

export async function getRoleById(roleId: string) {
  const supabase = getSupabase();

  const { data, error } = await supabase
    .from("roles")
    .select(`
      id,
      role_code,
      role_name,
      description,
      is_system_role,
      status,
      created_at,
      updated_at,
      role_permissions (
        id,
        permission_id,
        permissions (
          id,
          permission_code,
          permission_name,
          module_code,
          action_code,
          description,
          status
        )
      )
    `)
    .eq("id", roleId)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to load role: ${error.message}`);
  }

  if (!data) {
    throw new Error("Role not found");
  }

  return data;
}

export async function createRole(input: CreateRoleInput) {
  const supabase = getSupabase();

  const roleCode = input.roleCode.trim().toUpperCase();
  const roleName = input.roleName.trim();

  const { data: existing, error: existingError } = await supabase
    .from("roles")
    .select("id")
    .eq("role_code", roleCode)
    .maybeSingle();

  if (existingError) {
    throw new Error(`Failed to check role: ${existingError.message}`);
  }

  if (existing) {
    throw new Error(`Role code '${roleCode}' already exists`);
  }

  const { data, error } = await supabase
    .from("roles")
    .insert({
      role_code: roleCode,
      role_name: roleName,
      description: input.description?.trim() || null,
      is_system_role: false,
      status: input.status ?? "ACTIVE",
    })
    .select()
    .single();

  if (error) {
    throw new Error(`Failed to create role: ${error.message}`);
  }

  return data;
}

export async function updateRole(
  roleId: string,
  input: UpdateRoleInput
) {
  const supabase = getSupabase();

  const payload: Record<string, unknown> = {};

  if (input.roleName !== undefined) {
    payload.role_name = input.roleName.trim();
  }

  if (input.description !== undefined) {
    payload.description = input.description?.trim() || null;
  }

  if (input.status !== undefined) {
    payload.status = input.status;
  }

  if (Object.keys(payload).length === 0) {
    throw new Error("No role changes supplied");
  }

  const { data, error } = await supabase
    .from("roles")
    .update(payload)
    .eq("id", roleId)
    .select()
    .single();

  if (error) {
    throw new Error(`Failed to update role: ${error.message}`);
  }

  return data;
}

export async function listPermissions() {
  const supabase = getSupabase();

  const { data, error } = await supabase
    .from("permissions")
    .select(`
      id,
      permission_code,
      permission_name,
      module_code,
      action_code,
      description,
      status,
      created_at,
      updated_at
    `)
    .order("module_code", { ascending: true })
    .order("permission_name", { ascending: true });

  if (error) {
    throw new Error(`Failed to load permissions: ${error.message}`);
  }

  return data ?? [];
}

export async function getRolePermissions(roleId: string) {
  const supabase = getSupabase();

  const { data, error } = await supabase
    .from("role_permissions")
    .select(`
      id,
      role_id,
      permission_id,
      permissions (
        id,
        permission_code,
        permission_name,
        module_code,
        action_code,
        description,
        status
      )
    `)
    .eq("role_id", roleId);

  if (error) {
    throw new Error(`Failed to load role permissions: ${error.message}`);
  }

  return data ?? [];
}

export async function assignPermission(
  roleId: string,
  permissionId: string
) {
  const supabase = getSupabase();

  const { data: role, error: roleError } = await supabase
    .from("roles")
    .select("id")
    .eq("id", roleId)
    .maybeSingle();

  if (roleError) {
    throw new Error(`Failed to check role: ${roleError.message}`);
  }

  if (!role) {
    throw new Error("Role not found");
  }

  const { data: permission, error: permissionError } = await supabase
    .from("permissions")
    .select("id")
    .eq("id", permissionId)
    .maybeSingle();

  if (permissionError) {
    throw new Error(
      `Failed to check permission: ${permissionError.message}`
    );
  }

  if (!permission) {
    throw new Error("Permission not found");
  }

  const { data: existing, error: existingError } = await supabase
    .from("role_permissions")
    .select("id")
    .eq("role_id", roleId)
    .eq("permission_id", permissionId)
    .maybeSingle();

  if (existingError) {
    throw new Error(
      `Failed to check permission assignment: ${existingError.message}`
    );
  }

  if (existing) {
    return existing;
  }

  const { data, error } = await supabase
    .from("role_permissions")
    .insert({
      role_id: roleId,
      permission_id: permissionId,
    })
    .select()
    .single();

  if (error) {
    throw new Error(
      `Failed to assign permission: ${error.message}`
    );
  }

  return data;
}

export async function removePermission(
  roleId: string,
  permissionId: string
) {
  const supabase = getSupabase();

  const { error } = await supabase
    .from("role_permissions")
    .delete()
    .eq("role_id", roleId)
    .eq("permission_id", permissionId);

  if (error) {
    throw new Error(
      `Failed to remove permission: ${error.message}`
    );
  }

  return {
    roleId,
    permissionId,
    removed: true,
  };
}
