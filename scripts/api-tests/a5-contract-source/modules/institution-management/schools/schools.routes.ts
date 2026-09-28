import { Router } from "express";

import {
    authenticate
} from "../../../middleware/auth.js";

import {
    requirePermission
} from "../../../middleware/rbac.js";

import {
    createSchoolController,
    getSchoolController,
    listSchoolsController,
    updateSchoolController
} from "./schools.controller.js";

const router = Router();

router.use(authenticate);

router.get(
    "/",
    requirePermission("schools.view"),
    listSchoolsController
);

router.get(
    "/:id",
    requirePermission("schools.view"),
    getSchoolController
);

router.post(
    "/",
    requirePermission("schools.manage"),
    createSchoolController
);

router.patch(
    "/:id",
    requirePermission("schools.manage"),
    updateSchoolController
);

export default router;





