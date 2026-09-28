import { Router } from "express";
import { getSupabase } from "../../config/database.js";
import { authenticate } from "../../middleware/auth.js";
import { requirePermission } from "../../middleware/rbac.js";
import { createAuditLog } from "../../services/audit.service.js";

const router = Router();
router.use(authenticate);

async function requestScope(userId: string) {
  const db = getSupabase();
  const [roleResult, staffResult, scopeResult] = await Promise.all([
    db.from("user_roles").select("status,expires_at,roles!inner(role_code,status)").eq("user_id", userId).eq("status", "ACTIVE"),
    db.from("staff").select("department_id,employment_status").eq("user_id", userId).maybeSingle(),
    db.from("user_scopes").select("department_id").eq("user_id", userId).eq("scope_type", "DEPARTMENT").limit(1).maybeSingle(),
  ]);
  if (roleResult.error) throw roleResult.error;
  if (staffResult.error) throw staffResult.error;
  if (scopeResult.error) throw scopeResult.error;

  const now = Date.now();
  const roleCodes = (roleResult.data ?? []).filter((item: any) =>
    item.roles?.status === "ACTIVE" && (!item.expires_at || new Date(item.expires_at).getTime() > now)
  ).map((item: any) => item.roles.role_code);
  const global = roleCodes.some((code: string) => ["SUPER_ADMIN", "ADMIN", "ACADEMIC_OFFICER", "REGISTRAR"].includes(code));
  const staff = staffResult.data as any;
  const departmentId = (scopeResult.data as any)?.department_id
    ?? (staff?.employment_status === "ACTIVE" ? (staff.department_id ?? null) : null);

  if (!global && !departmentId) {
    const error = new Error("HOD/Deputy HOD account must be linked to an active staff record with a department.") as Error & { statusCode?: number };
    error.statusCode = 403;
    throw error;
  }
  return { global, departmentId, roleCodes };
}

type AnyRow = Record<string, any>;

async function resultRowsForScope(userId: string, status?: string) {
  const db = getSupabase();
  const scope = await requestScope(userId);
  let query = db.from("course_results").select("*").order("updated_at", { ascending: false }).limit(2000);
  if (status) query = query.eq("result_status", status);
  const resultSet = await query;
  if (resultSet.error) throw resultSet.error;
  const results = (resultSet.data ?? []) as AnyRow[];
  const offeringIds = [...new Set(results.map(row => row.course_offering_id).filter(Boolean))];
  if (!offeringIds.length) return { scope, rows: [] as AnyRow[] };

  const offeringsResult = await db.from("course_offerings").select("id,offering_code,course_id,academic_year_id,semester_id,programme_id").in("id", offeringIds);
  if (offeringsResult.error) throw offeringsResult.error;
  const offerings = (offeringsResult.data ?? []) as AnyRow[];
  const courseIds = [...new Set(offerings.map(row => row.course_id).filter(Boolean))];
  const studentIds = [...new Set(results.map(row => row.student_id).filter(Boolean))];
  const yearIds = [...new Set(results.map(row => row.academic_year_id).filter(Boolean))];
  const semesterIds = [...new Set(results.map(row => row.semester_id).filter(Boolean))];
  const [courseSet, studentSet, yearSet, semesterSet] = await Promise.all([
    courseIds.length ? db.from("courses").select("id,course_code,course_name,department_id").in("id", courseIds) : Promise.resolve({ data: [], error: null }),
    studentIds.length ? db.from("students").select("id,student_number,first_name,middle_name,last_name,programme_id").in("id", studentIds) : Promise.resolve({ data: [], error: null }),
    yearIds.length ? db.from("academic_years").select("id,year_code,year_name").in("id", yearIds) : Promise.resolve({ data: [], error: null }),
    semesterIds.length ? db.from("semesters").select("id,semester_code,semester_name,semester_number").in("id", semesterIds) : Promise.resolve({ data: [], error: null }),
  ]);
  for (const item of [courseSet, studentSet, yearSet, semesterSet]) if (item.error) throw item.error;
  const makeMap = (items: AnyRow[]) => new Map(items.map(item => [String(item.id), item]));
  const offeringMap = makeMap(offerings), courseMap = makeMap((courseSet.data ?? []) as AnyRow[]), studentMap = makeMap((studentSet.data ?? []) as AnyRow[]);
  const yearMap = makeMap((yearSet.data ?? []) as AnyRow[]), semesterMap = makeMap((semesterSet.data ?? []) as AnyRow[]);
  const rows: AnyRow[] = results.map(result => {
    const offering = offeringMap.get(String(result.course_offering_id)) ?? {};
    const course = courseMap.get(String(offering.course_id)) ?? {};
    const student = studentMap.get(String(result.student_id)) ?? {};
    const year = yearMap.get(String(result.academic_year_id)) ?? {};
    const semester = semesterMap.get(String(result.semester_id)) ?? {};
    return { ...result, department_id: course.department_id ?? null, offering_code: offering.offering_code ?? null,
      course_code: course.course_code ?? null, course_name: course.course_name ?? null,
      student_number: student.student_number ?? null,
      student_name: [student.first_name, student.middle_name, student.last_name].filter(Boolean).join(" "),
      academic_year: year.year_name || year.year_code || null,
      semester_name: semester.semester_name || semester.semester_code || null,
      semester_number: semester.semester_number ?? null };
  }).filter(row => scope.global || row.department_id === scope.departmentId);
  return { scope, rows };
}

router.get("/results", requirePermission("student_requests.view_department"), async (req, res, next) => {
  try {
    const status = typeof req.query.status === "string" ? req.query.status.trim().toUpperCase() : "";
    const allowed = ["", "CALCULATED", "SUBMITTED", "UNDER_REVIEW", "APPROVED", "PUBLISHED", "LOCKED", "WITHHELD"];
    if (!allowed.includes(status)) return res.status(400).json({ success: false, message: "Unsupported result status filter." });
    const response = await resultRowsForScope(req.user!.id, status || undefined);
    res.json({ success: true, data: response.rows, meta: { total: response.rows.length, departmentId: response.scope.departmentId } });
  } catch (error) { next(error); }
});

const resultTransitions = {
  review: { from: ["CALCULATED", "SUBMITTED"], to: "UNDER_REVIEW", audit: "HOD_RESULT_CONFIRM_REVIEW" },
  approve: { from: ["UNDER_REVIEW"], to: "APPROVED", audit: "HOD_RESULT_APPROVE" },
  publish: { from: ["APPROVED"], to: "PUBLISHED", audit: "HOD_RESULT_PUBLISH" },
} as const;

async function applyResultAction(req: any, res: any, next: any, action: keyof typeof resultTransitions, studentOnly: boolean) {
  try {
    const transition = resultTransitions[action];
    const scoped = await resultRowsForScope(req.user.id);
    const studentId = String(req.params.studentId || "").trim();
    const academicYearId = String(req.body?.academicYearId || "").trim();
    const semesterId = String(req.body?.semesterId || "").trim();
    let matching = scoped.rows.filter(row => (transition.from as readonly string[]).includes(String(row.result_status)));
    if (studentOnly) {
      if (!studentId || !academicYearId || !semesterId) return res.status(400).json({ success: false, message: "Student, academic year and semester are required." });
      matching = matching.filter(row => String(row.student_id) === studentId && String(row.academic_year_id) === academicYearId && String(row.semester_id) === semesterId);
    }
    if (!matching.length) return res.status(409).json({ success: false, message: `No ${transition.from.join("/")} results are ready for this action in your department.` });
    const db = getSupabase(), now = new Date().toISOString();
    const patch: AnyRow = { result_status: transition.to, updated_at: now };
    if (action === "review") Object.assign(patch, { reviewed_by: req.user.id, reviewed_at: now });
    if (action === "approve") Object.assign(patch, { approved_by: req.user.id, approved_at: now });
    if (action === "publish") Object.assign(patch, { published_by: req.user.id, published_at: now });
    const ids = matching.map(row => row.id);
    // Database integrity requires CALCULATED -> SUBMITTED -> UNDER_REVIEW.
    // HOD confirmation performs both audited transitions when a lecturer has
    // calculated marks but has not pressed the legacy Submit button.
    if (action === "review") {
      const calculatedIds = matching.filter(row => row.result_status === "CALCULATED").map(row => row.id);
      if (calculatedIds.length) {
        const submitted = await db.from("course_results").update({ result_status: "SUBMITTED", submitted_by: req.user.id, submitted_at: now, updated_at: now }).in("id", calculatedIds).eq("result_status", "CALCULATED");
        if (submitted.error) throw submitted.error;
      }
    }
    const updateQuery = db.from("course_results").update(patch).in("id", ids);
    const updated = action === "review"
      ? await updateQuery.eq("result_status", "SUBMITTED").select("*")
      : await updateQuery.in("result_status", [...transition.from]).select("*");
    if (updated.error) throw updated.error;
    await createAuditLog({ actorUserId: req.user.id, actionCode: transition.audit, moduleCode: "RESULTS", entityType: "course_results", entityId: studentOnly ? studentId : null, oldValues: { statuses: transition.from, ids }, newValues: { status: transition.to, ids }, ipAddress: req.ip ?? null, requestId: typeof req.headers["x-request-id"] === "string" ? req.headers["x-request-id"] : null });
    res.json({ success: true, data: updated.data ?? [], meta: { updated: (updated.data ?? []).length, status: transition.to } });
  } catch (error) { next(error); }
}

for (const action of ["review", "approve", "publish"] as const) {
  router.post(`/results/students/:studentId/${action}`, requirePermission("student_requests.decide_department"), (req, res, next) => applyResultAction(req, res, next, action, true));
  router.post(`/results/bulk/${action}`, requirePermission("student_requests.decide_department"), (req, res, next) => applyResultAction(req, res, next, action, false));
}

async function serviceRequestRowsForScope(userId: string) {
  const db = getSupabase();
  const scope = await requestScope(userId);
  const requestSet = await db.from("student_service_requests").select("*").order("submitted_at", { ascending: false }).limit(1000);
  if (requestSet.error) throw requestSet.error;
  const requests = (requestSet.data ?? []) as AnyRow[];
  const studentIds = [...new Set(requests.map(row => row.student_id).filter(Boolean))];
  if (!studentIds.length) return { scope, rows: [] as AnyRow[] };
  const studentsResult = await db.from("students").select("id,student_number,first_name,middle_name,last_name,programme_id").in("id", studentIds);
  if (studentsResult.error) throw studentsResult.error;
  const students = (studentsResult.data ?? []) as AnyRow[];
  const programmeIds = [...new Set(students.map(row => row.programme_id).filter(Boolean))];
  const programmeSet = programmeIds.length ? await db.from("programmes").select("id,programme_code,programme_name,department_id").in("id", programmeIds) : { data: [], error: null };
  if (programmeSet.error) throw programmeSet.error;
  const yearIds = [...new Set(requests.map(row => row.academic_year_id).filter(Boolean))];
  const semesterIds = [...new Set(requests.map(row => row.semester_id).filter(Boolean))];
  const [yearSet, semesterSet] = await Promise.all([
    yearIds.length ? db.from("academic_years").select("id,year_code,year_name").in("id", yearIds) : Promise.resolve({ data: [], error: null }),
    semesterIds.length ? db.from("semesters").select("id,semester_code,semester_name").in("id", semesterIds) : Promise.resolve({ data: [], error: null }),
  ]);
  if (yearSet.error) throw yearSet.error;
  if (semesterSet.error) throw semesterSet.error;
  const makeMap = (items: AnyRow[]) => new Map(items.map(item => [String(item.id), item]));
  const studentMap = makeMap(students), programmeMap = makeMap((programmeSet.data ?? []) as AnyRow[]);
  const yearMap = makeMap((yearSet.data ?? []) as AnyRow[]), semesterMap = makeMap((semesterSet.data ?? []) as AnyRow[]);
  const rows: AnyRow[] = requests.map(row => {
    const student = studentMap.get(String(row.student_id)) ?? {};
    const programme = programmeMap.get(String(student.programme_id)) ?? {};
    const year = yearMap.get(String(row.academic_year_id)) ?? {};
    const semester = semesterMap.get(String(row.semester_id)) ?? {};
    return { ...row, request_category: "SERVICE", request_status: row.status, requested_at: row.submitted_at,
      student_number: student.student_number, student_name: [student.first_name, student.middle_name, student.last_name].filter(Boolean).join(" "),
      programme_code: programme.programme_code, programme_name: programme.programme_name, department_id: programme.department_id,
      academic_year: year.year_name || year.year_code || null, semester_name: semester.semester_name || semester.semester_code || null,
      course_code: null, course_name: row.subject };
  }).filter(row => scope.global || row.department_id === scope.departmentId);
  return { scope, rows };
}

router.get(
  "/",
  requirePermission("student_requests.view_department"),
  async (req, res, next) => {
    try {
      const db = getSupabase();
      const scope = await requestScope(req.user!.id);
      const page = Math.max(1, Number(req.query.page || 1));
      const limit = Math.min(100, Math.max(1, Number(req.query.limit || 25)));
      const from = (page - 1) * limit;

      let query = db.from("v_hod_student_requests").select("*");
      if (!scope.global) query = query.eq("department_id", scope.departmentId);
      const [{ data, error }, service] = await Promise.all([
        query.order("requested_at", { ascending: false }).limit(1000),
        serviceRequestRowsForScope(req.user!.id),
      ]);
      if (error) throw error;
      let combined: AnyRow[] = [...((data ?? []) as AnyRow[]), ...service.rows];
      const status = typeof req.query.status === "string" ? req.query.status.trim().toUpperCase() : "";
      if (status) combined = combined.filter(row => String(row.request_status).toUpperCase() === status);
      const search = typeof req.query.search === "string" ? req.query.search.trim().toLowerCase() : "";
      if (search) combined = combined.filter(row => [row.student_number, row.student_name, row.course_code, row.course_name, row.subject, row.request_type].some(value => String(value ?? "").toLowerCase().includes(search)));
      combined.sort((a, b) => Date.parse(b.requested_at || b.submitted_at || 0) - Date.parse(a.requested_at || a.submitted_at || 0));
      const total = combined.length;
      res.json({ success: true, data: combined.slice(from, from + limit), meta: { page, limit, total, departmentId: scope.departmentId } });
    } catch (error) { next(error); }
  }
);

router.post(
  "/:id/decision",
  requirePermission("student_requests.decide_department"),
  async (req, res, next) => {
    try {
      const decision = String(req.body?.decision || "").toUpperCase();
      if (!["APPROVED", "REJECTED"].includes(decision)) {
        return res.status(400).json({ success: false, message: "decision must be APPROVED or REJECTED" });
      }
      const db = getSupabase();
      const scope = await requestScope(req.user!.id);
      let accessQuery = db.from("v_hod_student_requests").select("*").eq("id", String(req.params.id));
      if (!scope.global) accessQuery = accessQuery.eq("department_id", scope.departmentId);
      const { data: addDropBefore, error: accessError } = await accessQuery.maybeSingle();
      if (accessError) throw accessError;
      const now = new Date().toISOString();
      if (addDropBefore) {
        if (addDropBefore.request_status !== "PENDING") return res.status(409).json({ success: false, message: `Request is already ${addDropBefore.request_status}.` });
        const patch = { request_status: decision, decision_reason: req.body?.reason || null, reviewed_by: req.user!.id, reviewed_at: now, updated_at: now };
        const { data: updated, error } = await db.from("course_add_drop_requests").update(patch).eq("id", addDropBefore.id).eq("request_status", "PENDING").select("*").single();
        if (error) throw error;
        await createAuditLog({ actorUserId: req.user!.id, actionCode: "HOD_STUDENT_REQUEST_DECISION", moduleCode: "STUDENT_REQUESTS", entityType: "course_add_drop_requests", entityId: addDropBefore.id, oldValues: addDropBefore, newValues: updated, ipAddress: req.ip ?? null, requestId: typeof req.headers["x-request-id"] === "string" ? req.headers["x-request-id"] : null });
        return res.json({ success: true, data: updated });
      }

      const service = await serviceRequestRowsForScope(req.user!.id);
      const before = service.rows.find(row => String(row.id) === String(req.params.id));
      if (!before) return res.status(404).json({ success: false, message: "Request was not found in your department." });
      if (!["SUBMITTED", "UNDER_REVIEW"].includes(String(before.request_status))) return res.status(409).json({ success: false, message: `Request is already ${before.request_status}.` });
      const updatedResult = await db.from("student_service_requests").update({ status: decision, review_comment: req.body?.reason || null, reviewed_by: req.user!.id, reviewed_at: now, updated_at: now }).eq("id", before.id).in("status", ["SUBMITTED", "UNDER_REVIEW"]).select("*").single();
      if (updatedResult.error) throw updatedResult.error;
      await createAuditLog({ actorUserId: req.user!.id, actionCode: "HOD_STUDENT_SERVICE_REQUEST_DECISION", moduleCode: "STUDENT_REQUESTS", entityType: "student_service_requests", entityId: before.id, oldValues: before, newValues: updatedResult.data, ipAddress: req.ip ?? null, requestId: typeof req.headers["x-request-id"] === "string" ? req.headers["x-request-id"] : null });
      return res.json({ success: true, data: updatedResult.data });
    } catch (error) { next(error); }
  }
);

export default router;
