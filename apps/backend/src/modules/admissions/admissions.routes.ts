import { Router } from "express";
import { randomUUID } from "node:crypto";
import { authenticate } from "../../middleware/auth.js";
import { requirePermission } from "../../middleware/rbac.js";
import { getSupabase } from "../../config/database.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";

const router = Router();
router.use(authenticate);

const wrap = (fn: any) => async (req: any, res: any, next: any) => {
  try { await fn(req, res); } catch (error) { next(error); }
};

async function reconcileConvertedApplication(applicationId: string, actorUserId: string) {
  const db = getSupabase();
  const application = await db.from("applications").select("*").eq("id", applicationId).maybeSingle();
  if (application.error) throw application.error;
  if (!application.data) throw Object.assign(new Error("Application not found."), { statusCode: 404 });
  if (application.data.status !== "CONVERTED_TO_STUDENT") throw Object.assign(new Error("Only a converted application can be reconciled."), { statusCode: 409 });

  const applicant = await db.from("applicants").select("*").eq("id", application.data.applicant_id).maybeSingle();
  if (applicant.error) throw applicant.error;
  if (!applicant.data) throw Object.assign(new Error("The converted application has no applicant record."), { statusCode: 409 });

  let student = await db.from("students").select("*").eq("source_application_id", applicationId).maybeSingle();
  if (student.error) throw student.error;
  if (!student.data) student = await db.from("students").select("*").eq("applicant_id", applicant.data.id).maybeSingle();
  if (student.error) throw student.error;
  if (!student.data) throw Object.assign(new Error("Application is marked converted but no student record exists. Restore or reconvert the admission before creating an account."), { statusCode: 409 });
  if (!applicant.data.auth_user_id) throw Object.assign(new Error("Applicant has no Supabase Auth identity to link."), { statusCode: 409 });

  let publicUser = await db.from("users").select("*").eq("auth_user_id", applicant.data.auth_user_id).maybeSingle();
  if (publicUser.error) throw publicUser.error;
  if (!publicUser.data) {
    const email = String(applicant.data.email || "").trim().toLowerCase();
    if (!email) throw Object.assign(new Error("Applicant email is required before the student account can be linked."), { statusCode: 409 });
    const emailOwner = await db.from("users").select("id,auth_user_id").ilike("email", email).maybeSingle();
    if (emailOwner.error) throw emailOwner.error;
    if (emailOwner.data && emailOwner.data.auth_user_id !== applicant.data.auth_user_id) throw Object.assign(new Error("Applicant email already belongs to another IDMC user."), { statusCode: 409 });
    const created = await db.from("users").insert({
      auth_user_id: applicant.data.auth_user_id,
      user_number: student.data.student_number,
      username: String(student.data.student_number).toLowerCase(),
      first_name: applicant.data.first_name || "Student",
      middle_name: applicant.data.middle_name || null,
      last_name: applicant.data.last_name || student.data.student_number,
      display_name: [applicant.data.first_name, applicant.data.middle_name, applicant.data.last_name].filter(Boolean).join(" "),
      email, phone: applicant.data.phone || null, status: "ACTIVE", email_verified_at: new Date().toISOString()
    }).select("*").single();
    if (created.error) throw created.error;
    publicUser = created;
  }

  if (student.data.user_id !== publicUser.data.id) {
    const linked = await db.from("students").update({ user_id: publicUser.data.id, updated_at: new Date().toISOString() }).eq("id", student.data.id).select("*").single();
    if (linked.error) throw linked.error;
    student.data = linked.data;
  }
  const role = await db.from("roles").select("id").eq("role_code", "STUDENT").eq("status", "ACTIVE").maybeSingle();
  if (role.error) throw role.error;
  if (!role.data) throw Object.assign(new Error("Active STUDENT role is missing."), { statusCode: 409 });
  const assignment = await db.from("user_roles").upsert({ user_id: publicUser.data.id, role_id: role.data.id, assigned_by: actorUserId, status: "ACTIVE" }, { onConflict: "user_id,role_id" });
  if (assignment.error) throw assignment.error;
  return { applicationId, studentId: student.data.id, studentNumber: student.data.student_number, userId: publicUser.data.id, email: publicUser.data.email, linked: true };
}

async function issueAdmissionOffer(applicationId: string, actorUserId: string) {
  const db = getSupabase();
  const application = await db.from("applications").select("*").eq("id", applicationId).maybeSingle();
  if (application.error) throw application.error;
  if (!application.data) throw Object.assign(new Error("Application not found."), { statusCode: 404 });
  if (!['SELECTED', 'ADMISSION_OFFERED'].includes(application.data.status)) {
    throw Object.assign(new Error(`An offer can only be issued for a selected application. Current status: ${application.data.status}.`), { statusCode: 409 });
  }
  const choice = await db.from("application_choices").select("id,programme_id").eq("application_id", applicationId).eq("status", "SELECTED").order("choice_number").limit(1).maybeSingle();
  if (choice.error) throw choice.error;
  if (!choice.data) {
    const fallback = await db.from("application_choices").select("id,programme_id").eq("application_id", applicationId).order("choice_number").limit(1).maybeSingle();
    if (fallback.error) throw fallback.error;
    if (!fallback.data) throw Object.assign(new Error("Select a programme before issuing the admission offer."), { statusCode: 409 });
    choice.data = fallback.data;
  }
  let decision = await db.from("admission_decisions").select("*").eq("application_id", applicationId).eq("decision_status", "APPROVED").limit(1).maybeSingle();
  if (decision.error) throw decision.error;
  if (!decision.data) {
    decision = await db.from("admission_decisions").insert({
      application_id: applicationId, application_choice_id: choice.data.id, decision_type: "SELECTED",
      decision_status: "APPROVED", decision_date: new Date().toISOString(), decision_reason: "Approved by Admissions",
      capacity_check: true, academic_check: true, document_check: true, approved_by: actorUserId, approved_at: new Date().toISOString()
    }).select("*").single();
    if (decision.error) throw decision.error;
  }
  let offer = await db.from("admission_offers").select("*").eq("application_id", applicationId).in("offer_status", ["ISSUED", "ACCEPTED"]).limit(1).maybeSingle();
  if (offer.error) throw offer.error;
  if (!offer.data) {
    const expiry = new Date(); expiry.setUTCDate(expiry.getUTCDate() + 30);
    offer = await db.from("admission_offers").insert({
      application_id: applicationId, programme_id: choice.data.programme_id, decision_id: decision.data.id,
      offer_number: `OFFER-${new Date().getUTCFullYear()}-${randomUUID().slice(0, 8).toUpperCase()}`,
      offer_date: new Date().toISOString().slice(0, 10), expiry_date: expiry.toISOString().slice(0, 10),
      offer_status: "ISSUED", admission_conditions: "Admission approved subject to institutional registration requirements.",
      issued_by: actorUserId, issued_at: new Date().toISOString()
    }).select("*").single();
    if (offer.error) throw offer.error;
  }
  const changed = await db.from("applications").update({ status: "ADMISSION_OFFERED", updated_at: new Date().toISOString() }).eq("id", applicationId);
  if (changed.error) throw changed.error;
  return offer.data;
}

async function convertAcceptedApplication(applicationId: string, actorUserId: string) {
  const db = getSupabase();
  const current = await db.from("applications").select("status").eq("id", applicationId).maybeSingle();
  if (current.error) throw current.error;
  if (!current.data) throw Object.assign(new Error("Application not found."), { statusCode: 404 });
  if (current.data.status === "CONVERTED_TO_STUDENT") return reconcileConvertedApplication(applicationId, actorUserId);
  if (current.data.status !== "ACCEPTED") throw Object.assign(new Error(`Only an accepted offer can create a student. Current status: ${current.data.status}.`), { statusCode: 409 });
  const converted = await db.rpc("convert_accepted_application_to_student", { p_application_id: applicationId });
  if (converted.error) throw converted.error;
  return reconcileConvertedApplication(applicationId, actorUserId);
}

router.get("/workspace", requirePermission("applications.view"), wrap(async (_req: any, res: any) => {
  const db = getSupabase();
  const [applications, applicants, choices, qualifications, documents, programmes, students, users, flag] = await Promise.all([
    db.from("applications").select("*").order("created_at", { ascending: false }).limit(500),
    db.from("applicants").select("id,applicant_number,first_name,middle_name,last_name,email,phone,status").limit(1000),
    db.from("application_choices").select("*").limit(2000),
    db.from("academic_qualifications").select("*").limit(2000),
    db.from("application_documents").select("*").limit(3000),
    db.from("programmes").select("id,programme_code,programme_name,status").limit(1000),
    db.from("students").select("id,student_number,registration_number,applicant_id,source_application_id,user_id,student_status").limit(2000),
    db.from("users").select("id,user_number,email,status").limit(3000),
    db.from("system_feature_flags").select("is_enabled,updated_at").eq("feature_code", "ONLINE_APPLICATIONS").limit(1).maybeSingle(),
  ]);
  for (const result of [applications, applicants, choices, qualifications, documents, programmes, students, users, flag]) {
    if (result.error) throw result.error;
  }
  res.json({ success: true, data: {
    onlineApplicationsOpen: flag.data ? Boolean(flag.data.is_enabled) : true,
    applications: applications.data ?? [], applicants: applicants.data ?? [], choices: choices.data ?? [],
    qualifications: qualifications.data ?? [], documents: documents.data ?? [], programmes: programmes.data ?? [],
    students: students.data ?? [], users: users.data ?? []
  }});
}));

router.post("/review/bulk", requirePermission("applications.manage"), wrap(async (req: any, res: any) => {
  const action = String(req.body?.action || "").toUpperCase();
  const ids: string[] = Array.from(new Set<string>((Array.isArray(req.body?.applicationIds) ? req.body.applicationIds : []).map((id: any) => String(id)))).slice(0, 500);
  if (!ids.length) return res.status(400).json({ success: false, message: "Select at least one application." });
  if (!['CONFIRM','VERIFY_ALL','MARK_ELIGIBLE','SELECT','RECONCILE'].includes(action)) return res.status(400).json({ success: false, message: "Unsupported bulk action." });
  const db = getSupabase(), completed: any[] = [], failed: any[] = [], now = new Date().toISOString();
  for (const id of ids) {
    try {
      const app = await db.from("applications").select("*").eq("id", id).maybeSingle();
      if (app.error) throw app.error;
      if (!app.data) throw new Error("Application not found.");
      if (action === "RECONCILE") { completed.push(await reconcileConvertedApplication(id, req.user!.id)); continue; }
      if (action === "CONFIRM") {
        if (app.data.status !== "SUBMITTED") throw new Error(`Status is ${app.data.status}; expected SUBMITTED.`);
        const changed = await db.from("applications").update({ status: "UNDER_REVIEW", verification_status: "IN_PROGRESS", reviewed_by: req.user!.id, reviewed_at: now, updated_at: now }).eq("id", id);
        if (changed.error) throw changed.error;
      } else {
        const qualifications = await db.from("academic_qualifications").select("id").eq("applicant_id", app.data.applicant_id);
        const documents = await db.from("application_documents").select("id").eq("application_id", id);
        if (qualifications.error) throw qualifications.error;
        if (documents.error) throw documents.error;
        if (!(qualifications.data ?? []).length) throw new Error("No qualification is attached.");
        if (!(documents.data ?? []).length) throw new Error("No certificate document is attached.");
        if (action === "VERIFY_ALL") {
          const q = await db.from("academic_qualifications").update({ verification_status: "VERIFIED", verified_by: req.user!.id, verified_at: now, updated_at: now }).eq("applicant_id", app.data.applicant_id);
          const d = await db.from("application_documents").update({ verification_status: "VERIFIED", verified_by: req.user!.id, verified_at: now, rejection_reason: null, updated_at: now }).eq("application_id", id);
          if (q.error) throw q.error; if (d.error) throw d.error;
        } else {
          const q = await db.from("academic_qualifications").select("verification_status").eq("applicant_id", app.data.applicant_id);
          const d = await db.from("application_documents").select("verification_status").eq("application_id", id);
          if ((q.data ?? []).some((row: any) => row.verification_status !== "VERIFIED") || (d.data ?? []).some((row: any) => row.verification_status !== "VERIFIED")) throw new Error("Verify all qualifications and documents first.");
          const status = action === "SELECT" ? "SELECTED" : "ELIGIBLE";
          const changed = await db.from("applications").update({ status, verification_status: "VERIFIED", eligibility_status: "ELIGIBLE", selection_status: action === "SELECT" ? "SELECTED" : app.data.selection_status, reviewed_by: req.user!.id, reviewed_at: now, updated_at: now }).eq("id", id);
          if (changed.error) throw changed.error;
        }
      }
      completed.push({ applicationId: id, action });
    } catch (error: any) { failed.push({ applicationId: id, message: error?.message || "Action failed." }); }
  }
  res.status(failed.length ? 207 : 200).json({ success: failed.length === 0, data: { completed, failed }, message: `${completed.length} completed; ${failed.length} failed.` });
}));

router.post("/reconcile-converted/:id", requirePermission("admissions.manage"), wrap(async (req: any, res: any) => {
  const result = await reconcileConvertedApplication(String(req.params.id), req.user!.id);
  res.json({ success: true, data: result, message: `Student ${result.studentNumber} is linked to an active IDMC user and STUDENT role.` });
}));

router.post("/review/:id/issue-offer", requirePermission("admissions.manage"), wrap(async (req: any, res: any) => {
  const offer = await issueAdmissionOffer(String(req.params.id), req.user!.id);
  res.status(201).json({ success: true, data: offer, message: `Admission offer ${offer.offer_number} issued. The applicant must accept it before student conversion.` });
}));

router.post("/review/:id/convert", requirePermission("admissions.manage"), wrap(async (req: any, res: any) => {
  const result = await convertAcceptedApplication(String(req.params.id), req.user!.id);
  res.json({ success: true, data: result, message: `Student ${result.studentNumber} created and linked successfully.` });
}));

router.post("/review/:id/archive", requirePermission("applications.archive"), wrap(async (req: any, res: any) => {
  const reason = String(req.body?.reason || "").trim().slice(0, 2000);
  if (!reason) return res.status(400).json({ success: false, message: "Enter the archive reason." });
  const db = getSupabase();
  const current = await db.from("applications").select("id,status").eq("id", req.params.id).maybeSingle();
  if (current.error) throw current.error;
  if (!current.data) return res.status(404).json({ success: false, message: "Application not found." });
  if (current.data.status === "CONVERTED_TO_STUDENT") return res.status(409).json({ success: false, message: "A converted application cannot be archived. Use the controlled student status workflow." });
  const result = await db.from("applications").update({ status: "CANCELLED", archived_at: new Date().toISOString(), archived_by: req.user!.id, archive_reason: reason, updated_at: new Date().toISOString() }).eq("id", req.params.id).select().single();
  if (result.error) throw result.error;
  res.json({ success: true, data: result.data, message: "Application archived. Its audit history was retained." });
}));

router.post("/online-publication", requirePermission("admissions.manage"), wrap(async (req: any, res: any) => {
  if (typeof req.body?.open !== "boolean") return res.status(400).json({ success: false, message: "The open field must be true or false." });
  const db = getSupabase();
  const institution = await db.from("institutions").select("id").eq("status", "ACTIVE").limit(1).maybeSingle();
  if (institution.error) throw institution.error;
  if (!institution.data) return res.status(409).json({ success: false, message: "Configure an active institution first." });
  const payload = {
    institution_id: institution.data.id, feature_code: "ONLINE_APPLICATIONS", feature_name: "Online Applications",
    is_enabled: req.body.open, rollout_percentage: 100, description: "Controls publication of the public online application service.",
    updated_by: req.user!.id, updated_at: new Date().toISOString()
  };
  const result = await db.from("system_feature_flags").upsert(payload, { onConflict: "institution_id,feature_code" }).select().single();
  if (result.error) throw result.error;
  res.json({ success: true, data: result.data, message: req.body.open ? "Online applications are now open." : "Online applications are now closed." });
}));

router.post("/review/:id/confirm", requirePermission("applications.manage"), wrap(async (req: any, res: any) => {
  const db = getSupabase();
  const current = await db.from("applications").select("id,status").eq("id", req.params.id).maybeSingle();
  if (current.error) throw current.error;
  if (!current.data) return res.status(404).json({ success: false, message: "Application not found." });
  if (!["SUBMITTED", "CORRECTION_REQUIRED"].includes(current.data.status)) return res.status(409).json({ success: false, message: `Only a submitted application can be confirmed. Current status: ${current.data.status}.` });
  const now = new Date().toISOString();
  const result = await db.from("applications").update({ status: "UNDER_REVIEW", verification_status: "IN_PROGRESS", reviewed_by: req.user!.id, reviewed_at: now, review_comments: String(req.body?.comments || "Application received and confirmed by Admissions.").slice(0, 2000), updated_at: now }).eq("id", req.params.id).select().single();
  if (result.error) throw result.error;
  res.json({ success: true, data: result.data, message: "Application confirmed and moved to review." });
}));

router.post("/review/:id/decision", requirePermission("applications.manage"), wrap(async (req: any, res: any) => {
  const decision = String(req.body?.decision || "").toUpperCase();
  if (!["REQUEST_CORRECTION", "MARK_ELIGIBLE", "SELECT", "REJECT"].includes(decision)) return res.status(400).json({ success: false, message: "Unsupported admission decision." });
  const db = getSupabase();
  const current = await db.from("applications").select("*").eq("id", req.params.id).maybeSingle();
  if (current.error) throw current.error;
  if (!current.data) return res.status(404).json({ success: false, message: "Application not found." });
  if (!["UNDER_REVIEW", "VERIFIED", "ELIGIBLE", "CORRECTION_REQUIRED"].includes(current.data.status)) return res.status(409).json({ success: false, message: `Application decision is not allowed while status is ${current.data.status}.` });
  const comments = String(req.body?.comments || "").trim().slice(0, 2000);
  if (["REQUEST_CORRECTION", "REJECT"].includes(decision) && !comments) return res.status(400).json({ success: false, message: "Enter the reason for this decision." });
  const now = new Date().toISOString();
  const update: Record<string, any> = { reviewed_by: req.user!.id, reviewed_at: now, review_comments: comments || current.data.review_comments, updated_at: now };
  if (decision === "REQUEST_CORRECTION") Object.assign(update, { status: "CORRECTION_REQUIRED", verification_status: "CORRECTION_REQUIRED" });
  if (decision === "MARK_ELIGIBLE" || decision === "SELECT") {
    const [qualifications, documents] = await Promise.all([
      db.from("academic_qualifications").select("id,verification_status").eq("applicant_id", current.data.applicant_id),
      db.from("application_documents").select("id,verification_status").eq("application_id", current.data.id)
    ]);
    if (qualifications.error) throw qualifications.error;
    if (documents.error) throw documents.error;
    if (!(qualifications.data ?? []).length || (qualifications.data ?? []).some(row => row.verification_status !== "VERIFIED")) return res.status(409).json({ success: false, message: "Verify every academic qualification before marking the application eligible." });
    if (!(documents.data ?? []).length || (documents.data ?? []).some(row => row.verification_status !== "VERIFIED")) return res.status(409).json({ success: false, message: "Verify every required document before marking the application eligible." });
    Object.assign(update, { status: decision === "SELECT" ? "SELECTED" : "ELIGIBLE", verification_status: "VERIFIED", eligibility_status: "ELIGIBLE" });
    if (decision === "SELECT") update.selection_status = "SELECTED";
  }
  if (decision === "REJECT") Object.assign(update, { status: "REJECTED", eligibility_status: "INELIGIBLE", selection_status: "NOT_SELECTED" });
  const result = await db.from("applications").update(update).eq("id", current.data.id).select().single();
  if (result.error) throw result.error;
  res.json({ success: true, data: result.data, message: decision === "SELECT" ? "Applicant selected. Joining instructions are now available." : "Admission decision saved." });
}));

router.post("/review/qualifications/:id", requirePermission("applications.manage"), wrap(async (req: any, res: any) => {
  const decision = String(req.body?.decision || "").toUpperCase();
  if (!["VERIFIED", "REJECTED", "REQUIRES_REVIEW"].includes(decision)) return res.status(400).json({ success: false, message: "Decision must be VERIFIED, REJECTED or REQUIRES_REVIEW." });
  const result = await getSupabase().from("academic_qualifications").update({ verification_status: decision, verified_by: req.user!.id, verified_at: new Date().toISOString(), verification_comments: String(req.body?.comments || "").slice(0, 4000), updated_at: new Date().toISOString() }).eq("id", req.params.id).select().single();
  if (result.error) throw result.error;
  res.json({ success: true, data: result.data });
}));

router.post("/review/documents/:id", requirePermission("applications.manage"), wrap(async (req: any, res: any) => {
  const decision = String(req.body?.decision || "").toUpperCase();
  if (!["VERIFIED", "REJECTED", "CORRECTION_REQUIRED"].includes(decision)) return res.status(400).json({ success: false, message: "Decision must be VERIFIED, REJECTED or CORRECTION_REQUIRED." });
  const now = new Date().toISOString();
  const result = await getSupabase().from("application_documents").update({ verification_status: decision, verified_by: req.user!.id, verified_at: now, rejection_reason: decision === "VERIFIED" ? null : String(req.body?.comments || "Reason required").slice(0, 2000), updated_at: now }).eq("id", req.params.id).select().single();
  if (result.error) throw result.error;
  res.json({ success: true, data: result.data });
}));

router.get("/review/documents/:id/access", requirePermission("applications.view"), wrap(async (req: any, res: any) => {
  const db = getSupabase();
  const document = await db.from("application_documents").select("id,document_name,file_url").eq("id", req.params.id).maybeSingle();
  if (document.error) throw document.error;
  if (!document.data) return res.status(404).json({ success: false, message: "Document not found." });
  const signed = await db.storage.from("idmc-private-documents").createSignedUrl(document.data.file_url, 600);
  if (signed.error) throw signed.error;
  res.json({ success: true, data: { documentName: document.data.document_name, url: signed.data.signedUrl, expiresIn: 600 } });
}));

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
