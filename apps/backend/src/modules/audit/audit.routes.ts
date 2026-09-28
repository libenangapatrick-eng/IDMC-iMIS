import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { requirePermission } from "../../middleware/rbac.js";
import { getSupabase } from "../../config/database.js";

const router = Router();

router.use(authenticate);

router.get(
  "/",
  requirePermission("audit.view"),
  async (_req, res, next) => {
    try {
      const { data, error } =
        await getSupabase()
          .from("audit_logs")
          .select("*")
          .order("created_at", { ascending: false })
          .limit(500);

      if (error) throw error;

      return res.json({
        success: true,
        data: data ?? []
      });
    } catch (error) {
      next(error);
    }
  }
);

export default router;