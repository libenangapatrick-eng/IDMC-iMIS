import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";

const router = Router();
router.use(authenticate);

registerCrudResource(router, {
  moduleCode:"PAYROLL", entityType:"payroll_periods", table:"payroll_periods", permissionView:"payroll.view", permissionManage:"payroll.manage",
  searchFields:["period_code","period_name","status"], filterFields:["institution_id","status"], defaultOrderField:"start_date",
  fields:{ institutionId:"institution_id", periodCode:"period_code", periodName:"period_name", startDate:"start_date", endDate:"end_date", paymentDate:"payment_date", status:"status", notes:"notes", createdBy:"created_by", approvedBy:"approved_by", approvedAt:"approved_at" }
}, "/payroll/periods");

registerCrudResource(router, {
  moduleCode:"PAYROLL", entityType:"payroll_components", table:"payroll_components", permissionView:"payroll.view", permissionManage:"payroll.manage",
  searchFields:["component_code","component_name","component_type","status"], filterFields:["institution_id","component_type","status"],
  fields:{ institutionId:"institution_id", componentCode:"component_code", componentName:"component_name", componentType:"component_type", calculationType:"calculation_type", defaultAmount:"default_amount", defaultPercentage:"default_percentage", taxable:"taxable", pensionable:"pensionable", status:"status" }
}, "/payroll/components");

registerCrudResource(router, {
  moduleCode:"PAYROLL", entityType:"staff_payroll_entries", table:"staff_payroll_entries", permissionView:"payroll.view", permissionManage:"payroll.manage",
  searchFields:["currency_code","bank_name","bank_account_number","payment_reference","status"], filterFields:["payroll_period_id","staff_id","status"], defaultOrderField:"created_at",
  fields:{ payrollPeriodId:"payroll_period_id", staffId:"staff_id", basicSalary:"basic_salary", grossPay:"gross_pay", totalDeductions:"total_deductions", netPay:"net_pay", currencyCode:"currency_code", bankName:"bank_name", bankAccountNumber:"bank_account_number", paymentReference:"payment_reference", status:"status", paidAt:"paid_at", notes:"notes", createdBy:"created_by", updatedBy:"updated_by" }
}, "/payroll/entries");

registerCrudResource(router, {
  moduleCode:"PAYROLL", entityType:"payroll_entry_lines", table:"payroll_entry_lines", permissionView:"payroll.view", permissionManage:"payroll.manage",
  searchFields:["description"], filterFields:["payroll_entry_id","payroll_component_id"],
  fields:{ payrollEntryId:"payroll_entry_id", payrollComponentId:"payroll_component_id", amount:"amount", description:"description" }
}, "/payroll/lines");

registerCrudResource(router, {
  moduleCode: "HUMAN_RESOURCES",
  entityType: "staff",
  table: "staff",
  permissionView: "staff.view",
  permissionManage: "staff.manage",
  searchFields: ["employee_number", "first_name", "middle_name", "last_name", "email", "phone"],
  filterFields: ["institution_id", "department_id", "employment_status", "staff_category", "employment_type"],
  fields: {
    institutionId: "institution_id", userId: "user_id", departmentId: "department_id",
    employeeNumber: "employee_number", staffCategory: "staff_category", employmentType: "employment_type",
    employmentStatus: "employment_status", firstName: "first_name", middleName: "middle_name", lastName: "last_name",
    gender: "gender", dateOfBirth: "date_of_birth", nationality: "nationality", nationalId: "national_id",
    passportNumber: "passport_number", maritalStatus: "marital_status", phone: "phone", email: "email",
    physicalAddress: "physical_address", postalAddress: "postal_address", jobTitle: "job_title",
    appointmentDate: "appointment_date", confirmationDate: "confirmation_date", contractStartDate: "contract_start_date",
    contractEndDate: "contract_end_date", highestQualification: "highest_qualification",
    professionalRegistrationNumber: "professional_registration_number", emergencyContactName: "emergency_contact_name",
    emergencyContactPhone: "emergency_contact_phone", emergencyContactRelationship: "emergency_contact_relationship",
    profilePhotoUrl: "profile_photo_url", notes: "notes"
  }
}, "/staff");

registerCrudResource(router, {
  moduleCode: "HUMAN_RESOURCES", entityType: "staff_employment_history", table: "staff_employment_history",
  permissionView: "staff.view", permissionManage: "staff.manage", searchFields: ["job_title", "reason_for_change"],
  filterFields: ["staff_id", "department_id", "employment_type"], defaultOrderField: "start_date",
  fields: { staffId: "staff_id", departmentId: "department_id", jobTitle: "job_title", employmentType: "employment_type", startDate: "start_date", endDate: "end_date", reasonForChange: "reason_for_change", notes: "notes" }
}, "/employment-history");

registerCrudResource(router, {
  moduleCode: "HUMAN_RESOURCES", entityType: "staff_qualifications", table: "staff_qualifications",
  permissionView: "staff.view", permissionManage: "staff.manage", searchFields: ["qualification_level", "qualification_name", "institution_name", "field_of_study"],
  filterFields: ["staff_id", "verification_status"],
  fields: { staffId: "staff_id", qualificationLevel: "qualification_level", qualificationName: "qualification_name", institutionName: "institution_name", fieldOfStudy: "field_of_study", startYear: "start_year", completionYear: "completion_year", certificateNumber: "certificate_number", verificationStatus: "verification_status", verificationNotes: "verification_notes" }
}, "/qualifications");

registerCrudResource(router, {
  moduleCode: "HUMAN_RESOURCES", entityType: "staff_documents", table: "staff_documents",
  permissionView: "staff.view", permissionManage: "staff.manage", searchFields: ["document_type", "document_name", "document_number"],
  filterFields: ["staff_id", "verification_status"],
  fields: { staffId: "staff_id", documentType: "document_type", documentName: "document_name", documentUrl: "document_url", storagePath: "storage_path", documentNumber: "document_number", issueDate: "issue_date", expiryDate: "expiry_date", verificationStatus: "verification_status", verificationNotes: "verification_notes" }
}, "/documents");

registerCrudResource(router, {
  moduleCode: "HUMAN_RESOURCES", entityType: "staff_leave_types", table: "staff_leave_types",
  permissionView: "leave.view", permissionManage: "leave.manage", searchFields: ["leave_code", "leave_name"], filterFields: ["institution_id", "status"],
  fields: { institutionId: "institution_id", leaveCode: "leave_code", leaveName: "leave_name", annualEntitlement: "annual_entitlement", requiresDocument: "requires_document", requiresApproval: "requires_approval", paidLeave: "paid_leave", carryForwardAllowed: "carry_forward_allowed", maxCarryForwardDays: "max_carry_forward_days", status: "status", description: "description" }
}, "/leave/types");

registerCrudResource(router, {
  moduleCode: "HUMAN_RESOURCES", entityType: "staff_leave_balances", table: "staff_leave_balances",
  permissionView: "leave.view", permissionManage: "leave.manage", searchFields: ["notes"], filterFields: ["staff_id", "leave_type_id", "leave_year"],
  fields: { staffId: "staff_id", leaveTypeId: "leave_type_id", leaveYear: "leave_year", openingBalance: "opening_balance", accruedDays: "accrued_days", carriedForwardDays: "carried_forward_days", usedDays: "used_days", pendingDays: "pending_days", closingAdjustment: "closing_adjustment", notes: "notes" }
}, "/leave/balances");

registerCrudResource(router, {
  moduleCode: "HUMAN_RESOURCES", entityType: "staff_leave_requests", table: "staff_leave_requests",
  permissionView: "leave.view", permissionManage: "leave.manage", searchFields: ["request_number", "reason"], filterFields: ["staff_id", "leave_type_id", "leave_year", "request_status"], defaultOrderField: "submitted_at",
  fields: { staffId: "staff_id", leaveTypeId: "leave_type_id", leaveYear: "leave_year", requestNumber: "request_number", startDate: "start_date", endDate: "end_date", daysRequested: "days_requested", reason: "reason", attachmentUrl: "attachment_url", requestStatus: "request_status", submittedAt: "submitted_at", approvedDays: "approved_days", rejectionReason: "rejection_reason", currentApproverUserId: "current_approver_user_id", finalApprovedBy: "final_approved_by", finalApprovedAt: "final_approved_at" }
}, "/leave/requests");

registerCrudResource(router, {
  moduleCode: "HUMAN_RESOURCES", entityType: "staff_leave_approvals", table: "staff_leave_approvals",
  permissionView: "leave.view", permissionManage: "leave.approve", searchFields: ["decision", "comments"], filterFields: ["leave_request_id", "approver_user_id", "decision"],
  fields: { leaveRequestId: "leave_request_id", approvalLevel: "approval_level", approverUserId: "approver_user_id", decision: "decision", approvedDays: "approved_days", comments: "comments", actionedAt: "actioned_at" }
}, "/leave/approvals");

registerCrudResource(router, {
  moduleCode: "HUMAN_RESOURCES", entityType: "staff_attendance", table: "staff_attendance",
  permissionView: "staff.attendance.view", permissionManage: "staff.attendance.manage", searchFields: ["location", "remarks"], filterFields: ["staff_id", "attendance_date", "attendance_status", "source"], defaultOrderField: "attendance_date",
  fields: { staffId: "staff_id", attendanceDate: "attendance_date", attendanceStatus: "attendance_status", checkIn: "check_in", checkOut: "check_out", lateMinutes: "late_minutes", workedMinutes: "worked_minutes", source: "source", location: "location", remarks: "remarks", markedBy: "marked_by" }
}, "/attendance");

registerCrudResource(router, {
  moduleCode: "HUMAN_RESOURCES", entityType: "staff_attendance_adjustments", table: "staff_attendance_adjustments",
  permissionView: "staff.attendance.view", permissionManage: "staff.attendance.manage", searchFields: ["adjustment_reason", "adjustment_status"], filterFields: ["attendance_id", "adjustment_status"],
  fields: { attendanceId: "attendance_id", requestedBy: "requested_by", reviewedBy: "reviewed_by", oldStatus: "old_status", newStatus: "new_status", oldCheckIn: "old_check_in", newCheckIn: "new_check_in", oldCheckOut: "old_check_out", newCheckOut: "new_check_out", adjustmentReason: "adjustment_reason", adjustmentStatus: "adjustment_status", reviewedAt: "reviewed_at" }
}, "/attendance/adjustments");

registerCrudResource(router, {
  moduleCode: "HUMAN_RESOURCES", entityType: "staff_lifecycle_events", table: "staff_lifecycle_events",
  permissionView: "staff.lifecycle.view", permissionManage: "staff.lifecycle.manage", searchFields: ["event_type", "reason", "reference_number"], filterFields: ["staff_id", "event_type"], defaultOrderField: "effective_date",
  fields: { staffId: "staff_id", eventType: "event_type", effectiveDate: "effective_date", previousStatus: "previous_status", newStatus: "new_status", previousDepartmentId: "previous_department_id", newDepartmentId: "new_department_id", previousJobTitle: "previous_job_title", newJobTitle: "new_job_title", reason: "reason", referenceNumber: "reference_number", notes: "notes", recordedBy: "recorded_by" }
}, "/lifecycle");

export default router;
