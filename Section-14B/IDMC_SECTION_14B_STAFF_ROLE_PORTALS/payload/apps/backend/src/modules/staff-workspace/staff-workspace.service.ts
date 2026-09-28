import type { Request } from "express";
import { institutionDb } from "../institution-management/shared/institution-db.js";

type Row = Record<string, any>;

function userId(req: Request): string {
  if (!req.user?.id) throw new Error("Authenticated staff identity is unavailable.");
  return String(req.user.id);
}

function clean(value: unknown, max = 2000): string | null {
  const text = String(value ?? "").trim();
  return text ? text.slice(0, max) : null;
}

async function rows(table: string, column?: string, value?: string, order = "created_at"): Promise<Row[]> {
  let query: any = institutionDb.from(table).select("*");
  if (column && value) query = query.eq(column, value);
  const result = await query.order(order, { ascending: false }).limit(500);
  if (result.error) throw new Error(`${table}: ${result.error.message}`);
  return result.data ?? [];
}

async function byIds(table: string, ids: unknown[]): Promise<Row[]> {
  const values = [...new Set(ids.filter(Boolean).map(String))];
  if (!values.length) return [];
  const result = await institutionDb.from(table).select("*").in("id", values).limit(500);
  if (result.error) throw new Error(`${table}: ${result.error.message}`);
  return result.data ?? [];
}

async function inColumn(table: string, column: string, ids: unknown[], order = "created_at"): Promise<Row[]> {
  const values = [...new Set(ids.filter(Boolean).map(String))];
  if (!values.length) return [];
  const result = await institutionDb.from(table).select("*").in(column, values).order(order, { ascending: false }).limit(500);
  if (result.error) throw new Error(`${table}: ${result.error.message}`);
  return result.data ?? [];
}

export async function getStaffIdentity(req: Request) {
  const id = userId(req);
  const [userResult, staffResult, roleResult, securityResult] = await Promise.all([
    institutionDb.from("users").select("*").eq("id", id).single(),
    institutionDb.from("staff").select("*").eq("user_id", id).maybeSingle(),
    institutionDb.from("user_roles").select("status,expires_at,roles!inner(id,role_code,role_name,status,role_permissions(permissions(permission_code,status)))").eq("user_id", id).eq("status", "ACTIVE"),
    institutionDb.from("security_logs").select("*").eq("user_id", id).order("created_at", { ascending: false }).limit(30),
  ]);
  if (userResult.error) throw new Error(`users: ${userResult.error.message}`);
  if (staffResult.error) throw new Error(`staff: ${staffResult.error.message}`);
  if (roleResult.error) throw new Error(`roles: ${roleResult.error.message}`);
  if (securityResult.error) throw new Error(`security_logs: ${securityResult.error.message}`);
  const roles = (roleResult.data ?? []).map((item: any) => item.roles).filter(Boolean);
  const permissions = [...new Set(roles.flatMap((role: any) => (role.role_permissions ?? []).map((entry: any) => entry.permissions).filter((permission: any) => permission?.status === "ACTIVE").map((permission: any) => permission.permission_code)))].sort();
  return { user: userResult.data, staff: staffResult.data, roles, permissions, security_logs: securityResult.data ?? [] };
}

export async function getLecturerWorkspace(req: Request) {
  const identity = await getStaffIdentity(req);
  const lecturerId = userId(req);
  const assignmentResult = await institutionDb.from("lecturer_assignments").select("*").eq("lecturer_user_id", lecturerId).in("assignment_status", ["ACTIVE", "COMPLETED"]).order("assigned_at", { ascending: false }).limit(500);
  if (assignmentResult.error) throw new Error(`lecturer_assignments: ${assignmentResult.error.message}`);
  const assignments = assignmentResult.data ?? [];
  const offeringIds = assignments.map(item => item.course_offering_id);
  const classIds = assignments.map(item => item.class_id);
  const [offerings, classes, assessments, sessions, registrations, timetable] = await Promise.all([
    byIds("course_offerings", offeringIds),
    byIds("classes", classIds),
    inColumn("assessments", "course_offering_id", offeringIds, "due_date"),
    inColumn("attendance_sessions", "course_offering_id", offeringIds, "session_date"),
    inColumn("course_registrations", "course_offering_id", offeringIds),
    inColumn("timetable_entries", "course_offering_id", offeringIds),
  ]);
  const [courses, academicYears, semesters, students, attendanceRecords, marks, results, slots, rooms] = await Promise.all([
    byIds("courses", offerings.map(item => item.course_id)),
    byIds("academic_years", offerings.map(item => item.academic_year_id)),
    byIds("semesters", offerings.map(item => item.semester_id)),
    byIds("students", registrations.map(item => item.student_id)),
    inColumn("attendance_records", "attendance_session_id", sessions.map(item => item.id), "marked_at"),
    inColumn("assessment_marks", "assessment_id", assessments.map(item => item.id)),
    inColumn("course_results", "course_offering_id", offeringIds),
    byIds("timetable_slots", timetable.map(item => item.timetable_slot_id)),
    byIds("rooms", timetable.map(item => item.room_id)),
  ]);
  return { ...identity, assignments, offerings, courses, academic_years: academicYears, semesters, classes, students, registrations, timetable_entries: timetable, timetable_slots: slots, rooms, attendance_sessions: sessions, attendance_records: attendanceRecords, assessments, assessment_marks: marks, course_results: results };
}

async function lecturerOwnsOffering(req: Request, offeringId: string) {
  const result = await institutionDb.from("lecturer_assignments").select("id").eq("lecturer_user_id", userId(req)).eq("course_offering_id", offeringId).eq("assignment_status", "ACTIVE").limit(1);
  if (result.error || !(result.data ?? []).length) throw new Error("This course offering is not actively assigned to the authenticated lecturer.");
}

export async function markLecturerAttendance(req: Request, input: Row) {
  const sessionId = clean(input.sessionId, 80); const studentId = clean(input.studentId, 80);
  const status = String(input.attendanceStatus ?? "").toUpperCase();
  if (!sessionId || !studentId || !["PRESENT", "ABSENT", "LATE", "EXCUSED"].includes(status)) throw new Error("Session, student and a valid attendance status are required.");
  const sessionResult = await institutionDb.from("attendance_sessions").select("*").eq("id", sessionId).single();
  if (sessionResult.error || !sessionResult.data) throw new Error("Attendance session was not found.");
  if (!["DRAFT", "OPEN"].includes(sessionResult.data.status)) throw new Error(`Attendance cannot be changed when the session is ${sessionResult.data.status}.`);
  await lecturerOwnsOffering(req, sessionResult.data.course_offering_id);
  const registration = await institutionDb.from("course_registrations").select("id").eq("course_offering_id", sessionResult.data.course_offering_id).eq("student_id", studentId).in("registration_status", ["REGISTERED", "ACTIVE"]).maybeSingle();
  if (registration.error || !registration.data) throw new Error("The student is not actively registered for this course offering.");
  const now = new Date().toISOString();
  const payload = { attendance_session_id: sessionId, student_id: studentId, course_registration_id: registration.data.id, attendance_status: status, minutes_late: status === "LATE" ? Math.max(0, Number(input.minutesLate ?? 0)) : 0, remarks: clean(input.remarks), marked_by: userId(req), marked_at: now, updated_at: now };
  const result = await institutionDb.from("attendance_records").upsert(payload, { onConflict: "attendance_session_id,student_id" }).select().single();
  if (result.error) throw new Error(`Unable to save attendance: ${result.error.message}`);
  return result.data;
}

export async function recordLecturerMark(req: Request, input: Row) {
  const assessmentId = clean(input.assessmentId, 80); const studentId = clean(input.studentId, 80); const mark = Number(input.marks);
  if (!assessmentId || !studentId || !Number.isFinite(mark) || mark < 0) throw new Error("Assessment, student and a non-negative mark are required.");
  const assessmentResult = await institutionDb.from("assessments").select("*").eq("id", assessmentId).single();
  if (assessmentResult.error || !assessmentResult.data) throw new Error("Assessment was not found.");
  const assessment = assessmentResult.data;
  if (!["DRAFT", "OPEN"].includes(assessment.status)) throw new Error(`Marks cannot be changed when the assessment is ${assessment.status}.`);
  if (mark > Number(assessment.maximum_marks)) throw new Error(`Mark cannot exceed ${assessment.maximum_marks}.`);
  await lecturerOwnsOffering(req, assessment.course_offering_id);
  const registration = await institutionDb.from("course_registrations").select("id").eq("course_offering_id", assessment.course_offering_id).eq("student_id", studentId).in("registration_status", ["REGISTERED", "ACTIVE"]).maybeSingle();
  if (registration.error || !registration.data) throw new Error("The student is not actively registered for this assessment course.");
  const existing = await institutionDb.from("assessment_marks").select("id,status").eq("assessment_id", assessmentId).eq("student_id", studentId).maybeSingle();
  if (existing.error) throw new Error(`Unable to verify existing mark: ${existing.error.message}`);
  if (existing.data && existing.data.status !== "DRAFT") throw new Error(`The existing mark is ${existing.data.status} and can no longer be edited.`);
  const now = new Date().toISOString();
  const result = await institutionDb.from("assessment_marks").upsert({ assessment_id: assessmentId, student_id: studentId, course_registration_id: registration.data.id, marks: mark, percentage: mark * 100 / Number(assessment.maximum_marks), remarks: clean(input.remarks), status: "DRAFT", entered_by: userId(req), entered_at: now, updated_at: now }, { onConflict: "assessment_id,student_id" }).select().single();
  if (result.error) throw new Error(`Unable to save assessment mark: ${result.error.message}`);
  return result.data;
}

export async function submitLecturerMark(req: Request, input: Row) {
  const markId = clean(input.markId, 80); if (!markId) throw new Error("Assessment mark is required.");
  const markResult = await institutionDb.from("assessment_marks").select("*").eq("id", markId).single();
  if (markResult.error || !markResult.data) throw new Error("Assessment mark was not found.");
  if (markResult.data.status !== "DRAFT") throw new Error(`Assessment mark cannot be submitted from ${markResult.data.status}.`);
  const assessmentResult = await institutionDb.from("assessments").select("course_offering_id").eq("id", markResult.data.assessment_id).single();
  if (assessmentResult.error || !assessmentResult.data) throw new Error("Assessment was not found.");
  await lecturerOwnsOffering(req, assessmentResult.data.course_offering_id);
  const result = await institutionDb.from("assessment_marks").update({ status: "SUBMITTED", submitted_by: userId(req), submitted_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", markId).select().single();
  if (result.error) throw new Error(`Unable to submit assessment mark: ${result.error.message}`);
  return result.data;
}

export async function submitLecturerResult(req: Request, input: Row) {
  const resultId = clean(input.resultId, 80); if (!resultId) throw new Error("Course result is required.");
  const existing = await institutionDb.from("course_results").select("*").eq("id", resultId).single();
  if (existing.error || !existing.data) throw new Error("Course result was not found.");
  if (existing.data.result_status !== "CALCULATED") throw new Error(`Course result cannot be submitted from ${existing.data.result_status}.`);
  await lecturerOwnsOffering(req, existing.data.course_offering_id);
  const result = await institutionDb.from("course_results").update({ result_status: "SUBMITTED", submitted_by: userId(req), submitted_at: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", resultId).select().single();
  if (result.error) throw new Error(`Unable to submit course result: ${result.error.message}`);
  return result.data;
}

export async function getFinanceWorkspace(req: Request) {
  const identity = await getStaffIdentity(req);
  const institutionId = identity.user?.institution_id;
  let studentQuery: any = institutionDb.from("students").select("*").order("created_at", { ascending: false }).limit(500);
  if (institutionId) studentQuery = studentQuery.eq("institution_id", institutionId);
  const studentResult = await studentQuery;
  if (studentResult.error) throw new Error(`students: ${studentResult.error.message}`);
  const students = studentResult.data ?? [];
  const ids = students.map((item: Row) => item.id);
  const [accounts, charges, invoices, payments, transactions, feeStructures] = await Promise.all([
    inColumn("student_financial_accounts", "student_id", ids, "updated_at"),
    inColumn("student_charges", "student_id", ids, "charge_date"),
    inColumn("invoices", "student_id", ids, "invoice_date"),
    inColumn("payments", "student_id", ids, "payment_date"),
    inColumn("financial_transactions", "student_id", ids, "transaction_date"),
    rows("fee_structures", undefined, undefined, "created_at"),
  ]);
  return { ...identity, students, accounts, charges, invoices, payments, financial_transactions: transactions, fee_structures: feeStructures };
}

export async function recordFinancePayment(req: Request, input: Row) {
  const studentId = clean(input.studentId, 80); const invoiceId = clean(input.invoiceId, 80);
  const amount = Number(input.amount); const method = String(input.paymentMethod ?? "").toUpperCase();
  const allowed = ["CASH", "BANK", "MOBILE_MONEY", "CARD", "CONTROL_NUMBER", "ONLINE", "OTHER"];
  if (!studentId || !Number.isFinite(amount) || amount <= 0 || !allowed.includes(method)) throw new Error("Student, positive amount and valid payment method are required.");
  const result = await institutionDb.rpc("idmc_record_staff_payment", { p_student_id: studentId, p_invoice_id: invoiceId, p_amount: amount, p_payment_method: method, p_reference: clean(input.reference, 150), p_payer_name: clean(input.payerName, 200), p_actor: userId(req) });
  if (result.error) throw new Error(`Unable to record payment: ${result.error.message}`);
  return result.data;
}

export async function getRegistryWorkspace(req: Request) {
  const identity = await getStaffIdentity(req);
  const institutionId = identity.user?.institution_id;
  let studentQuery: any = institutionDb.from("students").select("*").order("created_at", { ascending: false }).limit(500);
  if (institutionId) studentQuery = studentQuery.eq("institution_id", institutionId);
  const studentResult = await studentQuery;
  if (studentResult.error) throw new Error(`students: ${studentResult.error.message}`);
  const students = studentResult.data ?? [];
  const ids = students.map((item: Row) => item.id);
  const [registrations, courseRegistrations, results, semesterResults, requests, addDrop, programmes, years, semesters] = await Promise.all([
    inColumn("student_registrations", "student_id", ids),
    inColumn("course_registrations", "student_id", ids),
    inColumn("course_results", "student_id", ids),
    inColumn("student_semester_results", "student_id", ids),
    inColumn("student_service_requests", "student_id", ids, "submitted_at"),
    rows("course_add_drop_requests"),
    rows("programmes"), rows("academic_years", undefined, undefined, "start_date"), rows("semesters", undefined, undefined, "start_date"),
  ]);
  return { ...identity, students, registrations, course_registrations: courseRegistrations, course_results: results, semester_results: semesterResults, service_requests: requests, add_drop_requests: addDrop, programmes, academic_years: years, semesters };
}

export async function decideStudentRequest(req: Request, input: Row) {
  const requestId = clean(input.requestId, 80); const decision = String(input.decision ?? "").toUpperCase();
  if (!requestId || !["APPROVED", "REJECTED", "COMPLETED"].includes(decision)) throw new Error("Request and valid decision are required.");
  const existing = await institutionDb.from("student_service_requests").select("*").eq("id", requestId).single();
  if (existing.error || !existing.data) throw new Error("Student request was not found.");
  if (!["SUBMITTED", "UNDER_REVIEW", "APPROVED"].includes(existing.data.status)) throw new Error(`Request cannot be changed from ${existing.data.status}.`);
  const result = await institutionDb.from("student_service_requests").update({ status: decision, reviewed_by: userId(req), reviewed_at: new Date().toISOString(), review_comment: clean(input.comment), updated_at: new Date().toISOString() }).eq("id", requestId).select().single();
  if (result.error) throw new Error(`Unable to decide request: ${result.error.message}`);
  return result.data;
}
