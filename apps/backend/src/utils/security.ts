type RoleAssignment = Record<string, any>;

export function parseBearerToken(authorization: string | undefined): string | null {
  if (!authorization) return null;
  return authorization.match(/^Bearer\s+([^\s]+)$/i)?.[1] ?? null;
}

function assignmentIsActive(userRole: RoleAssignment, now: Date): boolean {
  return userRole.status === "ACTIVE" && userRole.roles?.status === "ACTIVE" && (!userRole.expires_at || new Date(userRole.expires_at) > now);
}

export function rolesGrantPermission(data: RoleAssignment[] | null | undefined, permissionCode: string, now = new Date()): boolean {
  return (data ?? []).some(userRole => assignmentIsActive(userRole, now) && (userRole.roles?.role_permissions ?? []).some((item: RoleAssignment) => item.permissions?.status === "ACTIVE" && item.permissions?.permission_code === permissionCode));
}

export function rolesGrantRole(data: RoleAssignment[] | null | undefined, roleCodes: string[], now = new Date()): boolean {
  return (data ?? []).some(userRole => assignmentIsActive(userRole, now) && roleCodes.includes(userRole.roles?.role_code));
}
