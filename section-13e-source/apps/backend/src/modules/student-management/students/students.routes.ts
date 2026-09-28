import { Router } from "express";

import {
    authenticate,
} from "../../../middleware/auth.js";

import {
    requirePermission,
} from "../../../middleware/rbac.js";

import {
    createStudentController,
    getMyStudentController,
    getMyStudentPortalController,
    getStudentController,
    listStudentsController,
    updateStudentController,
    updateMyProfilePhotoController,
} from "./students.controller.js";

const router =
    Router();

router.use(authenticate);

router.get(
    "/me",
    requirePermission("students.self.view"),
    getMyStudentController
);

router.get(
    "/me/portal",
    requirePermission("students.self.view"),
    getMyStudentPortalController
);

router.patch(
    "/me/profile-photo",
    requirePermission("students.self.view"),
    updateMyProfilePhotoController
);

router.get(
    "/",
    requirePermission("students.view"),
    listStudentsController
);

router.get(
    "/:id",
    requirePermission("students.view"),
    getStudentController
);

router.post(
    "/",
    requirePermission("students.manage"),
    createStudentController
);

router.patch(
    "/:id",
    requirePermission("students.manage"),
    updateStudentController
);

export default router;

