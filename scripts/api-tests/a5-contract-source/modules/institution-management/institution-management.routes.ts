import { Router } from "express";

import institutionsRoutes
    from "./institutions/institutions.routes.js";

import campusesRoutes
    from "./campuses/campuses.routes.js";

import schoolsRoutes
    from "./schools/schools.routes.js";

import departmentsRoutes
    from "./departments/departments.routes.js";

const router = Router();

router.use(
    "/institutions",
    institutionsRoutes
);

router.use(
    "/campuses",
    campusesRoutes
);

router.use(
    "/schools",
    schoolsRoutes
);

router.use(
    "/departments",
    departmentsRoutes
);

export default router;


