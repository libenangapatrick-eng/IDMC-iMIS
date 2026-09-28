import { Router, type RequestHandler } from "express";

import authRoutes from "../modules/auth/routes/auth.routes.js";
import financeRoutes from "../modules/finance/routes/finance.routes.js";
import academicsRoutes from "../modules/academics/academics.routes.js";
import usersRoutes from "../modules/users/routes/users.routes.js";
import rolesRoutes from "../modules/users/routes/roles.routes.js";
import auditRoutes from "../modules/audit/audit.routes.js";

import hrRoutes from "../modules/hr/hr.routes.js";
import operationsRoutes from "../modules/operations/operations.routes.js";
import hostelRoutes from "../modules/hostel/hostel.routes.js";
import libraryRoutes from "../modules/library/library.routes.js";

import researchRoutes from "../modules/research/research.routes.js";
import communicationsRoutes from "../modules/communications/communications.routes.js";
import reportsRoutes from "../modules/reports/reports.routes.js";
import systemRoutes from "../modules/system/system.routes.js";

import registrationRoutes from "../modules/registration/registration.routes.js";
import timetableRoutes from "../modules/timetable/timetable.routes.js";
import attendanceRoutes from "../modules/attendance/attendance.routes.js";
import transcriptsRoutes from "../modules/transcripts/transcripts.routes.js";

import coreAcademicRoutes from "./core-routes.js";
import workflowRoutes from "../modules/workflows/workflow.routes.js";
import studentResultsRoutes from "../modules/student-self-service/student-results.routes.js";
import studentRequestsRoutes from "../modules/student-requests/student-requests.routes.js";
import selfServiceActionRoutes from "../modules/self-service-actions/self-service-actions.routes.js";
import paymentProviderRoutes from "../modules/self-service-actions/payment-provider.routes.js";
import applicantSelfServiceRoutes from "../modules/applicant-self-service/applicant-self-service.routes.js";
import institutionalDevelopmentRoutes from "../modules/institutional-development/institutional-development.routes.js";
import historicalStudentsRoutes from "../modules/historical-students/historical-students.routes.js";
import historicalAcademicsRoutes from "../modules/historical-students/historical-academics.routes.js";
import lifecycleCompletionRoutes from "../modules/lifecycle-completion/lifecycle-completion.routes.js";
import publicVerificationRoutes from "../modules/public-verification/public-verification.routes.js";

const router = Router();

export function scopedAliasPrefix(internalPrefix: string): RequestHandler {
  return (req, _res, next) => {
    req.url = `${internalPrefix}${req.url}`;
    next();
  };
}

/*
 * ============================================================
 * IDMC iMIS API v1
 * ============================================================
 *
 * Keep existing modules as the source of truth.
 * Alias mounts below expose stable top-level API contracts
 * without duplicating database/business logic.
 *
 */

// ------------------------------------------------------------
// Identity / Administration
// ------------------------------------------------------------

router.use("/auth", authRoutes);
router.use("/public", publicVerificationRoutes);
router.use("/users", usersRoutes);
router.use("/roles", rolesRoutes);
router.use("/audit-logs", auditRoutes);


// ------------------------------------------------------------
// Finance / HR
// ------------------------------------------------------------

router.use("/finance", financeRoutes);
router.use("/hr", hrRoutes);


// ------------------------------------------------------------
// Academic administration
// ------------------------------------------------------------

router.use("/academics", academicsRoutes);


// ------------------------------------------------------------
// Operations
// Existing operationsRoutes owns procurement/inventory/assets.
// ------------------------------------------------------------

router.use("/operations", operationsRoutes);

/*
 * Stable aliases:
 *
 * /api/v1/assets/*
 *     -> existing /operations/assets/*
 *
 * /api/v1/procurement/*
 *     -> existing /operations/procurement/*
 *
 * No duplicate CRUD implementation is created.
 */

router.all("/assets", scopedAliasPrefix("/assets"), operationsRoutes);
router.use("/assets", scopedAliasPrefix("/assets"), operationsRoutes);
router.use("/procurement", scopedAliasPrefix("/procurement"), operationsRoutes);


// ------------------------------------------------------------
// Student services
// ------------------------------------------------------------

router.use("/hostel", hostelRoutes);
router.use("/library", libraryRoutes);


// ------------------------------------------------------------
// Research / QA / Communication
// ------------------------------------------------------------

router.use("/research", researchRoutes);
router.use("/communications", communicationsRoutes);


// ------------------------------------------------------------
// Documents / Helpdesk
//
// communicationsRoutes already owns:
//   /documents
//   /document-versions
//   /helpdesk/categories
//   /helpdesk/tickets
//   /helpdesk/messages
//
// Mount aliases rather than duplicate those handlers.
// ------------------------------------------------------------

router.all("/documents", scopedAliasPrefix("/documents"), communicationsRoutes);
router.use("/documents", scopedAliasPrefix("/documents"), communicationsRoutes);
router.use("/helpdesk", scopedAliasPrefix("/helpdesk"), communicationsRoutes);


// ------------------------------------------------------------
// Reporting / System
// ------------------------------------------------------------

router.use("/reports", reportsRoutes);
router.use("/system", systemRoutes);


// ------------------------------------------------------------
// Core academic API
//
// applications
// admissions
// academic-core
// assessment
// examinations
// results
// graduation
// alumni
// ------------------------------------------------------------

router.use("/registrations", registrationRoutes);
router.use("/timetables", timetableRoutes);
router.use("/attendance", attendanceRoutes);
router.use("/transcripts", transcriptsRoutes);

router.use("/", coreAcademicRoutes);


// ------------------------------------------------------------
// Workflow actions
// ------------------------------------------------------------

router.use("/workflows", workflowRoutes);
router.use("/student-results", studentResultsRoutes);
router.use("/student-requests", studentRequestsRoutes);
router.use("/self-service", selfServiceActionRoutes);
router.use("/payment-provider", paymentProviderRoutes);
router.use("/applicant", applicantSelfServiceRoutes);
router.use("/institutional-development", institutionalDevelopmentRoutes);
router.use("/historical-students", historicalStudentsRoutes);
router.use("/historical-academics", historicalAcademicsRoutes);
router.use("/lifecycle-completion", lifecycleCompletionRoutes);


export default router;

