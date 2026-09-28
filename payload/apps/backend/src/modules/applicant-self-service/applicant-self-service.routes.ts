import { Router, type Request, type Response } from "express";
import { authenticate } from "../../middleware/auth.js";
import { getSupabase } from "../../config/database.js";

const router = Router();
router.use(authenticate);

const editableStatuses = new Set(["DRAFT", "CORRECTION_REQUIRED"]);
const send = (res: Response, data: unknown, status = 200) => res.status(status).json({ success: true, data });
const fail = (res: Response, status: number, message: string) => res.status(status).json({ success: false, message });
const value = (input: unknown, max = 255) => typeof input === "string" ? input.trim().slice(0, max) : null;

function applicantNumber(): string {
  const stamp = new Date().toISOString().slice(0, 10).replace(/-/g, "");
  return `APP/${stamp}/${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
}

function applicationNumber(): string {
  const year = new Date().getUTCFullYear();
  return `IDMC/APP/${year}/${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
}

async function ownApplicant(req: Request) {
  return getSupabase().from("applicants").select("*").eq("auth_user_id", req.user!.authUserId).maybeSingle();
}

async function ownApplication(req: Request, id?: string) {
  const applicant = await ownApplicant(req);
  if (applicant.error || !applicant.data) return { applicant, application: null };
  let query = getSupabase().from("applications").select("*").eq("applicant_id", applicant.data.id);
  if (id) query = query.eq("id", id);
  const application = id ? await query.maybeSingle() : await query.order("created_at", { ascending: false });
  return { applicant, application };
}

function handler(fn: (req: Request, res: Response) => Promise<unknown>) {
  return async (req: Request, res: Response) => {
    try { await fn(req, res); }
    catch (error) {
      const message = error instanceof Error ? error.message : "Unexpected applicant service error";
      fail(res, 500, message);
    }
  };
}

router.get("/lookups/years", handler(async (_req, res) => {
  const result = await getSupabase().from("academic_years").select("id,year_code,year_name,start_date,end_date,status").eq("status", "ACTIVE").order("start_date", { ascending: false });
  if (result.error) throw result.error;
  send(res, result.data ?? []);
}));

router.get("/lookups/programmes", handler(async (_req, res) => {
  const result = await getSupabase().from("programmes").select("id,programme_code,programme_name,programme_type,award_level,mode_of_study,status").eq("status", "ACTIVE").order("programme_name");
  if (result.error) throw result.error;
  send(res, result.data ?? []);
}));

router.get("/applicants", handler(async (req, res) => {
  const result = await ownApplicant(req);
  if (result.error) throw result.error;
  send(res, result.data ? [result.data] : []);
}));

router.post("/applicants", handler(async (req, res) => {
  const existing = await ownApplicant(req);
  if (existing.error) throw existing.error;
  if (existing.data) return fail(res, 409, "An applicant profile already exists for this account.");
  const firstName = value(req.body?.firstName, 100);
  const lastName = value(req.body?.lastName, 100);
  const email = value(req.body?.email, 255) || req.user!.email;
  if (!firstName || !lastName || !email) return fail(res, 400, "First name, last name and email are required.");
  const payload = {
    applicant_number: applicantNumber(), first_name: firstName, middle_name: value(req.body?.middleName, 100), last_name: lastName,
    email, phone: value(req.body?.phone, 50), gender: value(req.body?.gender, 30), nationality: value(req.body?.nationality, 100),
    date_of_birth: value(req.body?.dateOfBirth, 10), profile_photo_url: value(req.body?.profilePhotoUrl, 3_000_000),
    auth_user_id: req.user!.authUserId, status: "ACTIVE", updated_at: new Date().toISOString()
  };
  const result = await getSupabase().from("applicants").insert(payload).select().single();
  if (result.error) throw result.error;
  send(res, result.data, 201);
}));

router.patch("/applicants/:id", handler(async (req, res) => {
  const applicant = await ownApplicant(req);
  if (applicant.error) throw applicant.error;
  if (!applicant.data || applicant.data.id !== req.params.id) return fail(res, 404, "Applicant profile not found.");
  const payload = {
    first_name: value(req.body?.firstName, 100), middle_name: value(req.body?.middleName, 100), last_name: value(req.body?.lastName, 100),
    email: value(req.body?.email, 255), phone: value(req.body?.phone, 50), gender: value(req.body?.gender, 30),
    nationality: value(req.body?.nationality, 100), date_of_birth: value(req.body?.dateOfBirth, 10),
    profile_photo_url: value(req.body?.profilePhotoUrl, 3_000_000), updated_at: new Date().toISOString()
  };
  if (!payload.first_name || !payload.last_name || !payload.email) return fail(res, 400, "First name, last name and email are required.");
  const result = await getSupabase().from("applicants").update(payload).eq("id", applicant.data.id).select().single();
  if (result.error) throw result.error;
  send(res, result.data);
}));

router.get("/applications", handler(async (req, res) => {
  const owned = await ownApplication(req);
  if (owned.applicant.error) throw owned.applicant.error;
  if (!owned.applicant.data) return send(res, []);
  if (owned.application?.error) throw owned.application.error;
  send(res, owned.application?.data ?? []);
}));

router.post("/applications", handler(async (req, res) => {
  const applicant = await ownApplicant(req);
  if (applicant.error) throw applicant.error;
  if (!applicant.data) return fail(res, 400, "Save the applicant profile first.");
  let academicYearId = value(req.body?.academicYearId, 80);
  if (!academicYearId) {
    const active = await getSupabase().from("academic_years").select("id").eq("status", "ACTIVE").order("start_date", { ascending: false }).limit(1).maybeSingle();
    if (active.error) throw active.error;
    academicYearId = active.data?.id ?? null;
  }
  if (!academicYearId) return fail(res, 400, "No active academic year is configured.");
  const payload = { applicant_id: applicant.data.id, academic_year_id: academicYearId, application_number: applicationNumber(), application_type: value(req.body?.applicationType, 50) || "NEW", application_round: value(req.body?.applicationRound, 50), status: "DRAFT", updated_at: new Date().toISOString() };
  const result = await getSupabase().from("applications").insert(payload).select().single();
  if (result.error) throw result.error;
  send(res, result.data, 201);
}));

router.patch("/applications/:id", handler(async (req, res) => {
  const owned = await ownApplication(req, String(req.params.id));
  if (owned.application?.error) throw owned.application.error;
  const current: any = owned.application?.data;
  if (!current) return fail(res, 404, "Application not found.");
  if (!editableStatuses.has(current.status)) return fail(res, 409, `Application cannot be edited while ${current.status}.`);
  const payload = { academic_year_id: value(req.body?.academicYearId, 80) || current.academic_year_id, application_type: value(req.body?.applicationType, 50) || current.application_type, application_round: value(req.body?.applicationRound, 50), updated_at: new Date().toISOString() };
  const result = await getSupabase().from("applications").update(payload).eq("id", current.id).select().single();
  if (result.error) throw result.error;
  send(res, result.data);
}));

type ChildConfig = { path: string; table: string; ownerColumn: "application_id" | "applicant_id"; fields: Record<string, string> };
const children: ChildConfig[] = [
  { path: "choices", table: "application_choices", ownerColumn: "application_id", fields: { programmeId: "programme_id", choiceNumber: "choice_number", preferenceType: "preference_type" } },
  { path: "qualifications", table: "academic_qualifications", ownerColumn: "applicant_id", fields: { qualificationType: "qualification_type", institutionName: "institution_name", country: "country", awardName: "award_name", indexNumber: "index_number", completionYear: "completion_year", grade: "grade", gpa: "gpa", fieldOfStudy: "field_of_study" } },
  { path: "documents", table: "application_documents", ownerColumn: "application_id", fields: { documentType: "document_type", documentName: "document_name", fileUrl: "file_url", fileSize: "file_size", mimeType: "mime_type", documentNumber: "document_number", issueDate: "issue_date", expiryDate: "expiry_date" } }
];

for (const config of children) {
  router.get(`/${config.path}`, handler(async (req, res) => {
    const applicant = await ownApplicant(req);
    if (applicant.error) throw applicant.error;
    if (!applicant.data) return send(res, []);
    if (config.ownerColumn === "applicant_id") {
      const result = await getSupabase().from(config.table).select("*").eq("applicant_id", applicant.data.id).order("created_at");
      if (result.error) throw result.error;
      return send(res, result.data ?? []);
    }
    const apps = await getSupabase().from("applications").select("id").eq("applicant_id", applicant.data.id);
    if (apps.error) throw apps.error;
    const ids = (apps.data ?? []).map(row => row.id);
    if (!ids.length) return send(res, []);
    const result = await getSupabase().from(config.table).select("*").in("application_id", ids).order(config.table === "application_documents" ? "uploaded_at" : "created_at");
    if (result.error) throw result.error;
    send(res, result.data ?? []);
  }));

  router.post(`/${config.path}`, handler(async (req, res) => {
    const applicant = await ownApplicant(req);
    if (applicant.error) throw applicant.error;
    if (!applicant.data) return fail(res, 400, "Save the applicant profile first.");
    const ownerId = config.ownerColumn === "applicant_id" ? applicant.data.id : value(req.body?.applicationId, 80);
    if (!ownerId) return fail(res, 400, "Application is required.");
    if (config.ownerColumn === "application_id") {
      const owned = await ownApplication(req, ownerId);
      const current: any = owned.application?.data;
      if (!current) return fail(res, 404, "Application not found.");
      if (!editableStatuses.has(current.status)) return fail(res, 409, `Application cannot be edited while ${current.status}.`);
    }
    const payload: Record<string, unknown> = { [config.ownerColumn]: ownerId, updated_at: new Date().toISOString() };
    for (const [input, column] of Object.entries(config.fields)) if (req.body?.[input] !== undefined) payload[column] = req.body[input] === "" ? null : req.body[input];
    const result = await getSupabase().from(config.table).insert(payload).select().single();
    if (result.error) throw result.error;
    send(res, result.data, 201);
  }));

  router.patch(`/${config.path}/:id`, handler(async (req, res) => {
    const applicant = await ownApplicant(req);
    if (applicant.error) throw applicant.error;
    if (!applicant.data) return fail(res, 404, "Applicant profile not found.");
    let ownership: any = getSupabase().from(config.table).select("*").eq("id", req.params.id);
    if (config.ownerColumn === "applicant_id") ownership = ownership.eq("applicant_id", applicant.data.id);
    const current = await ownership.maybeSingle();
    if (current.error) throw current.error;
    if (!current.data) return fail(res, 404, "Record not found.");
    if (config.ownerColumn === "application_id") {
      const owned = await ownApplication(req, String(current.data.application_id));
      const application: any = owned.application?.data;
      if (!application) return fail(res, 404, "Record not found.");
      if (!editableStatuses.has(application.status)) return fail(res, 409, `Application cannot be edited while ${application.status}.`);
    }
    const payload: Record<string, unknown> = { updated_at: new Date().toISOString() };
    for (const [input, column] of Object.entries(config.fields)) if (req.body?.[input] !== undefined) payload[column] = req.body[input] === "" ? null : req.body[input];
    const result = await getSupabase().from(config.table).update(payload).eq("id", req.params.id).select().single();
    if (result.error) throw result.error;
    send(res, result.data);
  }));

  router.delete(`/${config.path}/:id`, handler(async (req, res) => {
    const applicant = await ownApplicant(req);
    if (applicant.error) throw applicant.error;
    if (!applicant.data) return fail(res, 404, "Applicant profile not found.");
    let ownership: any = getSupabase().from(config.table).select("*").eq("id", req.params.id);
    if (config.ownerColumn === "applicant_id") ownership = ownership.eq("applicant_id", applicant.data.id);
    const current = await ownership.maybeSingle();
    if (current.error) throw current.error;
    if (!current.data) return fail(res, 404, "Record not found.");
    if (config.ownerColumn === "application_id") {
      const owned = await ownApplication(req, String(current.data.application_id));
      const application: any = owned.application?.data;
      if (!application || !editableStatuses.has(application.status)) return fail(res, 409, "Only draft application records can be deleted.");
    }
    const result = await getSupabase().from(config.table).delete().eq("id", req.params.id);
    if (result.error) throw result.error;
    send(res, { id: req.params.id });
  }));
}

router.post("/applications/:id/submit", handler(async (req, res) => {
  const owned = await ownApplication(req, String(req.params.id));
  if (owned.application?.error) throw owned.application.error;
  const application: any = owned.application?.data;
  if (!application) return fail(res, 404, "Application not found.");
  if (!editableStatuses.has(application.status)) return fail(res, 409, `Application is already ${application.status}.`);
  const db = getSupabase();
  const [choices, qualifications, documents] = await Promise.all([
    db.from("application_choices").select("id", { count: "exact", head: true }).eq("application_id", application.id),
    db.from("academic_qualifications").select("id", { count: "exact", head: true }).eq("applicant_id", application.applicant_id),
    db.from("application_documents").select("id", { count: "exact", head: true }).eq("application_id", application.id)
  ]);
  if (!choices.count || !qualifications.count || !documents.count) return fail(res, 400, "Add at least one programme choice, qualification and document before submission.");
  const now = new Date().toISOString();
  const result = await db.from("applications").update({ status: "SUBMITTED", submitted_at: now, completion_percentage: 100, updated_at: now }).eq("id", application.id).select().single();
  if (result.error) throw result.error;
  send(res, result.data);
}));

export default router;
