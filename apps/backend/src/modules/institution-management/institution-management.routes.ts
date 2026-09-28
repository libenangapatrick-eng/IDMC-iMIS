import { Router } from "express";

import institutionsRoutes
    from "./institutions/institutions.routes.js";

import campusesRoutes
    from "./campuses/campuses.routes.js";

import schoolsRoutes
    from "./schools/schools.routes.js";

import departmentsRoutes
    from "./departments/departments.routes.js";

import {
    bindPrimaryInstitution
} from "./shared/single-institution.js";

const router = Router();

router.use(
    "/institutions",
    institutionsRoutes
);

router.use(
    "/campuses",
    bindPrimaryInstitution,
    campusesRoutes
);

router.use(
    "/schools",
    bindPrimaryInstitution,
    schoolsRoutes
);

router.use(
    "/departments",
    bindPrimaryInstitution,
    departmentsRoutes
);

export default router;


