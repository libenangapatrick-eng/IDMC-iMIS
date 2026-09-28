import { Router, type NextFunction, type Request, type Response } from "express";
import { getSupabase } from "../../config/database.js";
import { authenticate } from "../../middleware/auth.js";
import { requirePermission } from "../../middleware/rbac.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";

const router = Router();
router.use(authenticate);
const VIEW = "assessment.view";
const MANAGE = "assessment.manage";
const CORRECT = "assessment.corrections.manage";
const TYPES = new Set(["ASSIGNMENT", "QUIZ", "TEST", "PRACTICAL", "PRESENTATION", "PROJECT", "CONTINUOUS_ASSESSMENT", "OTHER"]);
const STATUSES = new Set(["DRAFT", "OPEN", "SUBMITTED", "UNDER_REVIEW", "APPROVED", "LOCKED", "CANCELLED"]);
type Row = Record<string, any>;
type HttpError = Error & { statusCode?: number };

function fail(message: string, statusCode = 400): never { const error = new Error(message) as HttpError; error.statusCode = statusCode; throw error; }
function required(value: unknown, field: string, max = 255): string { const result = String(value ?? "").trim(); if (!result) fail(`${field} is required.`); return result.slice(0, max); }
function numeric(value: unknown, field: string, minimum: number, maximum: number): number { const result = Number(value); if (!Number.isFinite(result) || result < minimum || result > maximum) fail(`${field} must be between ${minimum} and ${maximum}.`); return result; }
function optional(value: unknown, max = 2000): string | null { const result = String(value ?? "").trim(); return result ? result.slice(0, max) : null; }
function byId(rows: Row[] | null) { return new Map((rows ?? []).map(row => [String(row.id), row])); }

async function workspaceData() {
  const db = getSupabase();
  const [assessments, offerings, courses, years, semesters] = await Promise.all([
    db.from("assessments").select("*").order("created_at", { ascending: false }).limit(500),
    db.from("course_offerings").select("id,offering_code,course_id,academic_year_id,semester_id,status").order("created_at", { ascending: false }).limit(500),
    db.from("courses").select("id,course_code,course_name,credit_units,status").limit(1000),
    db.from("academic_years").select("id,year_code,year_name,status").limit(100),
    db.from("semesters").select("id,semester_code,semester_name,status").limit(200),
  ]);
  for (const result of [assessments, offerings, courses, years, semesters]) if (result.error) throw result.error;
  const courseMap = byId(courses.data), yearMap = byId(years.data), semesterMap = byId(semesters.data);
  const labelledOfferings = (offerings.data ?? []).map((offering: Row) => {
    const course = courseMap.get(String(offering.course_id)) ?? {}, year = yearMap.get(String(offering.academic_year_id)) ?? {}, semester = semesterMap.get(String(offering.semester_id)) ?? {};
    const courseLabel = [course.course_code, course.course_name].filter(Boolean).join(" — ") || "Course not linked";
    const periodLabel = [year.year_name || year.year_code, semester.semester_name || semester.semester_code].filter(Boolean).join(" / ");
    return { ...offering, course_code: course.course_code, course_name: course.course_name, credits: course.credit_units, label: `${courseLabel}${periodLabel ? ` | ${periodLabel}` : ""}${offering.offering_code ? ` | ${offering.offering_code}` : ""}` };
  });
  const offeringMap = byId(labelledOfferings);
  return { offerings: labelledOfferings, assessments: (assessments.data ?? []).map((assessment: Row) => ({ ...assessment, course_label: offeringMap.get(String(assessment.course_offering_id))?.label ?? "Course offering not found" })) };
}

router.get("/workspace", requirePermission(VIEW), async (_req: Request, res: Response, next: NextFunction) => { try { res.json({ success: true, data: await workspaceData() }); } catch (error) { next(error); } });

router.post("/workspace/assessments", requirePermission(MANAGE), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const db = getSupabase();
    const courseOfferingId = required(req.body?.courseOfferingId, "Course offering", 80);
    const assessmentCode = required(req.body?.assessmentCode, "Assessment code", 50).toUpperCase();
    const assessmentName = required(req.body?.assessmentName, "Assessment name");
    const assessmentType = required(req.body?.assessmentType, "Assessment type", 40).toUpperCase();
    const maximumMarks = numeric(req.body?.maximumMarks, "Maximum marks", 0.01, 10000);
    const weightPercentage = numeric(req.body?.weightPercentage, "Weight percentage", 0.01, 100);
    const status = String(req.body?.status ?? "DRAFT").trim().toUpperCase();
    if (!TYPES.has(assessmentType)) fail("Choose a valid assessment type.");
    if (!STATUSES.has(status)) fail("Choose a valid assessment status.");
    const offering = await db.from("course_offerings").select("id,status").eq("id", courseOfferingId).maybeSingle();
    if (offering.error) throw offering.error;
    if (!offering.data) fail("The selected course offering does not exist.", 404);
    const weights = await db.from("assessments").select("weight_percentage").eq("course_offering_id", courseOfferingId).neq("status", "CANCELLED");
    if (weights.error) throw weights.error;
    const usedWeight = (weights.data ?? []).reduce((sum, row) => sum + Number(row.weight_percentage || 0), 0);
    if (usedWeight + weightPercentage > 100.0001) fail(`Assessment weights would become ${usedWeight + weightPercentage}%. Only ${Math.max(0, 100 - usedWeight)}% remains.`);
    const saved = await db.from("assessments").insert({ course_offering_id: courseOfferingId, assessment_code: assessmentCode, assessment_name: assessmentName, assessment_type: assessmentType,
      assessment_number: req.body?.assessmentNumber ? Number(req.body.assessmentNumber) : null, maximum_marks: maximumMarks, weight_percentage: weightPercentage,
      due_date: optional(req.body?.dueDate, 10), due_time: optional(req.body?.dueTime, 12), status, instructions: optional(req.body?.instructions), created_by: req.user?.id ?? null, updated_by: req.user?.id ?? null }).select("*").single();
    if (saved.error) {
      if (saved.error.code === "23505") fail("This assessment code already exists for the selected course offering.", 409);
      if (["23514", "23502", "22P02"].includes(saved.error.code)) fail(saved.error.message);
      throw saved.error;
    }
    res.status(201).json({ success: true, data: saved.data });
  } catch (error) { next(error); }
});

router.get("/workspace/assessments/:id/roster", requirePermission(VIEW), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const db = getSupabase();
    const assessment = await db.from("assessments").select("*").eq("id", req.params.id).maybeSingle();
    if (assessment.error) throw assessment.error;
    if (!assessment.data) fail("Assessment was not found.", 404);
    const registrations = await db.from("course_registrations").select("id,student_id,course_offering_id,registration_status").eq("course_offering_id", assessment.data.course_offering_id).in("registration_status", ["APPROVED", "REGISTERED"]);
    if (registrations.error) throw registrations.error;
    const ids = (registrations.data ?? []).map(row => row.student_id);
    const [students, profiles, marks] = await Promise.all([
      ids.length ? db.from("students").select("id,student_number,student_status").in("id", ids) : Promise.resolve({ data: [], error: null }),
      ids.length ? db.from("student_profiles").select("student_id,first_name,middle_name,last_name").in("student_id", ids) : Promise.resolve({ data: [], error: null }),
      db.from("assessment_marks").select("*").eq("assessment_id", req.params.id),
    ]);
    for (const result of [students, profiles, marks]) if (result.error) throw result.error;
    const studentMap = byId(students.data as Row[]), profileMap = new Map((profiles.data ?? []).map((row: Row) => [String(row.student_id), row])), markMap = new Map((marks.data ?? []).map((row: Row) => [String(row.student_id), row]));
    const roster = (registrations.data ?? []).map((registration: Row) => { const student = studentMap.get(String(registration.student_id)) ?? {}, profile = profileMap.get(String(registration.student_id)) ?? {}, mark = markMap.get(String(registration.student_id)); return {
      registrationId: registration.id, studentId: registration.student_id, studentNumber: student.student_number,
      studentName: [profile.first_name, profile.middle_name, profile.last_name].filter(Boolean).join(" ") || "Student", marks: mark?.marks ?? null, remarks: mark?.remarks ?? "", status: mark?.status ?? "DRAFT" }; });
    res.json({ success: true, data: { assessment: assessment.data, roster } });
  } catch (error) { next(error); }
});

router.post("/workspace/assessments/:id/marks", requirePermission(MANAGE), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const db = getSupabase();
    const assessment = await db.from("assessments").select("id,course_offering_id,maximum_marks,status").eq("id", req.params.id).maybeSingle();
    if (assessment.error) throw assessment.error;
    if (!assessment.data) fail("Assessment was not found.", 404);
    const assessmentRow = assessment.data;
    if (assessmentRow.status === "LOCKED") fail("This assessment is locked and marks cannot be changed.", 423);
    const rows = Array.isArray(req.body?.rows) ? req.body.rows : [];
    if (!rows.length) fail("No mark rows were supplied.");
    if (rows.length > 1000) fail("A maximum of 1000 mark rows can be saved at once.");
    const now = new Date().toISOString();
    const payload = rows.map((row: Row) => { const marks = numeric(row.marks, `Marks for ${row.studentNumber || "student"}`, 0, Number(assessmentRow.maximum_marks)); return {
      assessment_id: assessmentRow.id, student_id: required(row.studentId, "Student", 80), course_registration_id: required(row.registrationId, "Course registration", 80), marks,
      percentage: Number(assessmentRow.maximum_marks) ? (marks / Number(assessmentRow.maximum_marks)) * 100 : 0, remarks: optional(row.remarks, 1000), status: "DRAFT", entered_by: req.user?.id ?? null, entered_at: now, updated_at: now }; });
    const saved = await db.from("assessment_marks").upsert(payload, { onConflict: "assessment_id,student_id" }).select("*");
    if (saved.error) { if (["23503", "23514", "23502", "22P02"].includes(saved.error.code)) fail(saved.error.message); throw saved.error; }
    res.json({ success: true, data: saved.data ?? [] });
  } catch (error) { next(error); }
});

registerCrudResource(router,{moduleCode:"ASSESSMENT",entityType:"assessments",table:"assessments",permissionView:VIEW,permissionManage:MANAGE,searchFields:["assessment_code","assessment_name","assessment_type","status"],filterFields:["course_offering_id","assessment_type","status"],defaultOrderField:"due_date",fields:{courseOfferingId:"course_offering_id",assessmentCode:"assessment_code",assessmentName:"assessment_name",assessmentType:"assessment_type",assessmentNumber:"assessment_number",maximumMarks:"maximum_marks",weightPercentage:"weight_percentage",dueDate:"due_date",dueTime:"due_time",status:"status",instructions:"instructions",createdBy:"created_by",updatedBy:"updated_by",approvedBy:"approved_by",approvedAt:"approved_at",lockedBy:"locked_by",lockedAt:"locked_at"}},"/assessments");
registerCrudResource(router,{moduleCode:"ASSESSMENT",entityType:"assessment_submissions",table:"assessment_submissions",permissionView:VIEW,permissionManage:MANAGE,searchFields:["submission_status","submission_reference","remarks"],filterFields:["assessment_id","student_id","submission_status"],defaultOrderField:"submitted_at",fields:{assessmentId:"assessment_id",studentId:"student_id",submittedAt:"submitted_at",submissionStatus:"submission_status",fileId:"file_id",submissionReference:"submission_reference",remarks:"remarks"}},"/submissions");
registerCrudResource(router,{moduleCode:"ASSESSMENT",entityType:"assessment_marks",table:"assessment_marks",permissionView:VIEW,permissionManage:MANAGE,searchFields:["grade","status","remarks"],filterFields:["assessment_id","student_id","course_registration_id","status"],defaultOrderField:"created_at",fields:{assessmentId:"assessment_id",studentId:"student_id",courseRegistrationId:"course_registration_id",marks:"marks",percentage:"percentage",grade:"grade",remarks:"remarks",status:"status",enteredBy:"entered_by",enteredAt:"entered_at",submittedBy:"submitted_by",submittedAt:"submitted_at",approvedBy:"approved_by",approvedAt:"approved_at"}},"/marks");
registerCrudResource(router,{moduleCode:"ASSESSMENT",entityType:"assessment_mark_corrections",table:"assessment_mark_corrections",permissionView:VIEW,permissionManage:CORRECT,searchFields:["reason","status","review_comment"],filterFields:["assessment_mark_id","requested_by","status"],defaultOrderField:"requested_at",fields:{assessmentMarkId:"assessment_mark_id",requestedBy:"requested_by",requestedAt:"requested_at",oldMarks:"old_marks",newMarks:"new_marks",oldGrade:"old_grade",newGrade:"new_grade",reason:"reason",evidenceFileId:"evidence_file_id",status:"status",reviewedBy:"reviewed_by",reviewedAt:"reviewed_at",reviewComment:"review_comment"}},"/mark-corrections");
export default router;
