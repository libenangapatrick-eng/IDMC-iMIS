import { Router } from "express";
import * as controller from "../controllers/auth.controller.js";
import { authenticate } from "../../../middleware/auth.js";
import { rateLimit } from "../../../middleware/rateLimit.js";

const router = Router();

router.get("/health", controller.authHealth);
router.post("/student-login", rateLimit({ windowMs: 15 * 60 * 1000, max: 10, name: "student-login" }), controller.studentLogin);
router.post("/login", rateLimit({ windowMs: 15 * 60 * 1000, max: 10, name: "auth-login" }), controller.login);
router.get("/me", authenticate, controller.me);

export default router;
