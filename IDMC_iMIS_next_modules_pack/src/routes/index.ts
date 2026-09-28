import { Router } from "express";
import authRoutes from "../modules/auth/auth.routes.js";
import financeRoutes from "../modules/finance/finance.routes.js";
import academicsRoutes from "../modules/academics/academics.routes.js";
import usersRoutes from "../modules/users/users.routes.js";
import rolesRoutes from "../modules/users/roles.routes.js";
import hrRoutes from "../modules/hr/hr.routes.js";
import operationsRoutes from "../modules/operations/operations.routes.js";
import hostelRoutes from "../modules/hostel/hostel.routes.js";
import libraryRoutes from "../modules/library/library.routes.js";
import researchRoutes from "../modules/research/research.routes.js";
import communicationsRoutes from "../modules/communications/communications.routes.js";
import reportsRoutes from "../modules/reports/reports.routes.js";
import systemRoutes from "../modules/system/system.routes.js";

const router = Router();

router.use("/auth", authRoutes);
router.use("/finance", financeRoutes);
router.use("/academics", academicsRoutes);
router.use("/users", usersRoutes);
router.use("/roles", rolesRoutes);
router.use("/hr", hrRoutes);
router.use("/operations", operationsRoutes);
router.use("/hostel", hostelRoutes);
router.use("/library", libraryRoutes);
router.use("/research", researchRoutes);
router.use("/communications", communicationsRoutes);
router.use("/reports", reportsRoutes);
router.use("/system", systemRoutes);

export default router;
