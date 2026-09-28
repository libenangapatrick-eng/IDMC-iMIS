import { Router } from "express";

import {
    authenticate
} from "../../../middleware/auth.js";

import {
    requirePermission
} from "../../../middleware/rbac.js";

import {
    createInstitutionController,
    getInstitutionController,
    listInstitutionsController,
    updateInstitutionController
} from "./institutions.controller.js";

const router = Router();

router.use(authenticate);

router.get(
    "/",
    requirePermission("institutions.view"),
    listInstitutionsController
);

router.get(
    "/:id",
    requirePermission("institutions.view"),
    getInstitutionController
);

router.post(
    "/",
    requirePermission("institutions.manage"),
    createInstitutionController
);

router.patch(
    "/:id",
    requirePermission("institutions.manage"),
    updateInstitutionController
);

export default router;





