import { Router, type Request, type Response } from "express";
import { institutionDb } from "../../institution-management/shared/institution-db.js";
import { requirePermission } from "../../../middleware/rbac.js";
import {
  changeOwnPassword,
  getStudentPortal,
  respondToCoursework,
  submitCourseEvaluation,
  submitHelpdeskTicket,
  submitServiceRequest,
  updateOwnPhoto,
  updateOwnProfile,
} from "./student-self-service.service.js";
import { getMyStudentRecord } from "./students.service.js";

type Row = Record<string, any>;
const router = Router();

function handle(action: (req: Request) => Promise<unknown>) {
  return async (req: Request, res: Response) => {
    try {
      res.json({ success: true, data: await action(req) });
    } catch (error) {
      res.status(400).json({
        success: false,
        message: error instanceof Error ? error.message : "Student self-service request failed.",
      });
    }
  };
}

function latest(records: Row[]): Row | null {
  return records[0] ?? null;
}

async function portal(req: Request): Promise<Row> {
  return await getStudentPortal(req) as Row;
}

router.get("/portal", requirePermission("students.self.view"), handle(portal));

router.get("/summary", requirePermission("students.self.view"), handle(async req => {
  const data = await portal(req);
  const student = data.student ?? {};
  const attendance = data.attendance_records ?? [];
  const attended = attendance.filter((item: Row) => ["PRESENT", "LATE"].includes(String(item.attendance_status).toUpperCase())).length;
  const semester = latest(data.semester_results ?? []);
  const cgpa = latest(data.cgpa_records ?? []);
  const registration = latest(data.registrations ?? []);
  const account = data.financial_account ?? {};
  const deficiencies = data.academic_deficiencies ?? [];
  const failed = (data.course_results ?? []).filter((item: Row) => String(item.pass_status).toUpperCase() === "FAIL");
  const unread = (data.notifications ?? []).filter((item: Row) => !item.read_at && String(item.status ?? "").toUpperCase() !== "READ");
  const pendingRequests = (data.service_requests ?? []).filter((item: Row) => !["APPROVED", "REJECTED", "CLOSED", "CANCELLED"].includes(String(item.status).toUpperCase()));
  const balance = Number(account.balance ?? account.outstanding_balance ?? account.current_balance ?? account.account_balance ?? 0);
  const userResult = student.user_id
    ? await institutionDb.from("users").select("last_login_at").eq("id", student.user_id).maybeSingle()
    : { data: null, error: null };
  if (userResult.error) throw new Error(`Unable to load student login history: ${userResult.error.message}`);
  const currentYearName = registration?.academic_year_name ?? null;
  const currentYearStart = Number(String(currentYearName ?? "").match(/\d{4}/)?.[0] ?? new Date().getFullYear());
  const entryYear = Number(student.admission_year ?? String(student.admission_date ?? student.enrollment_date ?? "").slice(0, 4));
  const rawYearOfStudy = Number.isFinite(entryYear) && entryYear > 0 ? Math.max(1, currentYearStart - entryYear + 1) : null;
  const programmeDuration = Number(student.duration_years ?? 0);
  const yearOfStudy = rawYearOfStudy && programmeDuration > 0 ? Math.min(rawYearOfStudy, programmeDuration) : rawYearOfStudy;
  const ordinal = (value: number | null) => {
    if (!value) return null;
    const suffix = value % 100 >= 11 && value % 100 <= 13 ? "th" : ({ 1: "st", 2: "nd", 3: "rd" } as Record<number, string>)[value % 10] ?? "th";
    return `${value}${suffix} Year`;
  };
  const admissionDate = student.admission_date ?? student.enrollment_date ?? null;
  const intake = admissionDate
    ? new Date(`${String(admissionDate).slice(0, 10)}T00:00:00Z`).toLocaleString("en-GB", { month: "long", timeZone: "UTC" })
    : null;
  const classRecord = (data.student_classes ?? [])[0] ?? null;
  const alerts: Row[] = [];
  if (!registration) alerts.push({ severity: "warning", title: "No semester registration", message: "Contact the Academic Office to create the current registration." });
  else if (!["REGISTERED", "LOCKED", "APPROVED"].includes(String(registration.registration_status).toUpperCase())) alerts.push({ severity: "warning", title: "Registration requires attention", message: `Current status: ${registration.registration_status}.` });
  if (balance > 0) alerts.push({ severity: "warning", title: "Outstanding balance", message: `Your account has an outstanding balance of ${balance}.` });
  if (deficiencies.length || failed.length) alerts.push({ severity: "danger", title: "Academic action required", message: `${deficiencies.length || failed.length} course item(s) require attention.` });
  if (unread.length) alerts.push({ severity: "info", title: "Unread notifications", message: `${unread.length} notification(s) have not been read.` });

  return {
    student,
    panel: {
      current_year: currentYearName,
      last_login_at: userResult.data?.last_login_at ?? null,
      year_of_study: ordinal(yearOfStudy),
      year_of_study_number: yearOfStudy,
      stream: classRecord?.class_name ?? classRecord?.class_code ?? null,
      student_status: student.student_status ?? student.status ?? null,
      entry_year: Number.isFinite(entryYear) && entryYear > 0 ? `${entryYear}/${entryYear + 1}` : null,
      intake: intake,
      session: student.mode_of_study ?? null,
      programme: student.programme_name ?? null,
      programme_code: student.programme_code ?? null,
      department: student.department_name ?? null,
      school: student.school_name ?? null,
      campus: student.campus_name ?? null,
    },
    current_registration: registration,
    latest_result: { gpa: semester?.gpa ?? null, cgpa: cgpa?.cgpa ?? semester?.cgpa ?? null, academic_standing: semester?.academic_standing ?? cgpa?.academic_standing ?? null },
    attendance: { total: attendance.length, attended, percentage: attendance.length ? Number(((attended / attendance.length) * 100).toFixed(1)) : null },
    finance: { balance, account_status: account.account_status ?? null, currency: account.currency_code ?? "TZS" },
    counts: {
      registered_courses: (data.course_registrations ?? []).filter((item: Row) => !["DROPPED", "REJECTED", "CANCELLED"].includes(String(item.registration_status).toUpperCase())).length,
      published_results: (data.course_results ?? []).filter((item: Row) => ["PUBLISHED", "LOCKED"].includes(String(item.result_status).toUpperCase())).length,
      documents: (data.student_documents ?? []).length,
      unread_notifications: unread.length,
      pending_requests: pendingRequests.length,
      deficiencies: deficiencies.length,
      failed_courses: failed.length,
    },
    academic_risk: deficiencies.length || failed.length ? "AT_RISK" : (semester?.academic_standing ?? "GOOD"),
    alerts,
    upcoming_classes: (data.timetable_entries ?? []).slice(0, 5),
    upcoming_examinations: (data.examination_timetable ?? []).filter((item: Row) => !item.examination_date || new Date(item.examination_date).getTime() >= Date.now() - 86400000).slice(0, 5),
    announcements: (data.announcements ?? []).slice(0, 5),
    audit_warnings: data.audit_warnings ?? [],
  };
}));

router.get("/registration", requirePermission("students.self.view"), handle(async req => {
  const data = await portal(req);
  return {
    student: data.student,
    registrations: data.registrations ?? [],
    current_registration: latest(data.registrations ?? []),
    course_registrations: data.course_registrations ?? [],
    course_offerings: data.course_offerings ?? [],
    courses: data.courses ?? [],
    audit_warnings: data.audit_warnings ?? [],
  };
}));

router.get("/results", requirePermission("students.self.view"), handle(async req => {
  const data = await portal(req);
  return {
    course_results: (data.course_results ?? []).filter((item: Row) => ["PUBLISHED", "LOCKED"].includes(String(item.result_status).toUpperCase())),
    semester_results: (data.semester_results ?? []).filter((item: Row) => ["PUBLISHED", "LOCKED", "APPROVED"].includes(String(item.result_status ?? item.status).toUpperCase())),
    cgpa_records: data.cgpa_records ?? [],
    deficiencies: data.academic_deficiencies ?? [],
  };
}));

router.get("/attendance", requirePermission("students.self.view"), handle(async req => {
  const data = await portal(req);
  return { records: data.attendance_records ?? [] };
}));

router.get("/timetable", requirePermission("students.self.view"), handle(async req => {
  const data = await portal(req);
  return { classes: data.timetable_entries ?? [], examinations: data.examination_timetable ?? [] };
}));

router.get("/finance", requirePermission("students.self.view"), handle(async req => {
  const data = await portal(req);
  const student = await getMyStudentRecord(req) as Row;
  const paymentRequests = await institutionDb.from("student_payment_requests").select("*").eq("student_id", student.id).order("requested_at", { ascending: false });
  if (paymentRequests.error) throw new Error(`Unable to load payment requests: ${paymentRequests.error.message}`);
  return { account: data.financial_account, invoices: data.invoices ?? [], payments: data.payments ?? [], transactions: data.financial_transactions ?? [], scholarships: data.scholarships ?? [], payment_requests: paymentRequests.data ?? [] };
}));

router.get("/documents", requirePermission("students.self.view"), handle(async req => {
  const data = await portal(req);
  return { documents: data.student_documents ?? [], service_requests: data.service_requests ?? [] };
}));

router.get("/documents/:id/download", requirePermission("students.self.view"), handle(async req => {
  const student = await getMyStudentRecord(req) as Row;
  const result = await institutionDb.from("student_documents").select("*").eq("id", req.params.id).eq("student_id", student.id).maybeSingle();
  if (result.error || !result.data) throw new Error("Document was not found for the authenticated student.");
  const path = result.data.file_url || result.data.file_path;
  if (!path) throw new Error("Document storage path is unavailable.");
  if (/^https?:\/\//i.test(path)) return { url: path, file_name: result.data.file_name };
  const signed = await institutionDb.storage.from("idmc-private-documents").createSignedUrl(path, 300);
  if (signed.error) throw new Error(`Unable to prepare document download: ${signed.error.message}`);
  return { url: signed.data.signedUrl, expires_in: 300, file_name: result.data.file_name };
}));

router.get("/notifications", requirePermission("students.self.view"), handle(async req => {
  const data = await portal(req);
  return { notifications: data.notifications ?? [], announcements: data.announcements ?? [] };
}));

router.patch("/notifications/:id/read", requirePermission("students.self.manage"), handle(async req => {
  const student = await getMyStudentRecord(req) as Row;
  const now = new Date().toISOString();
  const result = await institutionDb.from("notifications").update({ status: "READ", read_at: now }).eq("id", req.params.id).eq("recipient_student_id", student.id).select().maybeSingle();
  if (result.error || !result.data) throw new Error("Notification was not found for the authenticated student.");
  return result.data;
}));

router.post("/notifications/read-all", requirePermission("students.self.manage"), handle(async req => {
  const student = await getMyStudentRecord(req) as Row;
  const result = await institutionDb.from("notifications").update({ status: "READ", read_at: new Date().toISOString() }).eq("recipient_student_id", student.id).is("read_at", null).select("id");
  if (result.error) throw new Error(`Unable to update notifications: ${result.error.message}`);
  return { updated: result.data?.length ?? 0 };
}));

router.get("/transcript", requirePermission("students.self.view"), handle(async req => {
  const student = await getMyStudentRecord(req) as Row;
  const transcripts = await institutionDb.from("student_transcripts").select("*").eq("student_id", student.id).order("created_at", { ascending: false });
  if (transcripts.error) throw new Error(`Unable to load transcript: ${transcripts.error.message}`);
  const transcript = transcripts.data?.[0] ?? null;
  if (!transcript) return { student, transcript: null, semesters: [], courses: [] };
  const [semesters, courses] = await Promise.all([
    institutionDb.from("student_transcript_semesters").select("*").eq("transcript_id", transcript.id).order("sequence_no"),
    institutionDb.from("student_transcript_courses").select("*").eq("transcript_id", transcript.id).order("display_sequence"),
  ]);
  if (semesters.error) throw new Error(`Unable to load transcript semesters: ${semesters.error.message}`);
  if (courses.error) throw new Error(`Unable to load transcript courses: ${courses.error.message}`);
  return { student, transcript, semesters: semesters.data ?? [], courses: courses.data ?? [], history: transcripts.data ?? [] };
}));

router.patch("/profile", requirePermission("students.self.manage"), handle(req => updateOwnProfile(req, req.body ?? {})));
router.patch("/profile-photo", requirePermission("students.self.manage"), handle(req => updateOwnPhoto(req, req.body ?? {})));
router.post("/coursework-responses", requirePermission("students.self.manage"), handle(req => respondToCoursework(req, req.body ?? {})));
router.post("/course-evaluations", requirePermission("students.self.manage"), handle(req => submitCourseEvaluation(req, req.body ?? {})));
router.post("/requests", requirePermission("students.self.manage"), handle(req => submitServiceRequest(req, req.body ?? {})));
router.post("/helpdesk", requirePermission("students.self.manage"), handle(req => submitHelpdeskTicket(req, req.body ?? {})));
router.post("/change-password", requirePermission("students.self.manage"), handle(req => changeOwnPassword(req, req.body ?? {})));

export default router;
