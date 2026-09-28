import { Router } from "express";

import admissionsRoutes from "../modules/admissions/admissions.routes.js";
import academicCoreRoutes from "../modules/academic-core/academic-core.routes.js";
import assessmentRoutes from "../modules/assessment/assessment.routes.js";
import examinationRoutes from "../modules/examinations/examinations.routes.js";
import resultsRoutes from "../modules/results/results.routes.js";
import graduationRoutes from "../modules/graduation/graduation.routes.js";
import alumniRoutes from "../modules/alumni/alumni.routes.js";

const router = Router();
router.use("/applications", admissionsRoutes);
router.use("/admissions", admissionsRoutes);
router.use("/academic-core", academicCoreRoutes);
router.use("/assessment", assessmentRoutes);
router.use("/examinations", examinationRoutes);
router.use("/results", resultsRoutes);
router.use("/graduation", graduationRoutes);
router.use("/alumni", alumniRoutes);
export default router;
