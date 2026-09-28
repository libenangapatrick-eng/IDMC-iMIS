import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";

const router = Router();
router.use(authenticate);

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "library_items", table: "library_items", permissionView: "library.view", permissionManage: "library.manage",
  searchFields: ["accession_number", "title", "author", "isbn", "subject", "call_number"], filterFields: ["institution_id", "item_type", "item_status"], defaultOrderField: "created_at",
  fields: { institutionId: "institution_id", accessionNumber: "accession_number", title: "title", subtitle: "subtitle", itemType: "item_type", isbn: "isbn", author: "author", publisher: "publisher", publicationYear: "publication_year", edition: "edition", subject: "subject", callNumber: "call_number", language: "language", totalCopies: "total_copies", availableCopies: "available_copies", location: "location", itemStatus: "item_status", description: "description" }
}, "/items");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "library_members", table: "library_members", permissionView: "library.view", permissionManage: "library.manage",
  searchFields: ["membership_number", "membership_type"], filterFields: ["institution_id", "student_id", "staff_id", "membership_status", "membership_type"],
  fields: { institutionId: "institution_id", studentId: "student_id", staffId: "staff_id", membershipNumber: "membership_number", membershipType: "membership_type", membershipStatus: "membership_status", registrationDate: "registration_date", expiryDate: "expiry_date", maxActiveLoans: "max_active_loans" }
}, "/members");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "library_loans", table: "library_loans", permissionView: "library.view", permissionManage: "library.issue",
  searchFields: ["loan_number", "loan_status", "notes"], filterFields: ["library_member_id", "library_item_id", "loan_status"], defaultOrderField: "loan_date",
  fields: { libraryMemberId: "library_member_id", libraryItemId: "library_item_id", loanNumber: "loan_number", loanDate: "loan_date", dueDate: "due_date", returnDate: "return_date", quantity: "quantity", loanStatus: "loan_status", issuedBy: "issued_by", returnedTo: "returned_to", notes: "notes" }
}, "/loans");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "library_fines", table: "library_fines", permissionView: "library.view", permissionManage: "library.fines.manage",
  searchFields: ["fine_type", "reason", "fine_status"], filterFields: ["loan_id", "member_id", "fine_status", "fine_type"],
  fields: { loanId: "loan_id", memberId: "member_id", fineType: "fine_type", amount: "amount", amountPaid: "amount_paid", currency: "currency", fineStatus: "fine_status", reason: "reason", waivedBy: "waived_by", waivedAt: "waived_at" }
}, "/fines");

registerCrudResource(router, {
  moduleCode: "OPERATIONS", entityType: "library_reservations", table: "library_reservations", permissionView: "library.view", permissionManage: "library.manage",
  searchFields: ["reservation_status", "notes"], filterFields: ["library_member_id", "library_item_id", "reservation_status"],
  fields: { libraryMemberId: "library_member_id", libraryItemId: "library_item_id", reservationDate: "reservation_date", expiryDate: "expiry_date", reservationStatus: "reservation_status", fulfilledAt: "fulfilled_at", notes: "notes" }
}, "/reservations");

export default router;
