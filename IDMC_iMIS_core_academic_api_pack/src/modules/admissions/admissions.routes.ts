import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";

const router = Router();
router.use(authenticate);

registerCrudResource(router, {
  moduleCode: "APPLICATIONS", entityType: "applicants", table: "applicants",
  permissionView: "applications.view", permissionManage: "applications.manage",
  searchFields: ["applicant_number","first_name","middle_name","last_name","email","phone","national_id_number","passport_number"],
  filterFields: ["applicant_type","status","nationality","gender"], defaultOrderField: "created_at",
  fields: { applicantNumber:"applicant_number", firstName:"first_name", middleName:"middle_name", lastName:"last_name",
    gender:"gender", dateOfBirth:"date_of_birth", nationality:"nationality", nationalIdNumber:"national_id_number",
    passportNumber:"passport_number", email:"email", phone:"phone", addressLine1:"address_line_1", addressLine2:"address_line_2",
    city:"city", district:"district", region:"region", country:"country", disabilityStatus:"disability_status",
    disabilityDetails:"disability_details", applicantType:"applicant_type", status:"status", authUserId:"auth_user_id" }
}, "/applicants");

registerCrudResource(router, {
  moduleCode: "APPLICATIONS", entityType: "applications", table: "applications",
  permissionView: "applications.view", permissionManage: "applications.manage",
  searchFields: ["application_number","status","payment_status","verification_status","eligibility_status","selection_status"],
  filterFields: ["applicant_id","academic_year_id","application_type","application_round","status","payment_status","verification_status","eligibility_status","selection_status"],
  defaultOrderField: "created_at",
  fields: { applicantId:"applicant_id", academicYearId:"academic_year_id", applicationNumber:"application_number",
    applicationType:"application_type", applicationRound:"application_round", submittedAt:"submitted_at", status:"status",
    paymentStatus:"payment_status", verificationStatus:"verification_status", eligibilityStatus:"eligibility_status",
    selectionStatus:"selection_status", completionPercentage:"completion_percentage", correctionCount:"correction_count",
    correctionDeadline:"correction_deadline", reviewedBy:"reviewed_by", reviewedAt:"reviewed_at", reviewComments:"review_comments" }
}, "/applications");

registerCrudResource(router, {
  moduleCode: "APPLICATIONS", entityType: "application_choices", table: "application_choices",
  permissionView: "applications.view", permissionManage: "applications.manage",
  searchFields: ["choice_number","preference_type","status","decision_reason"], filterFields: ["application_id","programme_id","choice_number","status"],
  defaultOrderField: "created_at", fields: { applicationId:"application_id", programmeId:"programme_id", choiceNumber:"choice_number",
    preferenceType:"preference_type", status:"status", decisionReason:"decision_reason" }
}, "/choices");

registerCrudResource(router, {
  moduleCode: "APPLICATIONS", entityType: "academic_qualifications", table: "academic_qualifications",
  permissionView: "applications.view", permissionManage: "applications.manage",
  searchFields: ["qualification_type","institution_name","award_name","index_number","field_of_study"],
  filterFields: ["applicant_id","qualification_type","verification_status","completion_year"], defaultOrderField: "created_at",
  fields: { applicantId:"applicant_id", qualificationType:"qualification_type", institutionName:"institution_name", country:"country",
    awardName:"award_name", indexNumber:"index_number", registrationNumber:"registration_number", startYear:"start_year",
    completionYear:"completion_year", grade:"grade", gpa:"gpa", fieldOfStudy:"field_of_study", verificationStatus:"verification_status",
    verifiedBy:"verified_by", verifiedAt:"verified_at", verificationComments:"verification_comments" }
}, "/qualifications");

registerCrudResource(router, {
  moduleCode: "APPLICATIONS", entityType: "application_documents", table: "application_documents",
  permissionView: "applications.view", permissionManage: "applications.manage",
  searchFields: ["document_type","document_name","document_number","mime_type","verification_status"],
  filterFields: ["application_id","document_type","verification_status"], defaultOrderField: "uploaded_at",
  fields: { applicationId:"application_id", documentType:"document_type", documentName:"document_name", fileUrl:"file_url",
    fileSize:"file_size", mimeType:"mime_type", documentNumber:"document_number", issueDate:"issue_date", expiryDate:"expiry_date",
    verificationStatus:"verification_status", verifiedBy:"verified_by", verifiedAt:"verified_at", rejectionReason:"rejection_reason", uploadedAt:"uploaded_at" }
}, "/documents");

registerCrudResource(router, {
  moduleCode: "ADMISSIONS", entityType: "admission_decisions", table: "admission_decisions",
  permissionView: "admissions.view", permissionManage: "admissions.manage",
  searchFields: ["decision_type","decision_status","decision_reason"], filterFields: ["application_id","application_choice_id","decision_type","decision_status"],
  defaultOrderField: "decision_date", fields: { applicationId:"application_id", applicationChoiceId:"application_choice_id", decisionType:"decision_type",
    decisionStatus:"decision_status", decisionDate:"decision_date", decisionReason:"decision_reason", capacityCheck:"capacity_check",
    academicCheck:"academic_check", documentCheck:"document_check", approvedBy:"approved_by", approvedAt:"approved_at" }
}, "/admission-decisions");

registerCrudResource(router, {
  moduleCode: "ADMISSIONS", entityType: "admission_offers", table: "admission_offers",
  permissionView: "admissions.view", permissionManage: "admissions.manage",
  searchFields: ["offer_number","offer_status","admission_conditions"], filterFields: ["application_id","programme_id","decision_id","offer_status"],
  defaultOrderField: "offer_date", fields: { applicationId:"application_id", programmeId:"programme_id", decisionId:"decision_id", offerNumber:"offer_number",
    offerDate:"offer_date", expiryDate:"expiry_date", offerStatus:"offer_status", admissionConditions:"admission_conditions",
    admissionLetterUrl:"admission_letter_url", joiningInstructionsUrl:"joining_instructions_url", issuedBy:"issued_by", issuedAt:"issued_at" }
}, "/admission-offers");

registerCrudResource(router, {
  moduleCode: "ADMISSIONS", entityType: "admission_acceptances", table: "admission_acceptances",
  permissionView: "admissions.view", permissionManage: "admissions.manage",
  searchFields: ["acceptance_status","decline_reason"], filterFields: ["admission_offer_id","acceptance_status"], defaultOrderField: "created_at",
  fields: { admissionOfferId:"admission_offer_id", acceptanceStatus:"acceptance_status", acceptedAt:"accepted_at", declinedAt:"declined_at",
    declineReason:"decline_reason", acceptanceIpAddress:"acceptance_ip_address", acceptanceUserAgent:"acceptance_user_agent", acceptedBy:"accepted_by" }
}, "/admission-acceptances");

export default router;
