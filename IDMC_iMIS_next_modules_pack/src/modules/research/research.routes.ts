import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";

const router = Router();
router.use(authenticate);

registerCrudResource(router, {
  moduleCode: "RESEARCH",
  entityType: "research_projects",
  table: "research_projects",
  permissionView: "research.view",
  permissionManage: "research.manage",
  searchFields: ["project_code","title","funding_source"],
  filterFields: ["institution_id","department_id","project_type","status","principal_investigator_user_id","ethics_status"],
  defaultOrderField: "created_at",
  fields: {
    institutionId:"institution_id", departmentId:"department_id", projectCode:"project_code", title:"title",
    projectType:"project_type", principalInvestigatorUserId:"principal_investigator_user_id",
    startDate:"start_date", endDate:"end_date", status:"status", budgetAmount:"budget_amount",
    fundingSource:"funding_source", abstract:"abstract", objectives:"objectives",
    ethicsRequired:"ethics_required", ethicsStatus:"ethics_status", createdBy:"created_by", updatedBy:"updated_by"
  }
}, "/projects");

registerCrudResource(router, {
  moduleCode: "RESEARCH",
  entityType: "research_team_members",
  table: "research_team_members",
  permissionView: "research.view",
  permissionManage: "research.manage",
  searchFields: ["role_title","notes"],
  filterFields: ["project_id","user_id"],
  defaultOrderField: "joined_at",
  fields: {
    projectId:"project_id", userId:"user_id", roleTitle:"role_title", allocationPercent:"allocation_percent",
    joinedAt:"joined_at", leftAt:"left_at", notes:"notes"
  }
}, "/team-members");

registerCrudResource(router, {
  moduleCode: "RESEARCH",
  entityType: "research_outputs",
  table: "research_outputs",
  permissionView: "research.view",
  permissionManage: "research.manage",
  searchFields: ["title","doi","output_type"],
  filterFields: ["project_id","output_type","status"],
  defaultOrderField: "created_at",
  fields: {
    projectId:"project_id", outputType:"output_type", title:"title", publicationDate:"publication_date",
    doi:"doi", url:"url", fileUrl:"file_url", status:"status", notes:"notes", createdBy:"created_by"
  }
}, "/outputs");

registerCrudResource(router, {
  moduleCode: "RESEARCH",
  entityType: "research_funding",
  table: "research_funding",
  permissionView: "research.view",
  permissionManage: "research.manage",
  searchFields: ["source_name","reference_number"],
  filterFields: ["project_id","funding_status"],
  defaultOrderField: "created_at",
  fields: {
    projectId:"project_id", sourceName:"source_name", referenceNumber:"reference_number",
    amountApproved:"amount_approved", amountReceived:"amount_received", amountSpent:"amount_spent",
    fundingStatus:"funding_status", receivedDate:"received_date", notes:"notes"
  }
}, "/funding");

registerCrudResource(router, {
  moduleCode: "RESEARCH",
  entityType: "research_ethics_reviews",
  table: "research_ethics_reviews",
  permissionView: "research.view",
  permissionManage: "research.manage",
  searchFields: ["reference_number","remarks"],
  filterFields: ["project_id","decision","reviewer_user_id"],
  defaultOrderField: "submission_date",
  fields: {
    projectId:"project_id", submissionDate:"submission_date", reviewDate:"review_date",
    decision:"decision", reviewerUserId:"reviewer_user_id", referenceNumber:"reference_number",
    conditions:"conditions", remarks:"remarks"
  }
}, "/ethics-reviews");

registerCrudResource(router, {
  moduleCode: "QUALITY_ASSURANCE",
  entityType: "quality_standards",
  table: "quality_standards",
  permissionView: "qa.view",
  permissionManage: "qa.manage",
  searchFields: ["standard_code","standard_name"],
  filterFields: ["institution_id","status"],
  defaultOrderField: "created_at",
  fields: {
    institutionId:"institution_id", standardCode:"standard_code", standardName:"standard_name",
    version:"version", description:"description", status:"status", effectiveDate:"effective_date",
    retiredDate:"retired_date", createdBy:"created_by"
  }
}, "/quality/standards");

registerCrudResource(router, {
  moduleCode: "QUALITY_ASSURANCE",
  entityType: "quality_reviews",
  table: "quality_reviews",
  permissionView: "qa.view",
  permissionManage: "qa.manage",
  searchFields: ["review_code","title"],
  filterFields: ["institution_id","standard_id","status","lead_user_id"],
  defaultOrderField: "start_date",
  fields: {
    institutionId:"institution_id", standardId:"standard_id", reviewCode:"review_code", title:"title",
    scope:"scope", leadUserId:"lead_user_id", startDate:"start_date", endDate:"end_date", status:"status",
    overallRating:"overall_rating", findingsSummary:"findings_summary", approvedBy:"approved_by",
    approvedAt:"approved_at", createdBy:"created_by"
  }
}, "/quality/reviews");

registerCrudResource(router, {
  moduleCode: "QUALITY_ASSURANCE",
  entityType: "quality_findings",
  table: "quality_findings",
  permissionView: "qa.view",
  permissionManage: "qa.manage",
  searchFields: ["finding_code","category","finding","root_cause"],
  filterFields: ["review_id","severity","status","owner_user_id"],
  defaultOrderField: "created_at",
  fields: {
    reviewId:"review_id", findingCode:"finding_code", category:"category", severity:"severity",
    finding:"finding", rootCause:"root_cause", evidenceUrl:"evidence_url", status:"status",
    ownerUserId:"owner_user_id", dueDate:"due_date", resolution:"resolution",
    verifiedBy:"verified_by", verifiedAt:"verified_at"
  }
}, "/quality/findings");

registerCrudResource(router, {
  moduleCode: "QUALITY_ASSURANCE",
  entityType: "quality_actions",
  table: "quality_actions",
  permissionView: "qa.view",
  permissionManage: "qa.manage",
  searchFields: ["action_code","action_description","notes"],
  filterFields: ["finding_id","status","responsible_user_id"],
  defaultOrderField: "created_at",
  fields: {
    findingId:"finding_id", actionCode:"action_code", actionDescription:"action_description",
    responsibleUserId:"responsible_user_id", dueDate:"due_date", status:"status",
    completionDate:"completion_date", evidenceUrl:"evidence_url", notes:"notes"
  }
}, "/quality/actions");

export default router;
