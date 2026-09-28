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
    updateMyProfileController,
    updateMyProfilePhotoController,
    respondToCourseworkController,
    submitCourseEvaluationController,
    submitServiceRequestController,
    submitHelpdeskTicketController,
    changeMyPasswordController,
} from "./students.controller.js";

const router =
    Router();

router.use(authenticate);

router.get(
    "/me",
    requirePermission("students.self.view"),
    getMyStudentController
);

router.get("/me/portal", requirePermission("students.self.view"), getMyStudentPortalController);
router.patch("/me/profile", requirePermission("students.self.manage"), updateMyProfileController);
router.patch("/me/profile-photo", requirePermission("students.self.manage"), updateMyProfilePhotoController);
router.post("/me/coursework-responses", requirePermission("students.self.manage"), respondToCourseworkController);
router.post("/me/course-evaluations", requirePermission("students.self.manage"), submitCourseEvaluationController);
router.post("/me/requests", requirePermission("students.self.manage"), submitServiceRequestController);
router.post("/me/helpdesk", requirePermission("students.self.manage"), submitHelpdeskTicketController);
router.post("/me/change-password", requirePermission("students.self.manage"), changeMyPasswordController);

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

