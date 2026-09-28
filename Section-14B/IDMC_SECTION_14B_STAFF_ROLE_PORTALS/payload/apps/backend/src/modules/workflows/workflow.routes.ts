import { Router, type NextFunction, type Request, type Response } from "express";
import { getSupabase } from "../../config/database.js";
import { authenticate } from "../../middleware/auth.js";
import { requirePermission } from "../../middleware/rbac.js";
import { createAuditLog } from "../../services/audit.service.js";

const router = Router();
router.use(authenticate);

function fail(res: Response, status: number, message: string): void {
  res.status(status).json({ success: false, message });
}

function actor(req: Request): string | null {
  return req.user?.id ?? null;
}

function requestId(req: Request): string | null {
  const value = req.header("x-request-id");
  return value ? String(value) : null;
}

async function audit(req: Request, actionCode: string, entityType: string, entityId: string, oldValues: unknown, newValues: unknown): Promise<void> {
  try {
    await createAuditLog({
      actorUserId: actor(req),
      actionCode,
      moduleCode: "WORKFLOW",
      entityType,
      entityId,
      oldValues,
      newValues,
      ipAddress: req.ip,
      requestId: requestId(req),
    });
  } catch {
    // Workflow completion must not be converted into a 500 solely because audit storage failed.
  }
}

function transition(current: string, allowed: string[], next: string, res: Response): boolean {
  if (!allowed.includes(current)) {
    fail(res, 409, `Invalid workflow transition: ${current} -> ${next}`);
    return false;
  }
  return true;
}

async function updateById(
  req: Request,
  res: Response,
  next: NextFunction,
  table: string,
  id: string,
  patch: Record<string, unknown>,
  permission: string,
  actionCode: string,
  entityType: string,
): Promise<void> {
  try {
    const supabase = getSupabase();
    const { data: before, error: readError } = await supabase.from(table).select("*").eq("id", id).maybeSingle();
    if (readError) return next(readError);
    if (!before) return fail(res, 404, `${entityType} not found`);

    const { data, error } = await supabase.from(table).update(patch).eq("id", id).select("*").single();
    if (error) return next(error);

    await audit(req, actionCode, entityType, id, before, data);
    res.json({ success: true, data });
  } catch (error) {
    next(error);
  }
}

async function transitionById(
  req: Request,
  res: Response,
  next: NextFunction,
  table: string,
  id: string,
  statusField: string,
  allowed: string[],
  targetStatus: string,
  patch: Record<string, unknown>,
  actionCode: string,
  entityType: string,
): Promise<void> {
  try {
    const supabase = getSupabase();
    const { data: before, error: readError } = await supabase.from(table).select("*").eq("id", id).maybeSingle();
    if (readError) return next(readError);
    if (!before) return fail(res, 404, `${entityType} not found`);
    const current = String(before[statusField] ?? "");
    if (!allowed.includes(current)) return fail(res, 409, `Invalid workflow transition: ${current} -> ${targetStatus}`);
    const { data, error } = await supabase.from(table).update({ ...patch, [statusField]: targetStatus, updated_at: new Date().toISOString() }).eq("id", id).select("*").single();
    if (error) return next(error);
    await audit(req, actionCode, entityType, id, before, data);
    res.json({ success: true, data });
  } catch (error) { next(error); }
}

// ---------------- Admissions ----------------
router.post("/applications/:id/submit", requirePermission("admissions.submit"), async (req, res, next) => {
  const supabase = getSupabase();
  const { data, error } = await supabase.from("applications").select("*").eq("id", String(req.params.id)).maybeSingle();
  if (error) return next(error);
  if (!data) return fail(res, 404, "Application not found");
  if (!transition(data.status, ["DRAFT", "CORRECTION_REQUIRED"], "SUBMITTED", res)) return;
  const [applicantResult, choicesResult, qualificationsResult, documentsResult] = await Promise.all([
    supabase.from("applicants").select("first_name,last_name,email,date_of_birth,gender,nationality,profile_photo_url").eq("id", data.applicant_id).maybeSingle(),
    supabase.from("application_choices").select("id", { count: "exact", head: true }).eq("application_id", data.id),
    supabase.from("academic_qualifications").select("id", { count: "exact", head: true }).eq("applicant_id", data.applicant_id),
    supabase.from("application_documents").select("id", { count: "exact", head: true }).eq("application_id", data.id),
  ]);
  const relatedError = applicantResult.error || choicesResult.error || qualificationsResult.error || documentsResult.error;
  if (relatedError) return next(relatedError);
  const applicant = applicantResult.data;
  const missing: string[] = [];
  if (!applicant?.first_name || !applicant?.last_name || !applicant?.email || !applicant?.date_of_birth || !applicant?.gender || !applicant?.nationality) missing.push("complete applicant profile");
  if (!applicant?.profile_photo_url) missing.push("profile photo");
  if ((choicesResult.count ?? 0) < 1) missing.push("programme choice");
  if ((qualificationsResult.count ?? 0) < 1) missing.push("academic qualification");
  if ((documentsResult.count ?? 0) < 1) missing.push("supporting document");
  const completionPercentage = Math.round(((5 - missing.length) / 5) * 100);
  if (missing.length) {
    await supabase.from("applications").update({ completion_percentage: completionPercentage, updated_at: new Date().toISOString() }).eq("id", data.id);
    return fail(res, 409, `Application is incomplete: ${missing.join(", ")}`);
  }
  const { data: updated, error: updateError } = await supabase.from("applications").update({ status: "SUBMITTED", completion_percentage: 100, submitted_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", String(req.params.id)).select("*").single();
  if (updateError) return next(updateError);
  await audit(req, "APPLICATION_SUBMIT", "applications", String(req.params.id), data, updated);
  res.json({ success: true, data: updated });
});

router.post("/applications/:id/review", requirePermission("admissions.review"), async (req, res, next) => {
  return updateById(req, res, next, "applications", String(req.params.id), { status: "UNDER_REVIEW", reviewed_at: new Date().toISOString(), reviewed_by: actor(req) }, "admissions.review", "APPLICATION_REVIEW", "applications");
});

router.post("/applications/:id/verify", requirePermission("admissions.verify"), async (req, res, next) => {
  const supabase = getSupabase();
  const { data, error } = await supabase.from("applications").select("*").eq("id", String(req.params.id)).maybeSingle();
  if (error) return next(error);
  if (!data) return fail(res, 404, "Application not found");
  if (!['UNDER_REVIEW', 'CORRECTION_REQUIRED'].includes(data.status)) return fail(res, 409, `Application cannot be verified from ${data.status}`);
  const { data: updated, error: updateError } = await supabase.from("applications").update({ verification_status: "VERIFIED", status: "VERIFIED", updated_at: new Date().toISOString() }).eq("id", String(req.params.id)).select("*").single();
  if (updateError) return next(updateError);
  await audit(req, "APPLICATION_VERIFY", "applications", String(req.params.id), data, updated);
  res.json({ success: true, data: updated });
});

router.post("/applications/:id/eligibility", requirePermission("admissions.eligibility"), async (req, res, next) => {
  const result = String(req.body?.status ?? "").toUpperCase();
  if (!["ELIGIBLE", "INELIGIBLE", "CONDITIONAL"].includes(result)) return fail(res, 400, "status must be ELIGIBLE, INELIGIBLE or CONDITIONAL");
  const supabase = getSupabase();
  const { data, error } = await supabase.from("applications").select("*").eq("id", String(req.params.id)).maybeSingle();
  if (error) return next(error);
  if (!data) return fail(res, 404, "Application not found");
  const status = result === "ELIGIBLE" ? "ELIGIBLE" : result === "INELIGIBLE" ? "INELIGIBLE" : "ELIGIBLE";
  const { data: updated, error: updateError } = await supabase.from("applications").update({ eligibility_status: result, status, updated_at: new Date().toISOString() }).eq("id", String(req.params.id)).select("*").single();
  if (updateError) return next(updateError);
  await audit(req, "APPLICATION_ELIGIBILITY", "applications", String(req.params.id), data, updated);
  res.json({ success: true, data: updated });
});

router.post("/admission-decisions/:id/decide", requirePermission("admissions.decide"), async (req, res, next) => {
  const decision = String(req.body?.decision ?? "").toUpperCase();
  if (!["APPROVED", "REJECTED", "CANCELLED"].includes(decision)) return fail(res, 400, "decision must be APPROVED, REJECTED or CANCELLED");
  const supabase = getSupabase();
  const { data, error } = await supabase.from("admission_decisions").select("*").eq("id", String(req.params.id)).maybeSingle();
  if (error) return next(error);
  if (!data) return fail(res, 404, "Admission decision not found");
  if (data.decision_status !== "PENDING") return fail(res, 409, `Decision is already ${data.decision_status}`);
  const patch = { decision_status: decision, decision_date: new Date().toISOString(), decision_reason: req.body?.reason ?? null, approved_by: actor(req), approved_at: decision === "APPROVED" ? new Date().toISOString() : null, updated_at: new Date().toISOString() };
  const { data: updated, error: updateError } = await supabase.from("admission_decisions").update(patch).eq("id", String(req.params.id)).select("*").single();
  if (updateError) return next(updateError);
  await audit(req, "ADMISSION_DECISION", "admission_decisions", String(req.params.id), data, updated);
  res.json({ success: true, data: updated });
});

router.post("/admission-offers/:id/issue", requirePermission("admissions.offer"), async (req, res, next) => {
  const supabase = getSupabase();
  const { data, error } = await supabase.from("admission_offers").select("*").eq("id", String(req.params.id)).maybeSingle();
  if (error) return next(error);
  if (!data) return fail(res, 404, "Admission offer not found");
  if (data.offer_status !== "DRAFT") return fail(res, 409, `Offer cannot be issued from ${data.offer_status}`);
  if (data.decision_id) {
    const { data: decision, error: decisionError } = await supabase.from("admission_decisions").select("decision_status").eq("id", data.decision_id).maybeSingle();
    if (decisionError) return next(decisionError);
    if (!decision || decision.decision_status !== "APPROVED") return fail(res, 409, "Offer requires an approved admission decision");
  }
  const offerNumber = String(req.body?.offer_number ?? data.offer_number ?? "").trim();
  if (!offerNumber) return fail(res, 400, "offer_number is required");
  const { data: updated, error: updateError } = await supabase.from("admission_offers").update({ offer_number: offerNumber, offer_status: "ISSUED", issued_by: actor(req), issued_at: new Date().toISOString(), admission_letter_url: req.body?.admission_letter_url ?? data.admission_letter_url ?? null, joining_instructions_url: req.body?.joining_instructions_url ?? data.joining_instructions_url ?? null, updated_at: new Date().toISOString() }).eq("id", String(req.params.id)).select("*").single();
  if (updateError) return next(updateError);
  await audit(req, "ADMISSION_OFFER_ISSUE", "admission_offers", String(req.params.id), data, updated);
  res.json({ success: true, data: updated });
});

router.post("/admission-acceptances/:id/accept", requirePermission("admissions.accept"), async (req, res, next) => {
  const supabase = getSupabase();
  const { data, error } = await supabase.from("admission_acceptances").select("*").eq("id", String(req.params.id)).maybeSingle();
  if (error) return next(error);
  if (!data) return fail(res, 404, "Admission acceptance record not found");
  if (data.acceptance_status !== "PENDING") return fail(res, 409, `Acceptance is already ${data.acceptance_status}`);
  const { data: updated, error: updateError } = await supabase.from("admission_acceptances").update({ acceptance_status: "ACCEPTED", accepted_at: new Date().toISOString(), accepted_by: actor(req), updated_at: new Date().toISOString() }).eq("id", String(req.params.id)).select("*").single();
  if (updateError) return next(updateError);
  await supabase.from("admission_offers").update({ offer_status: "ACCEPTED", updated_at: new Date().toISOString() }).eq("id", data.admission_offer_id);
  await audit(req, "ADMISSION_ACCEPT", "admission_acceptances", String(req.params.id), data, updated);
  res.json({ success: true, data: updated });
});

router.post("/admission-acceptances/:id/decline", requirePermission("admissions.accept"), async (req, res, next) => {
  const supabase = getSupabase();
  const { data, error } = await supabase.from("admission_acceptances").select("*").eq("id", String(req.params.id)).maybeSingle();
  if (error) return next(error);
  if (!data) return fail(res, 404, "Admission acceptance record not found");
  if (data.acceptance_status !== "PENDING") return fail(res, 409, `Acceptance is already ${data.acceptance_status}`);
  const { data: updated, error: updateError } = await supabase.from("admission_acceptances").update({ acceptance_status: "DECLINED", declined_at: new Date().toISOString(), decline_reason: req.body?.reason ?? "Declined by applicant", accepted_by: actor(req), updated_at: new Date().toISOString() }).eq("id", String(req.params.id)).select("*").single();
  if (updateError) return next(updateError);
  await supabase.from("admission_offers").update({ offer_status: "DECLINED", updated_at: new Date().toISOString() }).eq("id", data.admission_offer_id);
  await audit(req, "ADMISSION_DECLINE", "admission_acceptances", String(req.params.id), data, updated);
  res.json({ success: true, data: updated });
});

// ---------------- Student activation ----------------
router.post("/students/:id/activate", requirePermission("students.activate"), async (req, res, next) => {
  const supabase = getSupabase();
  const { data, error } = await supabase.from("students").select("*").eq("id", String(req.params.id)).maybeSingle();
  if (error) return next(error);
  if (!data) return fail(res, 404, "Student not found");
  if (data.student_status !== "PENDING_ACTIVATION") return fail(res, 409, `Student cannot be activated from ${data.student_status}`);
  const { data: updated, error: updateError } = await supabase.from("students").update({ student_status: "ACTIVE", enrollment_date: data.enrollment_date ?? new Date().toISOString().slice(0,10), activated_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", String(req.params.id)).select("*").single();
  if (updateError) return next(updateError);
  await audit(req, "STUDENT_ACTIVATE", "students", String(req.params.id), data, updated);
  res.json({ success: true, data: updated });
});

// ---------------- Registration ----------------
router.post("/registrations/:id/submit", requirePermission("registration.submit"), async (req, res, next) => {
  const supabase = getSupabase();
  const { data, error } = await supabase.from("student_registrations").select("*").eq("id", String(req.params.id)).maybeSingle();
  if (error) return next(error);
  if (!data) return fail(res, 404, "Student registration not found");
  if (!transition(data.registration_status, ["DRAFT"], "SUBMITTED", res)) return;
  if (data.academic_eligibility_status !== "ELIGIBLE") return fail(res, 409, "Academic eligibility is not CLEARED/ELIGIBLE");
  if (!["CLEARED", "OVERRIDE"].includes(data.finance_eligibility_status)) return fail(res, 409, "Finance eligibility is not cleared");
  if (!["CLEARED", "OVERRIDE"].includes(data.document_eligibility_status)) return fail(res, 409, "Document eligibility is not cleared");
  const { data: updated, error: updateError } = await supabase.from("student_registrations").update({ registration_status: "SUBMITTED", submitted_at: new Date().toISOString(), updated_by: actor(req), updated_at: new Date().toISOString() }).eq("id", String(req.params.id)).select("*").single();
  if (updateError) return next(updateError);
  await audit(req, "REGISTRATION_SUBMIT", "student_registrations", String(req.params.id), data, updated);
  res.json({ success: true, data: updated });
});

router.post("/registrations/:id/approve", requirePermission("registration.approve"), async (req, res, next) => {
  const supabase = getSupabase();
  const { data, error } = await supabase.from("student_registrations").select("*").eq("id", String(req.params.id)).maybeSingle();
  if (error) return next(error);
  if (!data) return fail(res, 404, "Student registration not found");
  if (!["SUBMITTED", "PENDING_APPROVAL"].includes(data.registration_status)) return fail(res, 409, `Registration cannot be approved from ${data.registration_status}`);
  const { data: updated, error: updateError } = await supabase.from("student_registrations").update({ registration_status: "APPROVED", approved_by: actor(req), approved_at: new Date().toISOString(), updated_by: actor(req), updated_at: new Date().toISOString() }).eq("id", String(req.params.id)).select("*").single();
  if (updateError) return next(updateError);
  const { error: approvalError } = await supabase.from("registration_approvals").upsert({ student_registration_id: String(req.params.id), approval_level: Number(req.body?.approval_level ?? 1), approval_role: String(req.body?.approval_role ?? "ACADEMIC"), approval_status: "APPROVED", comments: req.body?.comments ?? null, approved_by: actor(req), approved_at: new Date().toISOString(), updated_at: new Date().toISOString() }, { onConflict: "student_registration_id,approval_level" });
  if (approvalError) return next(approvalError);
  await audit(req, "REGISTRATION_APPROVE", "student_registrations", String(req.params.id), data, updated);
  res.json({ success: true, data: updated });
});

router.post("/registrations/:id/register", requirePermission("registration.register"), async (req, res, next) => {
  return transitionById(req, res, next, "student_registrations", String(req.params.id), "registration_status", ["APPROVED"], "REGISTERED", { updated_by: actor(req) }, "REGISTRATION_REGISTER", "student_registrations");
});

router.post("/registrations/:id/lock", requirePermission("registration.lock"), async (req, res, next) => {
  return transitionById(req, res, next, "student_registrations", String(req.params.id), "registration_status", ["REGISTERED"], "LOCKED", { locked_by: actor(req), locked_at: new Date().toISOString(), updated_by: actor(req) }, "REGISTRATION_LOCK", "student_registrations");
});

router.post("/add-drop/:id/decide", requirePermission("registration.add_drop.decide"), async (req, res, next) => {
  const decision = String(req.body?.decision ?? "").toUpperCase();
  if (!["APPROVED", "REJECTED"].includes(decision)) return fail(res, 400, "decision must be APPROVED or REJECTED");
  return updateById(req, res, next, "course_add_drop_requests", String(req.params.id), { request_status: decision, decision_reason: req.body?.reason ?? null, reviewed_by: actor(req), reviewed_at: new Date().toISOString(), updated_at: new Date().toISOString() }, "registration.add_drop.decide", "ADD_DROP_DECIDE", "course_add_drop_requests");
});

// ---------------- Timetable ----------------
router.post("/timetables/:id/review", requirePermission("timetable.review"), async (req, res, next) => updateById(req, res, next, "timetables", String(req.params.id), { status: "UNDER_REVIEW", updated_by: actor(req), updated_at: new Date().toISOString() }, "timetable.review", "TIMETABLE_REVIEW", "timetables"));
router.post("/timetables/:id/approve", requirePermission("timetable.approve"), async (req, res, next) => updateById(req, res, next, "timetables", String(req.params.id), { status: "APPROVED", updated_by: actor(req), updated_at: new Date().toISOString() }, "timetable.approve", "TIMETABLE_APPROVE", "timetables"));
router.post("/timetables/:id/publish", requirePermission("timetable.publish"), async (req, res, next) => updateById(req, res, next, "timetables", String(req.params.id), { status: "PUBLISHED", published_by: actor(req), published_at: new Date().toISOString(), updated_by: actor(req), updated_at: new Date().toISOString() }, "timetable.publish", "TIMETABLE_PUBLISH", "timetables"));
router.post("/timetables/:id/lock", requirePermission("timetable.lock"), async (req, res, next) => updateById(req, res, next, "timetables", String(req.params.id), { status: "LOCKED", locked_by: actor(req), locked_at: new Date().toISOString(), updated_by: actor(req), updated_at: new Date().toISOString() }, "timetable.lock", "TIMETABLE_LOCK", "timetables"));

// ---------------- Assessments ----------------
router.post("/assessments/:id/open", requirePermission("assessment.open"), async (req, res, next) => updateById(req, res, next, "assessments", String(req.params.id), { status: "OPEN", updated_by: actor(req), updated_at: new Date().toISOString() }, "assessment.open", "ASSESSMENT_OPEN", "assessments"));
router.post("/assessments/:id/submit", requirePermission("assessment.submit"), async (req, res, next) => updateById(req, res, next, "assessments", String(req.params.id), { status: "SUBMITTED", updated_by: actor(req), updated_at: new Date().toISOString() }, "assessment.submit", "ASSESSMENT_SUBMIT", "assessments"));
router.post("/assessments/:id/approve", requirePermission("assessment.approve"), async (req, res, next) => updateById(req, res, next, "assessments", String(req.params.id), { status: "APPROVED", approved_by: actor(req), approved_at: new Date().toISOString(), updated_by: actor(req), updated_at: new Date().toISOString() }, "assessment.approve", "ASSESSMENT_APPROVE", "assessments"));
router.post("/assessments/:id/lock", requirePermission("assessment.lock"), async (req, res, next) => updateById(req, res, next, "assessments", String(req.params.id), { status: "LOCKED", locked_by: actor(req), locked_at: new Date().toISOString(), updated_by: actor(req), updated_at: new Date().toISOString() }, "assessment.lock", "ASSESSMENT_LOCK", "assessments"));

router.post("/assessment-marks/:id/submit", requirePermission("assessment.marks.submit"), async (req, res, next) => transitionById(req,res,next,"assessment_marks",String(req.params.id),"status",["DRAFT"],"SUBMITTED",{ submitted_by: actor(req), submitted_at: new Date().toISOString() },"ASSESSMENT_MARK_SUBMIT","assessment_marks"));
router.post("/assessment-marks/:id/approve", requirePermission("assessment.marks.approve"), async (req, res, next) => transitionById(req,res,next,"assessment_marks",String(req.params.id),"status",["SUBMITTED"],"APPROVED",{ approved_by: actor(req), approved_at: new Date().toISOString() },"ASSESSMENT_MARK_APPROVE","assessment_marks"));
router.post("/assessment-marks/:id/lock", requirePermission("assessment.marks.lock"), async (req, res, next) => transitionById(req,res,next,"assessment_marks",String(req.params.id),"status",["APPROVED"],"LOCKED",{},"ASSESSMENT_MARK_LOCK","assessment_marks"));

router.post("/assessment-corrections/:id/decide", requirePermission("assessment.correction.decide"), async (req, res, next) => {
  const decision = String(req.body?.decision ?? "").toUpperCase();
  if (!["APPROVED", "REJECTED", "CANCELLED"].includes(decision)) return fail(res, 400, "decision must be APPROVED, REJECTED or CANCELLED");
  const supabase = getSupabase();
  const { data: correction, error } = await supabase.from("assessment_mark_corrections").select("*").eq("id", String(req.params.id)).maybeSingle();
  if (error) return next(error);
  if (!correction) return fail(res, 404, "Assessment correction not found");
  if (correction.status !== "PENDING") return fail(res, 409, `Correction is already ${correction.status}`);
  const { data: updated, error: updateError } = await supabase.from("assessment_mark_corrections").update({ status: decision, reviewed_by: actor(req), reviewed_at: new Date().toISOString(), review_comment: req.body?.reason ?? null, updated_at: new Date().toISOString() }).eq("id", String(req.params.id)).select("*").single();
  if (updateError) return next(updateError);
  if (decision === "APPROVED") {
    const markPatch: Record<string, unknown> = {};
    if (correction.new_marks !== null) markPatch.marks = correction.new_marks;
    if (correction.new_grade !== null) markPatch.grade = correction.new_grade;
    if (Object.keys(markPatch).length) {
      markPatch.status = "CORRECTION_PENDING";
      await supabase.from("assessment_marks").update(markPatch).eq("id", correction.assessment_mark_id);
    }
  }
  await audit(req, "ASSESSMENT_CORRECTION_DECIDE", "assessment_mark_corrections", String(req.params.id), correction, updated);
  res.json({ success: true, data: updated });
});

// ---------------- Examinations ----------------
router.post("/examination-candidates/:id/eligibility", requirePermission("examination.eligibility"), async (req, res, next) => {
  const status = String(req.body?.status ?? "").toUpperCase();
  if (!["ELIGIBLE", "INELIGIBLE", "WITHHELD"].includes(status)) return fail(res, 400, "status must be ELIGIBLE, INELIGIBLE or WITHHELD");
  return updateById(req, res, next, "examination_candidates", String(req.params.id), { eligibility_status: status, eligibility_reason: req.body?.reason ?? null, updated_at: new Date().toISOString() }, "examination.eligibility", "EXAM_ELIGIBILITY", "examination_candidates");
});
router.post("/examination-marks/:id/submit", requirePermission("examination.marks.submit"), async (req, res, next) => updateById(req, res, next, "examination_marks", String(req.params.id), { status: "SUBMITTED", submitted_by: actor(req), submitted_at: new Date().toISOString(), updated_at: new Date().toISOString() }, "examination.marks.submit", "EXAM_MARK_SUBMIT", "examination_marks"));
router.post("/examination-marks/:id/approve", requirePermission("examination.marks.approve"), async (req, res, next) => updateById(req, res, next, "examination_marks", String(req.params.id), { status: "APPROVED", approved_by: actor(req), approved_at: new Date().toISOString(), updated_at: new Date().toISOString() }, "examination.marks.approve", "EXAM_MARK_APPROVE", "examination_marks"));
router.post("/examination-marks/:id/lock", requirePermission("examination.marks.lock"), async (req, res, next) => updateById(req, res, next, "examination_marks", String(req.params.id), { status: "LOCKED", locked_by: actor(req), locked_at: new Date().toISOString(), updated_at: new Date().toISOString() }, "examination.marks.lock", "EXAM_MARK_LOCK", "examination_marks"));

// ---------------- Results ----------------
router.post("/course-results/:id/calculate", requirePermission("results.calculate"), async (req, res, next) => {
  try {
    const supabase = getSupabase();
    const { data: before, error: readError } = await supabase.from("course_results").select("*").eq("id", String(req.params.id)).maybeSingle();
    if (readError) return next(readError);
    if (!before) return fail(res, 404, "Course result not found");
    const { data: calculated, error } = await supabase.rpc("calculate_course_result", { p_course_result_id: String(req.params.id) });
    if (error) return next(error);
    await audit(req, "RESULT_CALCULATE", "course_results", String(req.params.id), before, calculated);
    res.json({ success: true, data: calculated });
  } catch (error) { next(error); }
});
router.post("/course-results/:id/submit", requirePermission("results.submit"), async (req, res, next) => transitionById(req,res,next,"course_results",String(req.params.id),"result_status",["CALCULATED"],"SUBMITTED",{ submitted_by: actor(req), submitted_at: new Date().toISOString() },"RESULT_SUBMIT","course_results"));
router.post("/course-results/:id/review", requirePermission("results.review"), async (req, res, next) => transitionById(req,res,next,"course_results",String(req.params.id),"result_status",["SUBMITTED"],"VERIFIED",{},"RESULT_VERIFY","course_results"));
router.post("/course-results/:id/approve", requirePermission("results.approve"), async (req, res, next) => transitionById(req,res,next,"course_results",String(req.params.id),"result_status",["VERIFIED","UNDER_REVIEW"],"APPROVED",{ approved_by: actor(req), approved_at: new Date().toISOString() },"RESULT_APPROVE","course_results"));
router.post("/course-results/:id/publish", requirePermission("results.publish"), async (req, res, next) => transitionById(req,res,next,"course_results",String(req.params.id),"result_status",["APPROVED"],"PUBLISHED",{ published_by: actor(req), published_at: new Date().toISOString() },"RESULT_PUBLISH","course_results"));
router.post("/course-results/:id/lock", requirePermission("results.lock"), async (req, res, next) => transitionById(req,res,next,"course_results",String(req.params.id),"result_status",["PUBLISHED"],"LOCKED",{ locked_by: actor(req), locked_at: new Date().toISOString() },"RESULT_LOCK","course_results"));

// ---------------- Transcripts ----------------
router.post("/transcripts/:id/generate", requirePermission("transcript.generate"), async (req, res, next) => {
  const supabase = getSupabase();
  const { data, error } = await supabase.from("student_transcripts").select("*").eq("id", String(req.params.id)).maybeSingle();
  if (error) return next(error);
  if (!data) return fail(res, 404, "Transcript not found");
  if (!["DRAFT", "GENERATED"].includes(data.transcript_status)) return fail(res, 409, `Transcript cannot be generated from ${data.transcript_status}`);
  const { data: cgpa, error: cgpaError } = await supabase.rpc("calculate_student_cgpa", { p_student_id: data.student_id });
  if (cgpaError) return next(cgpaError);
  const { data: updated, error: updateError } = await supabase.from("student_transcripts").update({ transcript_status: "GENERATED", cgpa, generated_by: actor(req), generated_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", String(req.params.id)).select("*").single();
  if (updateError) return next(updateError);
  await audit(req, "TRANSCRIPT_GENERATE", "student_transcripts", String(req.params.id), data, updated);
  res.json({ success: true, data: updated });
});
router.post("/transcripts/:id/review", requirePermission("transcript.review"), async (req, res, next) => updateById(req, res, next, "student_transcripts", String(req.params.id), { transcript_status: "REVIEW", updated_at: new Date().toISOString() }, "transcript.review", "TRANSCRIPT_REVIEW", "student_transcripts"));
router.post("/transcripts/:id/approve", requirePermission("transcript.approve"), async (req, res, next) => updateById(req, res, next, "student_transcripts", String(req.params.id), { transcript_status: "APPROVED", approved_by: actor(req), approved_at: new Date().toISOString(), updated_at: new Date().toISOString() }, "transcript.approve", "TRANSCRIPT_APPROVE", "student_transcripts"));
router.post("/transcripts/:id/issue", requirePermission("transcript.issue"), async (req, res, next) => updateById(req, res, next, "student_transcripts", String(req.params.id), { transcript_status: "ISSUED", issued_by: actor(req), issued_at: new Date().toISOString(), updated_at: new Date().toISOString() }, "transcript.issue", "TRANSCRIPT_ISSUE", "student_transcripts"));
router.post("/transcripts/:id/revoke", requirePermission("transcript.revoke"), async (req, res, next) => updateById(req, res, next, "student_transcripts", String(req.params.id), { transcript_status: "REVOKED", revoked_by: actor(req), revoked_at: new Date().toISOString(), remarks: req.body?.reason ?? "Revoked", updated_at: new Date().toISOString() }, "transcript.revoke", "TRANSCRIPT_REVOKE", "student_transcripts"));

// ---------------- Graduation / Certificates / Alumni ----------------
router.post("/graduation-clearances/:id/clear", requirePermission("graduation.clearance"), async (req, res, next) => updateById(req, res, next, "graduation_clearances", String(req.params.id), { status: "CLEARED", cleared_by: actor(req), cleared_at: new Date().toISOString(), remarks: req.body?.remarks ?? null, updated_at: new Date().toISOString() }, "graduation.clearance", "GRADUATION_CLEARANCE", "graduation_clearances"));
router.post("/graduation-candidates/:id/eligibility", requirePermission("graduation.eligibility"), async (req, res, next) => {
  const eligibility = String(req.body?.status ?? "").toUpperCase();
  if (!["ELIGIBLE", "INELIGIBLE", "REVIEW"].includes(eligibility)) return fail(res, 400, "status must be ELIGIBLE, INELIGIBLE or REVIEW");
  return updateById(req, res, next, "graduation_candidates", String(req.params.id), { eligibility_status: eligibility, academic_completion_status: eligibility === "ELIGIBLE" ? "COMPLETE" : req.body?.academic_completion_status ?? "PENDING", eligible_at: eligibility === "ELIGIBLE" ? new Date().toISOString() : null, updated_at: new Date().toISOString() }, "graduation.eligibility", "GRADUATION_ELIGIBILITY", "graduation_candidates");
});
router.post("/graduation-candidates/:id/approve", requirePermission("graduation.approve"), async (req, res, next) => {
  const supabase = getSupabase();
  const { data, error } = await supabase.from("graduation_candidates").select("*").eq("id", String(req.params.id)).maybeSingle();
  if (error) return next(error);
  if (!data) return fail(res, 404, "Graduation candidate not found");
  if (data.eligibility_status !== "ELIGIBLE" || data.academic_completion_status !== "COMPLETE") return fail(res, 409, "Candidate must be eligible and academically complete");
  const { data: clearances, error: clearanceError } = await supabase.from("graduation_clearances").select("status").eq("graduation_candidate_id", String(req.params.id));
  if (clearanceError) return next(clearanceError);
  if ((clearances ?? []).length < 1 || (clearances ?? []).some((c) => !["CLEARED", "WAIVED"].includes(c.status))) return fail(res, 409, "All graduation clearances must be CLEARED or WAIVED");
  const { data: updated, error: updateError } = await supabase.from("graduation_candidates").update({ candidate_status: "APPROVED", approved_by: actor(req), approved_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", String(req.params.id)).select("*").single();
  if (updateError) return next(updateError);
  const { error: approvalError } = await supabase.from("graduation_approvals").upsert({ graduation_candidate_id: String(req.params.id), approval_stage: String(req.body?.approval_stage ?? "ACADEMIC"), decision: "APPROVED", comments: req.body?.comments ?? null, approved_by: actor(req), approved_at: new Date().toISOString() }, { onConflict: "graduation_candidate_id,approval_stage" });
  if (approvalError) return next(approvalError);
  await audit(req, "GRADUATION_APPROVE", "graduation_candidates", String(req.params.id), data, updated);
  res.json({ success: true, data: updated });
});
router.post("/graduation-candidates/:id/graduate", requirePermission("graduation.graduate"), async (req, res, next) => {
  return updateById(req, res, next, "graduation_candidates", String(req.params.id), { candidate_status: "GRADUATED", updated_at: new Date().toISOString() }, "graduation.graduate", "GRADUATION_COMPLETE", "graduation_candidates");
});
router.post("/certificates/:id/issue", requirePermission("certificate.issue"), async (req, res, next) => updateById(req, res, next, "certificates", String(req.params.id), { status: "ISSUED", issued_by: actor(req), issue_date: new Date().toISOString().slice(0,10), issued_at: new Date().toISOString(), updated_at: new Date().toISOString() }, "certificate.issue", "CERTIFICATE_ISSUE", "certificates"));
router.post("/certificates/:id/revoke", requirePermission("certificate.revoke"), async (req, res, next) => {
  const reason = String(req.body?.reason ?? "").trim();
  if (!reason) return fail(res, 400, "reason is required");
  return updateById(req, res, next, "certificates", String(req.params.id), { status: "REVOKED", revoked_by: actor(req), revoked_at: new Date().toISOString(), revocation_reason: reason, updated_at: new Date().toISOString() }, "certificate.revoke", "CERTIFICATE_REVOKE", "certificates");
});
router.post("/alumni/:id/activate", requirePermission("alumni.activate"), async (req, res, next) => updateById(req, res, next, "alumni_records", String(req.params.id), { status: "ACTIVE", updated_at: new Date().toISOString() }, "alumni.activate", "ALUMNI_ACTIVATE", "alumni_records"));


/* ============================================================
 * SECTION 11
 * ACCEPTED APPLICATION -> STUDENT
 *
 * Database function:
 * public.convert_accepted_application_to_student(uuid)
 *
 * Idempotency:
 * source_application_id is UNIQUE.
 * Existing student is returned instead of duplicated.
 * ============================================================ */

router.post(
  "/admission-applications/:id/convert-to-student",
  async (req, res, next) => {
    try {
      const supabase = getSupabase();

      const applicationId = String(req.params.id || "").trim();

      if (!applicationId) {
        return res.status(400).json({
          success: false,
          message: "Application ID is required",
        });
      }

      // --------------------------------------------------------
      // 1. Existing student check
      // --------------------------------------------------------

      const {
        data: existingStudent,
        error: existingStudentError,
      } = await supabase
        .from("students")
        .select("*")
        .eq("source_application_id", applicationId)
        .maybeSingle();

      if (existingStudentError) {
        throw existingStudentError;
      }

      if (existingStudent) {
        return res.status(200).json({
          success: true,
          created: false,
          message: "Application already converted to student",
          data: existingStudent,
        });
      }

      // --------------------------------------------------------
      // 2. Verify application
      // --------------------------------------------------------

      const {
        data: application,
        error: applicationError,
      } = await supabase
        .from("applications")
        .select("*")
        .eq("id", applicationId)
        .maybeSingle();

      if (applicationError) {
        throw applicationError;
      }

      if (!application) {
        return res.status(404).json({
          success: false,
          message: "Application not found",
        });
      }

      if (application.status !== "ACCEPTED") {
        return res.status(409).json({
          success: false,
          message:
            `Application cannot be converted from status ${application.status}; expected ACCEPTED`,
        });
      }

      // --------------------------------------------------------
      // 3. Execute canonical database conversion
      // --------------------------------------------------------

      const {
        data: studentId,
        error: conversionError,
      } = await supabase.rpc(
        "convert_accepted_application_to_student",
        {
          p_application_id: applicationId,
        }
      );

      if (conversionError) {
        throw conversionError;
      }

      if (!studentId) {
        throw new Error(
          "Student conversion completed without returning a student ID"
        );
      }

      // --------------------------------------------------------
      // 4. Read final student
      // --------------------------------------------------------

      const {
        data: student,
        error: studentError,
      } = await supabase
        .from("students")
        .select("*")
        .eq("id", studentId)
        .single();

      if (studentError) {
        throw studentError;
      }

      return res.status(201).json({
        success: true,
        created: true,
        message: "Applicant converted to student successfully",
        data: student,
      });
    } catch (error) {
      next(error);
    }
  }
);

export default router;


