import { Request, Response } from "express";
import {
  listRoles,
  getRoleById,
  createRole,
  updateRole,
  listPermissions,
  getRolePermissions,
  assignPermission,
  removePermission,
} from "../services/roles.service.js";
import { createAuditLog } from "../../../services/audit.service.js";

function getParam(
  req: Request,
  name: string
): string {
  const value = req.params[name];

  if (Array.isArray(value)) {
    return value[0] ?? "";
  }

  return value ?? "";
}

function getActorId(req: Request): string | null {
  return req.user?.id ?? null;
}

function getIpAddress(req: Request): string | null {
  const forwarded = req.headers["x-forwarded-for"];

  if (typeof forwarded === "string") {
    return forwarded.split(",")[0]?.trim() ?? null;
  }

  return req.ip ?? null;
}

function getRequestId(req: Request): string | null {
  const value = req.headers["x-request-id"];

  return typeof value === "string" ? value : null;
}

export async function listRolesController(
  _req: Request,
  res: Response
) {
  const data = await listRoles();

  res.json({
    success: true,
    data,
  });
}

export async function getRoleController(
  req: Request,
  res: Response
) {
  const roleId = getParam(req, "id");

  const data = await getRoleById(roleId);

  res.json({
    success: true,
    data,
  });
}

export async function createRoleController(
  req: Request,
  res: Response
) {
  const {
    roleCode,
    roleName,
    description,
    status,
  } = req.body;

  if (!roleCode || !roleName) {
    return res.status(400).json({
      success: false,
      message: "Role code and role name are required",
    });
  }

  const data = await createRole({
    roleCode,
    roleName,
    description,
    status,
  });

  await createAuditLog({
    actorUserId: getActorId(req),
    actionCode: "ROLE_CREATE",
    moduleCode: "RBAC",
    entityType: "ROLE",
    entityId: data.id,
    newValues: data,
    ipAddress: getIpAddress(req),
    requestId: getRequestId(req),
  });

  return res.status(201).json({
    success: true,
    message: "Role created successfully",
    data,
  });
}

export async function updateRoleController(
  req: Request,
  res: Response
) {
  const roleId = getParam(req, "id");

  const oldRole = await getRoleById(roleId);

  const data = await updateRole(roleId, {
    roleName: req.body.roleName,
    description: req.body.description,
    status: req.body.status,
  });

  await createAuditLog({
    actorUserId: getActorId(req),
    actionCode: "ROLE_UPDATE",
    moduleCode: "RBAC",
    entityType: "ROLE",
    entityId: roleId,
    oldValues: oldRole,
    newValues: data,
    ipAddress: getIpAddress(req),
    requestId: getRequestId(req),
  });

  return res.json({
    success: true,
    message: "Role updated successfully",
    data,
  });
}

export async function listPermissionsController(
  _req: Request,
  res: Response
) {
  const data = await listPermissions();

  res.json({
    success: true,
    data,
  });
}

export async function getRolePermissionsController(
  req: Request,
  res: Response
) {
  const roleId = getParam(req, "id");

  const data = await getRolePermissions(roleId);

  res.json({
    success: true,
    data,
  });
}

export async function assignPermissionController(
  req: Request,
  res: Response
) {
  const roleId = getParam(req, "id");
  const { permissionId } = req.body;

  if (!permissionId) {
    return res.status(400).json({
      success: false,
      message: "Permission ID is required",
    });
  }

  const data = await assignPermission(
    roleId,
    permissionId
  );

  await createAuditLog({
    actorUserId: getActorId(req),
    actionCode: "ROLE_PERMISSION_ASSIGN",
    moduleCode: "RBAC",
    entityType: "ROLE_PERMISSION",
    entityId: data.id,
    newValues: {
      roleId,
      permissionId,
    },
    ipAddress: getIpAddress(req),
    requestId: getRequestId(req),
  });

  return res.status(201).json({
    success: true,
    message: "Permission assigned successfully",
    data,
  });
}

export async function removePermissionController(
  req: Request,
  res: Response
) {
  const roleId = getParam(req, "id");
  const permissionId = getParam(req, "permissionId");

  const data = await removePermission(
    roleId,
    permissionId
  );

  await createAuditLog({
    actorUserId: getActorId(req),
    actionCode: "ROLE_PERMISSION_REMOVE",
    moduleCode: "RBAC",
    entityType: "ROLE_PERMISSION",
    entityId: permissionId,
    oldValues: {
      roleId,
      permissionId,
    },
    ipAddress: getIpAddress(req),
    requestId: getRequestId(req),
  });

  return res.json({
    success: true,
    message: "Permission removed successfully",
    data,
  });
}
