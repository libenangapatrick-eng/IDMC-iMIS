import { Router } from "express";
import { authenticate } from "../../../middleware/auth.js";
import { requirePermission } from "../../../middleware/rbac.js";

import {
  listRolesController,
  getRoleController,
  createRoleController,
  updateRoleController,
  listPermissionsController,
  getRolePermissionsController,
  assignPermissionController,
  removePermissionController,
} from "../controllers/roles.controller.js";

const router = Router();

router.use(authenticate);

router.get(
  "/",
  requirePermission("roles.view"),
  listRolesController
);

router.get(
  "/permissions",
  requirePermission("permissions.view"),
  listPermissionsController
);

router.get(
  "/:id",
  requirePermission("roles.view"),
  getRoleController
);

router.get(
  "/:id/permissions",
  requirePermission("roles.view"),
  getRolePermissionsController
);

router.post(
  "/",
  requirePermission("roles.manage"),
  createRoleController
);

router.patch(
  "/:id",
  requirePermission("roles.manage"),
  updateRoleController
);

router.post(
  "/:id/permissions",
  requirePermission("roles.manage"),
  assignPermissionController
);

router.delete(
  "/:id/permissions/:permissionId",
  requirePermission("roles.manage"),
  removePermissionController
);

export default router;
