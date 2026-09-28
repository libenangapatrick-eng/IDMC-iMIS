import { Router } from "express";
import { authenticate } from "../../middleware/auth.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";
import { getSupabase } from "../../config/database.js";
import { requirePermission } from "../../middleware/rbac.js";

const router = Router();

router.use(authenticate);

const VIEW = "registration.view";
const MANAGE = "registration.manage";

router.get("/workspace/references", requirePermission(VIEW), async (_req, res, next) => {
  try {
    const db = getSupabase();
    const [students, years, semesters, programmes, versions, registrations] = await Promise.all([
      db.from("students").select("id,student_number,first_name,middle_name,last_name,programme_id,student_status").order("student_number").limit(2000),
      db.from("academic_years").select("id,year_code,year_name,status,start_date,end_date").order("start_date", { ascending: false }),
      db.from("semesters").select("id,academic_year_id,semester_code,semester_name,semester_number,status").order("semester_number"),
      db.from("programmes").select("id,programme_code,programme_name,department_id,status").order("programme_code"),
      db.from("programme_versions").select("id,programme_id,version_code,version_name,status,effective_from").order("effective_from", { ascending: false }),
      db.from("student_registrations").select("*").order("created_at", { ascending: false }).limit(2000),
    ]);
    for (const result of [students, years, semesters, programmes, versions, registrations]) if (result.error) throw result.error;
    res.json({ success: true, data: { students: students.data ?? [], academicYears: years.data ?? [], semesters: semesters.data ?? [], programmes: programmes.data ?? [], programmeVersions: versions.data ?? [], registrations: registrations.data ?? [] } });
  } catch (error) { next(error); }
});

router.post("/workspace/create", requirePermission(MANAGE), async (req, res, next) => {
  try {
    const studentId = String(req.body?.studentId ?? "").trim();
    const academicYearId = String(req.body?.academicYearId ?? "").trim();
    const semesterId = String(req.body?.semesterId ?? "").trim();
    if (!studentId || !academicYearId || !semesterId) return res.status(400).json({ success: false, message: "Student, academic year and semester are required." });
    const db = getSupabase();
    const [student, year, semester, existing] = await Promise.all([
      db.from("students").select("id,student_number,programme_id,student_status").eq("id", studentId).maybeSingle(),
      db.from("academic_years").select("id,year_code,year_name,status").eq("id", academicYearId).maybeSingle(),
      db.from("semesters").select("id,academic_year_id,semester_code,semester_name,status").eq("id", semesterId).maybeSingle(),
      db.from("student_registrations").select("*").eq("student_id", studentId).eq("academic_year_id", academicYearId).eq("semester_id", semesterId).maybeSingle(),
    ]);
    for (const result of [student, year, semester, existing]) if (result.error) throw result.error;
    if (existing.data) return res.status(200).json({ success: true, created: false, message: "Registration already exists for the selected period.", data: existing.data });
    if (!student.data || !year.data || !semester.data) return res.status(404).json({ success: false, message: "Student or academic period was not found." });
    if (student.data.student_status !== "ACTIVE") return res.status(409).json({ success: false, message: `Student status is ${student.data.student_status}; only ACTIVE students can be registered.` });
    if (!student.data.programme_id) return res.status(409).json({ success: false, message: "The student has no programme. Update Student Master first." });
    if (semester.data.academic_year_id && semester.data.academic_year_id !== academicYearId) return res.status(409).json({ success: false, message: "The selected semester does not belong to the selected academic year." });
    const version = await db.from("programme_versions").select("id").eq("programme_id", student.data.programme_id).eq("status", "ACTIVE").order("effective_from", { ascending: false }).limit(1).maybeSingle();
    if (version.error) throw version.error;
    const cleanPeriod = String(year.data.year_code || year.data.year_name || "YEAR").replace(/[^A-Za-z0-9]/g, "");
    const cleanSemester = String(semester.data.semester_code || semester.data.semester_name || "SEM").replace(/[^A-Za-z0-9]/g, "");
    const registrationNumber = `${student.data.student_number}-${cleanPeriod}-${cleanSemester}`.slice(0, 80);
    const now = new Date().toISOString();
    const saved = await db.from("student_registrations").insert({ student_id: studentId, academic_year_id: academicYearId, semester_id: semesterId, programme_id: student.data.programme_id, programme_version_id: version.data?.id ?? null, registration_number: registrationNumber, registration_status: "DRAFT", academic_eligibility_status: "PENDING", finance_eligibility_status: "PENDING", document_eligibility_status: "PENDING", total_registered_credits: 0, minimum_credits: 0, maximum_credits: 60, notes: req.body?.notes ? String(req.body.notes).trim() : null, created_by: req.user?.id ?? null, updated_by: req.user?.id ?? null, created_at: now, updated_at: now }).select("*").single();
    if (saved.error) throw saved.error;
    res.status(201).json({ success: true, created: true, message: "Draft registration created. Programme and version were linked automatically.", data: saved.data });
  } catch (error) { next(error); }
});

registerCrudResource(
  router,
  {
    moduleCode: "REGISTRATION",
    entityType: "student_registrations",
    table: "student_registrations",
    permissionView: VIEW,
    permissionManage: MANAGE,

    searchFields: [
      "registration_number",
      "registration_status",
      "academic_eligibility_status",
      "finance_eligibility_status",
      "document_eligibility_status"
    ],

    filterFields: [
      "student_id",
      "academic_year_id",
      "semester_id",
      "programme_id",
      "programme_version_id",
      "registration_status",
      "academic_eligibility_status",
      "finance_eligibility_status",
      "document_eligibility_status"
    ],

    defaultOrderField: "created_at",

    fields: {
      studentId: "student_id",
      academicYearId: "academic_year_id",
      semesterId: "semester_id",
      programmeId: "programme_id",
      programmeVersionId: "programme_version_id",
      registrationNumber: "registration_number",
      registrationStatus: "registration_status",
      academicEligibilityStatus: "academic_eligibility_status",
      financeEligibilityStatus: "finance_eligibility_status",
      documentEligibilityStatus: "document_eligibility_status",
      totalRegisteredCredits: "total_registered_credits",
      minimumCredits: "minimum_credits",
      maximumCredits: "maximum_credits",
      submittedAt: "submitted_at",
      approvedAt: "approved_at",
      approvedBy: "approved_by",
      lockedAt: "locked_at",
      lockedBy: "locked_by",
      rejectionReason: "rejection_reason",
      notes: "notes",
      createdBy: "created_by",
      updatedBy: "updated_by"
    }
  },
  "/"
);

registerCrudResource(
  router,
  {
    moduleCode: "REGISTRATION",
    entityType: "course_registrations",
    table: "course_registrations",
    permissionView: VIEW,
    permissionManage: MANAGE,

    searchFields: [
      "registration_status"
    ],

    filterFields: [
      "student_registration_id",
      "student_id",
      "course_offering_id",
      "registration_status"
    ],

    defaultOrderField: "created_at",

    fields: {
      studentRegistrationId: "student_registration_id",
      studentId: "student_id",
      courseOfferingId: "course_offering_id",
      registrationStatus: "registration_status",
      createdBy: "created_by",
      updatedBy: "updated_by"
    }
  },
  "/courses"
);

registerCrudResource(
  router,
  {
    moduleCode: "REGISTRATION",
    entityType: "course_add_drop_requests",
    table: "course_add_drop_requests",
    permissionView: VIEW,
    permissionManage: MANAGE,

    searchFields: [
      "request_type",
      "request_status",
      "reason",
      "decision_reason"
    ],

    filterFields: [
      "student_registration_id",
      "course_registration_id",
      "request_type",
      "request_status"
    ],

    defaultOrderField: "created_at",

    fields: {
      studentRegistrationId: "student_registration_id",
      courseRegistrationId: "course_registration_id",
      requestType: "request_type",
      requestStatus: "request_status",
      reason: "reason",
      decisionReason: "decision_reason",
      requestedBy: "requested_by",
      reviewedBy: "reviewed_by",
      reviewedAt: "reviewed_at"
    }
  },
  "/add-drop"
);

registerCrudResource(
  router,
  {
    moduleCode: "REGISTRATION",
    entityType: "registration_approvals",
    table: "registration_approvals",
    permissionView: VIEW,
    permissionManage: MANAGE,

    searchFields: [
      "approval_type",
      "approval_status",
      "remarks"
    ],

    filterFields: [
      "student_registration_id",
      "approval_type",
      "approval_status"
    ],

    defaultOrderField: "created_at",

    fields: {
      studentRegistrationId: "student_registration_id",
      approvalType: "approval_type",
      approvalStatus: "approval_status",
      approvedBy: "approved_by",
      approvedAt: "approved_at",
      remarks: "remarks"
    }
  },
  "/approvals"
);

export default router;
