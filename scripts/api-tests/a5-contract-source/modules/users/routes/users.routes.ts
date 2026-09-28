import { Router } from "express";

import {
  authenticate,
} from "../../../middleware/auth.js";

import {
  requirePermission,
} from "../../../middleware/rbac.js";

import {
  listUsersController,
  listRolesController,
  getUserController,
  createUserController,
  updateUserController,
  assignRoleController,
  removeRoleController,
} from "../controllers/users.controller.js";

const router = Router();

router.use(authenticate);

/*
 * =========================================================
 * USERS
 * =========================================================
 */

router.get(
  "/",
  requirePermission("users.view"),
  listUsersController
);

router.get(
  "/roles",
  requirePermission("roles.view"),
  listRolesController
);

router.get(
  "/:id",
  requirePermission("users.view"),
  getUserController
);

router.post(
  "/",
  requirePermission("users.create"),
  createUserController
);

router.patch(
  "/:id",
  requirePermission("users.update"),
  updateUserController
);

/*
 * =========================================================
 * USER ROLES
 * =========================================================
 */

router.post(
  "/:id/roles",
  requirePermission("roles.manage"),
  assignRoleController
);

router.delete(
  "/:id/roles/:roleId",
  requirePermission("roles.manage"),
  removeRoleController
);

export default router;
