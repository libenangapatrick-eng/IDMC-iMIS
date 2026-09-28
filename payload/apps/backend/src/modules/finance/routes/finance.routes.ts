import { Router } from "express";
import * as controller from "../controllers/finance.controller.js";
import { authenticate } from "../../../middleware/auth.js";
import { requirePermission } from "../../../middleware/rbac.js";
import { registerCrudResource } from "../../../utils/resourceCrud.js";

const router = Router();
router.use(authenticate);

registerCrudResource(
  router,
  {
    moduleCode: "FINANCE",
    entityType: "fee_structures",
    table: "fee_structures",
    permissionView: "finance.view",
    permissionManage: "finance.manage",
    searchFields: [
      "fee_structure_code",
      "fee_structure_name",
      "academic_year",
      "semester",
      "status",
      "currency_code"
    ],
    filterFields: [
      "academic_year",
      "semester",
      "status",
      "currency_code"
    ],
    defaultOrderField: "created_at",
    fields: {
      feeStructureCode: "fee_structure_code",
      feeStructureName: "fee_structure_name",
      academicYear: "academic_year",
      semester: "semester",
      description: "description",
      status: "status",
      currencyCode: "currency_code",
      effectiveFrom: "effective_from",
      effectiveTo: "effective_to",
      createdBy: "created_by",
      updatedBy: "updated_by"
    }
  },
  "/fee-structures"
);

registerCrudResource(router, {
  moduleCode: "FINANCE", entityType: "student_charges", table: "student_charges",
  permissionView: "finance.charges.view", permissionManage: "finance.manage",
  searchFields: ["charge_number","description","academic_year","semester","status"],
  filterFields: ["student_id","fee_structure_id","fee_item_id","status","academic_year","semester"], defaultOrderField: "charge_date",
  fields: { studentId:"student_id", feeStructureId:"fee_structure_id", feeItemId:"fee_item_id", chargeNumber:"charge_number", description:"description", academicYear:"academic_year", semester:"semester", originalAmount:"original_amount", scholarshipAmount:"scholarship_amount", waiverAmount:"waiver_amount", adjustmentAmount:"adjustment_amount", status:"status", chargeDate:"charge_date", dueDate:"due_date", createdBy:"created_by", updatedBy:"updated_by" }
}, "/charges");

registerCrudResource(router, {
  moduleCode: "FINANCE", entityType: "invoices", table: "invoices",
  permissionView: "finance.invoices.view", permissionManage: "finance.manage",
  searchFields: ["invoice_number","academic_year","semester","status","notes"],
  filterFields: ["student_id","status","academic_year","semester"], defaultOrderField: "invoice_date",
  fields: { studentId:"student_id", invoiceNumber:"invoice_number", invoiceDate:"invoice_date", dueDate:"due_date", academicYear:"academic_year", semester:"semester", subtotal:"subtotal", discountAmount:"discount_amount", scholarshipAmount:"scholarship_amount", adjustmentAmount:"adjustment_amount", totalAmount:"total_amount", amountPaid:"amount_paid", balanceAmount:"balance_amount", status:"status", currencyCode:"currency_code", notes:"notes", issuedBy:"issued_by", issuedAt:"issued_at", createdBy:"created_by", updatedBy:"updated_by" }
}, "/invoices");

registerCrudResource(router, {
  moduleCode: "FINANCE", entityType: "payments", table: "payments",
  permissionView: "finance.payments.view", permissionManage: "finance.payments.admin",
  searchFields: ["payment_number","external_reference","control_number","provider","payer_name","receipt_number"],
  filterFields: ["student_id","payment_method","status","currency_code"], defaultOrderField: "payment_date",
  fields: { studentId:"student_id", paymentNumber:"payment_number", externalReference:"external_reference", controlNumber:"control_number", paymentMethod:"payment_method", provider:"provider", amount:"amount", currencyCode:"currency_code", paymentDate:"payment_date", status:"status", payerName:"payer_name", payerPhone:"payer_phone", payerEmail:"payer_email", providerTransactionId:"provider_transaction_id", receiptNumber:"receipt_number" }
}, "/payments");

registerCrudResource(router, {
  moduleCode: "FINANCE", entityType: "student_scholarships", table: "student_scholarships",
  permissionView: "finance.scholarships.view", permissionManage: "finance.manage",
  searchFields: ["scholarship_code","scholarship_name","sponsor_name","academic_year","semester","status"],
  filterFields: ["student_id","scholarship_type","status","academic_year","semester"], defaultOrderField: "created_at",
  fields: { studentId:"student_id", scholarshipCode:"scholarship_code", scholarshipName:"scholarship_name", sponsorName:"sponsor_name", scholarshipType:"scholarship_type", amount:"amount", percentage:"percentage", academicYear:"academic_year", semester:"semester", startDate:"start_date", endDate:"end_date", status:"status", approvalReference:"approval_reference", approvedBy:"approved_by", approvedAt:"approved_at", notes:"notes", createdBy:"created_by", updatedBy:"updated_by" }
}, "/scholarships");

registerCrudResource(router, {
  moduleCode: "FINANCE", entityType: "refunds", table: "refunds",
  permissionView: "finance.refunds.view", permissionManage: "finance.manage",
  searchFields: ["refund_number","reason","refund_method","status","external_reference"],
  filterFields: ["payment_id","student_id","status","refund_method"], defaultOrderField: "requested_at",
  fields: { paymentId:"payment_id", studentId:"student_id", refundNumber:"refund_number", amount:"amount", reason:"reason", refundMethod:"refund_method", status:"status", requestedBy:"requested_by", approvedBy:"approved_by", processedBy:"processed_by", requestedAt:"requested_at", approvedAt:"approved_at", processedAt:"processed_at", externalReference:"external_reference" }
}, "/refunds");

router.get("/students/:studentId/account", requirePermission("finance.view"), controller.getFinancialAccount);
router.get("/students/:studentId/charges", requirePermission("finance.charges.view"), controller.getCharges);
router.get("/students/:studentId/invoices", requirePermission("finance.invoices.view"), controller.getInvoices);
router.get("/students/:studentId/payments", requirePermission("finance.payments.view"), controller.getPayments);
router.get("/students/:studentId/refunds", requirePermission("finance.refunds.view"), controller.getRefunds);
router.get("/students/:studentId/scholarships", requirePermission("finance.scholarships.view"), controller.getScholarships);
router.get("/students/:studentId/adjustments", requirePermission("finance.charges.view"), controller.getAdjustments);
router.get("/students/:studentId/transactions", requirePermission("finance.view"), controller.getTransactions);

export default router;
