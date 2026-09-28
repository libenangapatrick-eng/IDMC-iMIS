import { Router } from "express";
import * as controller from "../controllers/finance.controller.js";
import { authenticate } from "../../../middleware/auth.js";
import { requirePermission } from "../../../middleware/rbac.js";

const router = Router();
router.use(authenticate);

router.get("/fee-structures", requirePermission("finance.view"), controller.listFeeStructures);
router.get("/fee-structures/:id", requirePermission("finance.view"), controller.getFeeStructure);

router.get("/students/:studentId/account", requirePermission("finance.view"), controller.getFinancialAccount);
router.get("/students/:studentId/charges", requirePermission("finance.charges.view"), controller.getCharges);
router.get("/students/:studentId/invoices", requirePermission("finance.invoices.view"), controller.getInvoices);
router.get("/students/:studentId/payments", requirePermission("finance.payments.view"), controller.getPayments);
router.get("/students/:studentId/refunds", requirePermission("finance.refunds.view"), controller.getRefunds);
router.get("/students/:studentId/scholarships", requirePermission("finance.scholarships.view"), controller.getScholarships);
router.get("/students/:studentId/adjustments", requirePermission("finance.charges.view"), controller.getAdjustments);
router.get("/students/:studentId/transactions", requirePermission("finance.view"), controller.getTransactions);

export default router;
