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
    getStudentController,
    listStudentsController,
    updateStudentController,
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

