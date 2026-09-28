import { Router } from "express";

import studentsRoutes from "./students/students.routes.js";

const router =
    Router();

router.use(
    "/students",
    studentsRoutes
);

export default router;
