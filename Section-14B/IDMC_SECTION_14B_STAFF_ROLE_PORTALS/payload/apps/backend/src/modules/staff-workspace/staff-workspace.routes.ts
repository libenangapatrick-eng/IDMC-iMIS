import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { requirePermission } from "../../middleware/rbac.js";
import { financePayment, financeWorkspace, lecturerAttendance, lecturerMark, lecturerMarkSubmit, lecturerResultSubmit, lecturerWorkspace, registryRequestDecision, registryWorkspace } from "./staff-workspace.controller.js";

const router = Router();
router.use(authenticate);
router.get("/lecturer", requirePermission("portal.lecturer"), lecturerWorkspace);
router.post("/lecturer/attendance", requirePermission("lecturer.attendance.record"), lecturerAttendance);
router.post("/lecturer/marks", requirePermission("lecturer.marks.enter"), lecturerMark);
router.post("/lecturer/marks/submit", requirePermission("lecturer.marks.submit"), lecturerMarkSubmit);
router.post("/lecturer/results/submit", requirePermission("lecturer.results.submit"), lecturerResultSubmit);
router.get("/finance", requirePermission("portal.finance"), financeWorkspace);
router.post("/finance/payments", requirePermission("finance.payments.record"), financePayment);
router.get("/registry", requirePermission("portal.registry"), registryWorkspace);
router.post("/registry/requests/decide", requirePermission("students.requests.decide"), registryRequestDecision);
export default router;
