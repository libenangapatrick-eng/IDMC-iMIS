import { Router, type NextFunction, type Request, type Response } from "express";
import { authenticate } from "../../middleware/auth.js";
import { requirePermission } from "../../middleware/rbac.js";
import { getSupabase } from "../../config/database.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";
import resultImportRoutes from "./result-import.routes.js";
const router=Router(); router.use(authenticate);
const VIEW="results.view", MANAGE="results.manage", APPROVE="results.approve", CORRECT="results.corrections.manage";
router.use("/imports", resultImportRoutes);

type ReferenceRow = Record<string, any>;
function referenceMap(rows: ReferenceRow[] | null) { return new Map((rows ?? []).map(row => [String(row.id), row])); }

router.get("/entry/reference", requirePermission(VIEW), async (_req: Request, res: Response, next: NextFunction) => {
  try {
    const db = getSupabase();
    const [offerings, courses, years, semesters, policies] = await Promise.all([
      db.from("course_offerings").select("id,offering_code,course_id,academic_year_id,semester_id,status").order("created_at", { ascending: false }).limit(500),
      db.from("courses").select("id,course_code,course_name,credit_units,status").limit(1000),
      db.from("academic_years").select("id,year_code,year_name,status").limit(100),
      db.from("semesters").select("id,semester_code,semester_name,status").limit(200),
      db.from("course_result_policies").select("id,course_offering_id,status,coursework_weight,examination_weight").limit(500),
    ]);
    for (const result of [offerings, courses, years, semesters, policies]) if (result.error) throw result.error;
    const courseMap = referenceMap(courses.data), yearMap = referenceMap(years.data), semesterMap = referenceMap(semesters.data);
    const policyMap = new Map((policies.data ?? []).filter(row => ["ACTIVE", "LOCKED"].includes(row.status)).map(row => [String(row.course_offering_id), row]));
    const data = (offerings.data ?? []).map((offering: ReferenceRow) => {
      const course = courseMap.get(String(offering.course_id)) ?? {}, year = yearMap.get(String(offering.academic_year_id)) ?? {}, semester = semesterMap.get(String(offering.semester_id)) ?? {}, policy = policyMap.get(String(offering.id));
      return { ...offering, courseCode: course.course_code, courseName: course.course_name, credits: course.credit_units,
        academicYear: year.year_name || year.year_code, semester: semester.semester_code || semester.semester_name,
        policyReady: Boolean(policy), policyStatus: policy?.status ?? "MISSING", courseworkWeight: policy?.coursework_weight ?? null, examinationWeight: policy?.examination_weight ?? null,
        label: `${course.course_code || "NO-CODE"} — ${course.course_name || "Course not linked"} | ${year.year_name || year.year_code || "No year"} / ${semester.semester_name || semester.semester_code || "No semester"}` };
    });
    res.json({ success: true, data });
  } catch (error) { next(error); }
});

router.get("/entry/grade-scales", requirePermission(VIEW), async (_req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await getSupabase().from("grade_scales").select("id,scale_code,scale_name,status,is_default").in("status", ["ACTIVE", "LOCKED"]).order("is_default", { ascending: false });
    if (result.error) throw result.error;
    res.json({ success: true, data: result.data ?? [] });
  } catch (error) { next(error); }
});

router.post("/entry/policy", requirePermission(MANAGE), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const courseOfferingId = String(req.body?.courseOfferingId ?? "").trim(), gradeScaleId = String(req.body?.gradeScaleId ?? "").trim();
    const courseworkWeight = Number(req.body?.courseworkWeight), examinationWeight = Number(req.body?.examinationWeight), minimumPassMark = Number(req.body?.minimumPassMark);
    if (!courseOfferingId || !gradeScaleId) return res.status(400).json({ success: false, message: "Course offering and grade scale are required." });
    if (![courseworkWeight, examinationWeight, minimumPassMark].every(Number.isFinite)) return res.status(400).json({ success: false, message: "Policy marks and weights must be valid numbers." });
    if (courseworkWeight < 0 || examinationWeight < 0 || Math.abs(courseworkWeight + examinationWeight - 100) > 0.0001) return res.status(400).json({ success: false, message: "Coursework and examination weights must total exactly 100%." });
    if (minimumPassMark < 0 || minimumPassMark > 100) return res.status(400).json({ success: false, message: "Minimum pass mark must be between 0 and 100." });
    const db = getSupabase();
    const [offering, scale] = await Promise.all([db.from("course_offerings").select("id").eq("id", courseOfferingId).maybeSingle(), db.from("grade_scales").select("id,status").eq("id", gradeScaleId).maybeSingle()]);
    if (offering.error) throw offering.error; if (scale.error) throw scale.error;
    if (!offering.data || !scale.data) return res.status(404).json({ success: false, message: "Course offering or grade scale was not found." });
    const saved = await db.from("course_result_policies").upsert({ course_offering_id: courseOfferingId, grade_scale_id: gradeScaleId, coursework_weight: courseworkWeight,
      examination_weight: examinationWeight, minimum_coursework_required: req.body?.minimumCourseworkRequired === "" ? null : Number(req.body?.minimumCourseworkRequired),
      minimum_exam_required: req.body?.minimumExamRequired === "" ? null : Number(req.body?.minimumExamRequired), minimum_pass_mark: minimumPassMark,
      status: "ACTIVE", created_by: req.user?.id ?? null, approved_by: req.user?.id ?? null, approved_at: new Date().toISOString(), updated_at: new Date().toISOString() }, { onConflict: "course_offering_id" }).select("*").single();
    if (saved.error) {
      if (["23503", "23514", "23502", "22P02"].includes(saved.error.code)) return res.status(400).json({ success: false, message: saved.error.message });
      throw saved.error;
    }
    res.json({ success: true, data: saved.data });
  } catch (error) { next(error); }
});

router.get("/entry/roster/:courseOfferingId", requirePermission(VIEW), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const db = getSupabase(), id = String(req.params.courseOfferingId);
    const offering = await db.from("course_offerings").select("id,course_id,academic_year_id,semester_id,status").eq("id", id).maybeSingle();
    if (offering.error) throw offering.error;
    if (!offering.data) return res.status(404).json({ success: false, message: "Course offering was not found." });
    const [course, year, semester, registrations, policy] = await Promise.all([
      db.from("courses").select("id,course_code,course_name,credit_units").eq("id", offering.data.course_id).maybeSingle(),
      db.from("academic_years").select("id,year_code,year_name").eq("id", offering.data.academic_year_id).maybeSingle(),
      db.from("semesters").select("id,semester_code,semester_name").eq("id", offering.data.semester_id).maybeSingle(),
      db.from("course_registrations").select("id,student_id,credits,registration_status").eq("course_offering_id", id).in("registration_status", ["APPROVED", "REGISTERED"]),
      db.from("course_result_policies").select("*").eq("course_offering_id", id).in("status", ["ACTIVE", "LOCKED"]).maybeSingle(),
    ]);
    for (const result of [course, year, semester, registrations, policy]) if (result.error) throw result.error;
    const studentIds = (registrations.data ?? []).map(row => row.student_id);
    const [students, profiles, existing] = await Promise.all([
      studentIds.length ? db.from("students").select("id,student_number,student_status").in("id", studentIds) : Promise.resolve({ data: [], error: null }),
      studentIds.length ? db.from("student_profiles").select("student_id,first_name,middle_name,last_name").in("student_id", studentIds) : Promise.resolve({ data: [], error: null }),
      db.from("course_results").select("student_id,coursework_mark,examination_mark,result_type,result_status,remarks").eq("course_offering_id", id),
    ]);
    for (const result of [students, profiles, existing]) if (result.error) throw result.error;
    const studentMap = referenceMap(students.data as ReferenceRow[]), profileMap = new Map((profiles.data ?? []).map((row: ReferenceRow) => [String(row.student_id), row])), resultMap = new Map((existing.data ?? []).map((row: ReferenceRow) => [String(row.student_id), row]));
    const roster = (registrations.data ?? []).map((registration: ReferenceRow) => { const student = studentMap.get(String(registration.student_id)) ?? {}, profile = profileMap.get(String(registration.student_id)) ?? {}, result = resultMap.get(String(registration.student_id)); return {
      studentNumber: student.student_number, studentName: [profile.first_name, profile.middle_name, profile.last_name].filter(Boolean).join(" ") || "Student",
      coursework: result?.coursework_mark ?? "", examination: result?.examination_mark ?? "", resultType: result?.result_type ?? "NORMAL", remarks: result?.remarks ?? "", status: result?.result_status ?? "NEW" }; });
    res.json({ success: true, data: { offering: { id, label: `${course.data?.course_code ?? ""} — ${course.data?.course_name ?? ""}`, academicYear: year.data?.year_name || year.data?.year_code, semester: semester.data?.semester_code || semester.data?.semester_name, policy: policy.data }, roster } });
  } catch (error) { next(error); }
});
registerCrudResource(router,{moduleCode:"RESULTS",entityType:"course_results",table:"course_results",permissionView:VIEW,permissionManage:MANAGE,searchFields:["grade_code","result_status","result_type","pass_status","remarks"],filterFields:["student_id","course_offering_id","course_registration_id","academic_year_id","semester_id","result_status","pass_status"],defaultOrderField:"created_at",fields:{studentId:"student_id",courseOfferingId:"course_offering_id",courseRegistrationId:"course_registration_id",academicYearId:"academic_year_id",semesterId:"semester_id",credits:"credits",courseworkMark:"coursework_mark",examinationMark:"examination_mark",supplementaryMark:"supplementary_mark",totalMark:"total_mark",gradeCode:"grade_code",gradePoint:"grade_point",passStatus:"pass_status",resultStatus:"result_status",attemptNumber:"attempt_number",resultType:"result_type",calculatedAt:"calculated_at",submittedAt:"submitted_at",submittedBy:"submitted_by",approvedAt:"approved_at",approvedBy:"approved_by",publishedAt:"published_at",publishedBy:"published_by",lockedAt:"locked_at",lockedBy:"locked_by",remarks:"remarks"}},"/course-results");
registerCrudResource(router,{moduleCode:"RESULTS",entityType:"course_result_corrections",table:"course_result_corrections",permissionView:VIEW,permissionManage:CORRECT,searchFields:["reason","status","review_comment"],filterFields:["course_result_id","requested_by","status"],defaultOrderField:"requested_at",fields:{courseResultId:"course_result_id",requestedBy:"requested_by",requestedAt:"requested_at",oldCourseworkMark:"old_coursework_mark",newCourseworkMark:"new_coursework_mark",oldExaminationMark:"old_examination_mark",newExaminationMark:"new_examination_mark",oldTotalMark:"old_total_mark",newTotalMark:"new_total_mark",oldGradeCode:"old_grade_code",newGradeCode:"new_grade_code",oldGradePoint:"old_grade_point",newGradePoint:"new_grade_point",reason:"reason",evidenceFileId:"evidence_file_id",status:"status",reviewedBy:"reviewed_by",reviewedAt:"reviewed_at",reviewComment:"review_comment"}},"/course-result-corrections");
registerCrudResource(router,{moduleCode:"RESULTS",entityType:"student_semester_results",table:"student_semester_results",permissionView:VIEW,permissionManage:APPROVE,searchFields:["academic_standing","result_status","remarks"],filterFields:["student_id","academic_year_id","semester_id","programme_version_id","academic_standing","result_status"],defaultOrderField:"created_at",fields:{studentId:"student_id",academicYearId:"academic_year_id",semesterId:"semester_id",programmeVersionId:"programme_version_id",totalRegisteredCredits:"total_registered_credits",totalAttemptedCredits:"total_attempted_credits",totalEarnedCredits:"total_earned_credits",totalQualityPoints:"total_quality_points",gpa:"gpa",coursesAttempted:"courses_attempted",coursesPassed:"courses_passed",coursesFailed:"courses_failed",academicStanding:"academic_standing",resultStatus:"result_status",calculatedAt:"calculated_at",submittedAt:"submitted_at",submittedBy:"submitted_by",approvedAt:"approved_at",approvedBy:"approved_by",publishedAt:"published_at",publishedBy:"published_by",lockedAt:"locked_at",lockedBy:"locked_by",remarks:"remarks"}},"/semester-results");
registerCrudResource(router,{moduleCode:"RESULTS",entityType:"student_academic_standings",table:"student_academic_standings",permissionView:VIEW,permissionManage:APPROVE,searchFields:["standing_code","standing_name","status","remarks"],filterFields:["student_id","academic_year_id","semester_id","standing_rule_id","standing_code","status"],defaultOrderField:"created_at",fields:{studentId:"student_id",academicYearId:"academic_year_id",semesterId:"semester_id",semesterResultId:"semester_result_id",gpa:"gpa",cgpa:"cgpa",standingRuleId:"standing_rule_id",standingCode:"standing_code",standingName:"standing_name",remarks:"remarks",status:"status",calculatedAt:"calculated_at",approvedBy:"approved_by",approvedAt:"approved_at"}},"/academic-standings");
registerCrudResource(router,{moduleCode:"RESULTS",entityType:"grade_scales",table:"grade_scales",permissionView:VIEW,permissionManage:MANAGE,searchFields:["scale_code","scale_name","description","status"],filterFields:["status","is_default"],defaultOrderField:"created_at",fields:{scaleCode:"scale_code",scaleName:"scale_name",description:"description",minimumTotal:"minimum_total",maximumTotal:"maximum_total",status:"status",isDefault:"is_default"}},"/grade-scales");
registerCrudResource(router,{moduleCode:"RESULTS",entityType:"grade_scale_details",table:"grade_scale_details",permissionView:VIEW,permissionManage:MANAGE,searchFields:["grade_code","grade_name","result_classification","status"],filterFields:["grade_scale_id","pass_status","status"],defaultOrderField:"minimum_mark",fields:{gradeScaleId:"grade_scale_id",gradeCode:"grade_code",gradeName:"grade_name",minimumMark:"minimum_mark",maximumMark:"maximum_mark",gradePoint:"grade_point",passStatus:"pass_status",resultClassification:"result_classification",status:"status"}},"/grade-scale-details");
registerCrudResource(router,{moduleCode:"RESULTS",entityType:"course_result_policies",table:"course_result_policies",permissionView:VIEW,permissionManage:MANAGE,searchFields:["status"],filterFields:["course_offering_id","grade_scale_id","status"],defaultOrderField:"created_at",fields:{courseOfferingId:"course_offering_id",gradeScaleId:"grade_scale_id",courseworkWeight:"coursework_weight",examinationWeight:"examination_weight",minimumCourseworkRequired:"minimum_coursework_required",minimumExamRequired:"minimum_exam_required",minimumPassMark:"minimum_pass_mark",status:"status",createdBy:"created_by",approvedBy:"approved_by",approvedAt:"approved_at"}},"/course-result-policies");
registerCrudResource(router,{moduleCode:"RESULTS",entityType:"student_gpa_records",table:"student_gpa_records",permissionView:VIEW,permissionManage:APPROVE,searchFields:["calculation_version"],filterFields:["student_id","academic_year_id","semester_id","semester_result_id"],defaultOrderField:"calculated_at",fields:{studentId:"student_id",academicYearId:"academic_year_id",semesterId:"semester_id",semesterResultId:"semester_result_id",gpa:"gpa",totalCredits:"total_credits",totalQualityPoints:"total_quality_points",calculationVersion:"calculation_version",calculatedAt:"calculated_at"}},"/gpa-records");
registerCrudResource(router,{moduleCode:"RESULTS",entityType:"student_cgpa_records",table:"student_cgpa_records",permissionView:VIEW,permissionManage:APPROVE,searchFields:["calculation_version"],filterFields:["student_id","academic_year_id","semester_id"],defaultOrderField:"calculated_at",fields:{studentId:"student_id",academicYearId:"academic_year_id",semesterId:"semester_id",cumulativeCredits:"cumulative_credits",cumulativeEarnedCredits:"cumulative_earned_credits",cumulativeQualityPoints:"cumulative_quality_points",cgpa:"cgpa",calculationVersion:"calculation_version",calculatedAt:"calculated_at"}},"/cgpa-records");
registerCrudResource(router,{moduleCode:"RESULTS",entityType:"student_course_attempts",table:"student_course_attempts",permissionView:VIEW,permissionManage:MANAGE,searchFields:["attempt_type","attempt_status","grade_code","remarks"],filterFields:["student_id","course_id","course_offering_id","course_registration_id","academic_year_id","semester_id","attempt_number","attempt_status"],defaultOrderField:"created_at",fields:{studentId:"student_id",courseId:"course_id",courseOfferingId:"course_offering_id",courseRegistrationId:"course_registration_id",courseResultId:"course_result_id",academicYearId:"academic_year_id",semesterId:"semester_id",attemptNumber:"attempt_number",attemptType:"attempt_type",attemptStatus:"attempt_status",totalMark:"total_mark",gradeCode:"grade_code",gradePoint:"grade_point",credits:"credits",startedAt:"started_at",completedAt:"completed_at",remarks:"remarks"}},"/course-attempts");
registerCrudResource(router,{moduleCode:"RESULTS",entityType:"student_academic_deficiencies",table:"student_academic_deficiencies",permissionView:VIEW,permissionManage:MANAGE,searchFields:["deficiency_type","deficiency_status","remarks"],filterFields:["student_id","course_id","course_offering_id","course_result_id","deficiency_type","deficiency_status"],defaultOrderField:"created_at",fields:{studentId:"student_id",courseId:"course_id",courseOfferingId:"course_offering_id",courseResultId:"course_result_id",deficiencyType:"deficiency_type",deficiencyStatus:"deficiency_status",firstRecordedAt:"first_recorded_at",resolvedAt:"resolved_at",resolutionCourseResultId:"resolution_course_result_id",remarks:"remarks"}},"/academic-deficiencies");
registerCrudResource(router,{moduleCode:"TRANSCRIPTS",entityType:"student_transcripts",table:"student_transcripts",permissionView:"transcripts.view",permissionManage:"transcripts.manage",searchFields:["transcript_number","transcript_type","transcript_status","verification_code"],filterFields:["student_id","programme_version_id","transcript_type","transcript_status"],defaultOrderField:"created_at",fields:{transcriptNumber:"transcript_number",studentId:"student_id",programmeVersionId:"programme_version_id",transcriptType:"transcript_type",issueReason:"issue_reason",cumulativeCredits:"cumulative_credits",cumulativeEarnedCredits:"cumulative_earned_credits",cumulativeQualityPoints:"cumulative_quality_points",cgpa:"cgpa",finalAcademicStanding:"final_academic_standing",transcriptStatus:"transcript_status",generatedAt:"generated_at",generatedBy:"generated_by",approvedAt:"approved_at",approvedBy:"approved_by",issuedAt:"issued_at",issuedBy:"issued_by",revokedAt:"revoked_at",revokedBy:"revoked_by",replacementOf:"replacement_of",documentFileId:"document_file_id",verificationCode:"verification_code",remarks:"remarks"}},"/transcripts");
registerCrudResource(router,{moduleCode:"TRANSCRIPTS",entityType:"student_transcript_semesters",table:"student_transcript_semesters",permissionView:"transcripts.view",permissionManage:"transcripts.manage",searchFields:["academic_standing"],filterFields:["transcript_id","academic_year_id","semester_id","semester_result_id"],defaultOrderField:"sequence_no",fields:{transcriptId:"transcript_id",academicYearId:"academic_year_id",semesterId:"semester_id",semesterResultId:"semester_result_id",gpa:"gpa",registeredCredits:"registered_credits",attemptedCredits:"attempted_credits",earnedCredits:"earned_credits",qualityPoints:"quality_points",academicStanding:"academic_standing",sequenceNo:"sequence_no"}},"/transcript-semesters");
registerCrudResource(router,{moduleCode:"TRANSCRIPTS",entityType:"student_transcript_courses",table:"student_transcript_courses",permissionView:"transcripts.view",permissionManage:"transcripts.manage",searchFields:["course_code","course_name","grade_code","result_type","pass_status"],filterFields:["transcript_id","transcript_semester_id","course_result_id","course_id"],defaultOrderField:"display_sequence",fields:{transcriptId:"transcript_id",transcriptSemesterId:"transcript_semester_id",courseResultId:"course_result_id",courseRegistrationId:"course_registration_id",courseId:"course_id",courseCode:"course_code",courseName:"course_name",credits:"credits",courseworkMark:"coursework_mark",examinationMark:"examination_mark",totalMark:"total_mark",gradeCode:"grade_code",gradePoint:"grade_point",resultType:"result_type",attemptNumber:"attempt_number",passStatus:"pass_status",displaySequence:"display_sequence"}},"/transcript-courses");
export default router;
