import { Router } from "express";

import { academicsController }
    from "./academics.controller.js";

import { authenticate }
    from "../../middleware/auth.js";

import { requirePermission }
    from "../../middleware/rbac.js";

const router = Router();

router.use(authenticate);

router.get(
    "/",
    requirePermission("academics.view"),
    academicsController.list.bind(academicsController)
);

router.get(
    "/:id",
    requirePermission("academics.view"),
    academicsController.getById.bind(academicsController)
);

router.post(
    "/",
    requirePermission("academics.manage"),
    academicsController.create.bind(academicsController)
);

router.patch(
    "/:id",
    requirePermission("academics.manage"),
    academicsController.update.bind(academicsController)
);

router.delete(
    "/:id",
    requirePermission("academics.manage"),
    academicsController.remove.bind(academicsController)
);

export default router;

