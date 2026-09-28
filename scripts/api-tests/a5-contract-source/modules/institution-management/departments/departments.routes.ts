import { Router } from "express";

import {
    authenticate
} from "../../../middleware/auth.js";

import {
    requirePermission
} from "../../../middleware/rbac.js";

import {
    createDepartmentController,
    getDepartmentController,
    listDepartmentsController,
    updateDepartmentController
} from "./departments.controller.js";

const router = Router();

router.use(authenticate);

router.get(
    "/",
    requirePermission("departments.view"),
    listDepartmentsController
);

router.get(
    "/:id",
    requirePermission("departments.view"),
    getDepartmentController
);

router.post(
    "/",
    requirePermission("departments.manage"),
    createDepartmentController
);

router.patch(
    "/:id",
    requirePermission("departments.manage"),
    updateDepartmentController
);

export default router;





