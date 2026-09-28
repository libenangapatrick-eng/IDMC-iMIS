import { Router } from "express";

import {
    authenticate
} from "../../../middleware/auth.js";

import {
    requirePermission
} from "../../../middleware/rbac.js";

import {
    createCampusController,
    getCampusController,
    listCampusesController,
    updateCampusController
} from "./campuses.controller.js";

const router = Router();

router.use(authenticate);

router.get(
    "/",
    requirePermission("campuses.view"),
    listCampusesController
);

router.get(
    "/:id",
    requirePermission("campuses.view"),
    getCampusController
);

router.post(
    "/",
    requirePermission("campuses.manage"),
    createCampusController
);

router.patch(
    "/:id",
    requirePermission("campuses.manage"),
    updateCampusController
);

export default router;





