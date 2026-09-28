import express, { Router, type Request, type Response } from "express";
import { randomUUID } from "node:crypto";
import { authenticate } from "../../middleware/auth.js";
import { getSupabase } from "../../config/database.js";
import { env } from "../../config/env.js";
import { buildAdmissionPdf } from "./admission-pdf.js";

const router = Router();
router.use(authenticate);

const editableStatuses = new Set(["DRAFT", "CORRECTION_REQUIRED"]);
const documentUploadStatuses = new Set(["DRAFT", "CORRECTION_REQUIRED", "SUBMITTED", "UNDER_REVIEW"]);
const send = (res: Response, data: unknown, status = 200) => res.status(status).json({ success: true, data });
const fail = (res: Response, status: number, message: string) => res.status(status).json({ success: false, message });
const value = (input: unknown, max = 255) => typeof input === "string" ? input.trim().slice(0, max) : null;

function applicantNumber(): string {
  const stamp = new Date().toISOString().slice(0, 10).replace(/-/g, "");
  return `APP/${stamp}/${randomUUID().slice(0, 8).toUpperCase()}`;
}

function applicationNumber(): string {
  const year = new Date().getUTCFullYear();
  return `IDMC/APP/${year}/${randomUUID().slice(0, 8).toUpperCase()}`;
}

const allowedDocumentTypes = new Set(["RESULT_SLIP", "CERTIFICATE", "ACADEMIC_CERTIFICATE", "BIRTH_CERTIFICATE", "IDENTITY", "OTHER"]);
const allowedMimeTypes = new Set(["application/pdf", "image/jpeg", "image/png", "image/webp"]);

function validIndexNumber(input: string): boolean {
  return /^[A-Z]\d{4}\/\d{4}\/\d{4}$/i.test(input) || /^[A-Z0-9][A-Z0-9./-]{7,29}$/i.test(input);
}

function qualificationMeta(input: unknown): Record<string, any> {
  if (typeof input !== "string" || !input.trim().startsWith("{")) return {};
  try { return JSON.parse(input); } catch { return {}; }
}

function qualificationMetaText(input: Record<string, any>): string {
  let result = JSON.stringify(input);
  if (result.length <= 4000) return result;
  const compact: Record<string, any> = { ...input, subjects: Array.isArray(input.subjects) ? input.subjects.slice(0, 10) : undefined };
  result = JSON.stringify(compact);
  if (result.length <= 4000) return result;
  delete compact.subjects;
  return JSON.stringify(compact);
}

async function ownQualification(req: Request, id: string) {
  const applicant = await ownApplicant(req);
  if (applicant.error || !applicant.data) return { applicant, qualification: null };
  const qualification = await getSupabase().from("academic_qualifications").select("*").eq("id", id).eq("applicant_id", applicant.data.id).maybeSingle();
  return { applicant, qualification };
}

async function applicationsOpen(): Promise<boolean> {
  const result = await getSupabase().from("system_feature_flags").select("is_enabled").eq("feature_code", "ONLINE_APPLICATIONS").limit(1).maybeSingle();
  if (result.error) throw result.error;
  return result.data ? Boolean(result.data.is_enabled) : true;
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

async function editableApplication(req: Request) {
  const owned = await ownApplication(req);
  if (owned.applicant.error) throw owned.applicant.error;
  if (owned.application?.error) throw owned.application.error;
  const applications: any[] = Array.isArray(owned.application?.data) ? owned.application.data : [];
  const application = applications[0] ?? null;
  return application && editableStatuses.has(application.status) ? application : null;
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

router.get("/online-status", handler(async (_req, res) => {
  send(res, { open: await applicationsOpen() });
}));

router.post("/start", handler(async (req, res) => {
  const db = getSupabase();
  let applicantResult = await ownApplicant(req);
  if (applicantResult.error) throw applicantResult.error;
  let applicant: any = applicantResult.data;
  if (!applicant) {
    if (!(await applicationsOpen())) return fail(res, 409, "Online applications are currently closed by the Admissions Office.");
    const created = await db.from("applicants").insert({
      applicant_number: applicantNumber(), first_name: req.user!.firstName || "Applicant", last_name: req.user!.lastName || "Account",
      email: req.user!.email, auth_user_id: req.user!.authUserId, applicant_type: "NEW", status: "ACTIVE", updated_at: new Date().toISOString()
    }).select().single();
    if (created.error) throw created.error;
    applicant = created.data;
  }
  const existing = await db.from("applications").select("*").eq("applicant_id", applicant.id).order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (existing.error) throw existing.error;
  if (existing.data) return send(res, { applicant, application: existing.data, created: false });
  if (!(await applicationsOpen())) return fail(res, 409, "Online applications are currently closed by the Admissions Office.");
  const activeYear = await db.from("academic_years").select("id").eq("status", "ACTIVE").order("start_date", { ascending: false }).limit(1).maybeSingle();
  if (activeYear.error) throw activeYear.error;
  if (!activeYear.data) return fail(res, 409, "No active academic year is configured.");
  const application = await db.from("applications").insert({ applicant_id: applicant.id, academic_year_id: activeYear.data.id, application_number: applicationNumber(), application_type: "NEW", status: "DRAFT", updated_at: new Date().toISOString() }).select().single();
  if (application.error) throw application.error;
  send(res, { applicant, application: application.data, created: true }, 201);
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
  if (!(await applicationsOpen())) return fail(res, 409, "Online applications are currently closed by the Admissions Office.");
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

router.post("/qualifications/verify", handler(async (req, res) => {
  const applicant = await ownApplicant(req);
  if (applicant.error) throw applicant.error;
  if (!applicant.data) return fail(res, 400, "Save the applicant profile first.");
  if (!(await editableApplication(req))) return fail(res, 409, "Academic qualifications are read-only after application submission. Ask Admissions to request a correction.");
  const indexNumber = String(value(req.body?.indexNumber, 100) || "").toUpperCase();
  const examinationYear = req.body?.examinationYear ? Number(req.body.examinationYear) : null;
  if (!validIndexNumber(indexNumber)) return fail(res, 400, "Enter a valid examination index number, for example S1234/0001/2025.");
  if (examinationYear !== null && (!Number.isInteger(examinationYear) || examinationYear < 1980 || examinationYear > new Date().getFullYear())) return fail(res, 400, "Enter a valid examination year.");

  if (!env.NATIONAL_RESULTS_PROVIDER_URL || !env.NATIONAL_RESULTS_PROVIDER_API_KEY) {
    const existing = await getSupabase().from("academic_qualifications").select("id").eq("applicant_id", applicant.data.id).eq("index_number", indexNumber).maybeSingle();
    const meta = { provider: null, examType: "CSEE", indexNumber, verification: "REQUIRES_REVIEW", message: "Official national results provider is not configured. Admission staff review is required." };
    const payload = { applicant_id: applicant.data.id, qualification_type: "SECONDARY", institution_name: "Pending official or institutional verification", country: "TANZANIA, UNITED REPUBLIC OF", award_name: "CSE", index_number: indexNumber, completion_year: examinationYear, verification_status: "REQUIRES_REVIEW", verification_comments: qualificationMetaText(meta), updated_at: new Date().toISOString() };
    const saved = existing.data
      ? await getSupabase().from("academic_qualifications").update(payload).eq("id", existing.data.id).select().single()
      : await getSupabase().from("academic_qualifications").insert(payload).select().single();
    if (saved.error) throw saved.error;
    return res.status(202).json({ success: true, data: saved.data, verification: "REQUIRES_REVIEW", message: "Index number saved. Official provider is not configured, so Admissions must verify it manually." });
  }

  const providerResponse = await fetch(env.NATIONAL_RESULTS_PROVIDER_URL, {
    method: "POST",
    headers: { "Accept": "application/json", "Content-Type": "application/json", "Authorization": `Bearer ${env.NATIONAL_RESULTS_PROVIDER_API_KEY}` },
    body: JSON.stringify(examinationYear ? { indexNumber, examinationYear } : { indexNumber }),
    signal: AbortSignal.timeout(15000),
  });
  const providerEnvelope: any = await providerResponse.json().catch(() => null);
  if (!providerResponse.ok || !providerEnvelope) return fail(res, 502, "The authorised examination-results provider could not verify this index number.");
  const providerData: any = providerEnvelope.data ?? providerEnvelope.result ?? providerEnvelope;
  const division = String(providerData.division ?? providerData.results?.division ?? "").toUpperCase();
  const points = providerData.points ?? providerData.results?.points ?? null;
  const schoolName = providerData.centerName ?? providerData.center_name ?? providerData.schoolName ?? providerData.school_name;
  const candidateName = providerData.candidateName ?? providerData.candidate_name ?? providerData.name;
  const examType = providerData.examType ?? providerData.exam_type ?? "CSEE";
  const startYear = Number(providerData.startYear ?? providerData.start_year) || null;
  const endYear = Number(providerData.endYear ?? providerData.end_year ?? providerData.completionYear ?? providerData.year ?? examinationYear) || null;
  const eligible = providerData.eligible !== false && providerData.passed !== false && !["0", "DIVISION 0", "FAIL", "FAILED"].includes(division);
  const verificationStatus = eligible ? "VERIFIED" : "REJECTED";
  const providerSummary = qualificationMetaText({ provider: providerEnvelope.provider ?? providerData.provider ?? "NATIONAL_RESULTS_PROVIDER", candidateName, centerName: schoolName, examType, startYear, endYear, division, points, subjects: providerData.subjects ?? providerData.results?.subjects, indexNumber });
  const existing = await getSupabase().from("academic_qualifications").select("id").eq("applicant_id", applicant.data.id).eq("index_number", indexNumber).maybeSingle();
  const payload = { applicant_id: applicant.data.id, qualification_type: "SECONDARY", institution_name: value(schoolName, 255) || "Verified examination centre", country: "TANZANIA, UNITED REPUBLIC OF", award_name: "CSE", index_number: indexNumber, start_year: startYear, completion_year: endYear, grade: division || value(providerData.grade, 100), verification_status: verificationStatus, verified_at: new Date().toISOString(), verification_comments: providerSummary, updated_at: new Date().toISOString() };
  const saved = existing.data
    ? await getSupabase().from("academic_qualifications").update(payload).eq("id", existing.data.id).select().single()
    : await getSupabase().from("academic_qualifications").insert(payload).select().single();
  if (saved.error) throw saved.error;
  if (!eligible) return res.status(422).json({ success: false, message: "The official result does not meet the minimum pass requirement.", data: saved.data });
  send(res, { qualification: saved.data, provider: { candidateName, centerName: schoolName, examType, startYear, endYear, division, points, subjects: providerData.subjects ?? providerData.results?.subjects } });
}));

router.post("/qualifications/:id/request-removal", handler(async (req, res) => {
  if (!(await editableApplication(req))) return fail(res, 409, "A converted or submitted application is read-only. Contact Admissions for record correction.");
  const owned = await ownQualification(req, String(req.params.id));
  if (owned.qualification?.error) throw owned.qualification.error;
  const current: any = owned.qualification?.data;
  if (!current) return fail(res, 404, "Academic qualification not found.");
  const reason = value(req.body?.reason, 1000);
  if (!reason) return fail(res, 400, "Enter the reason for requesting removal.");
  const meta = qualificationMeta(current.verification_comments);
  meta.removalRequest = { status: "PENDING", reason, requestedAt: new Date().toISOString(), previousVerificationStatus: current.verification_status };
  const result = await getSupabase().from("academic_qualifications").update({ verification_status: "REQUIRES_REVIEW", verification_comments: qualificationMetaText(meta), updated_at: new Date().toISOString() }).eq("id", current.id).select().single();
  if (result.error) throw result.error;
  send(res, result.data);
}));

router.post("/qualifications/:id/certificate", express.raw({ type: "application/octet-stream", limit: "6mb" }), handler(async (req, res) => {
  const owned = await ownQualification(req, String(req.params.id));
  if (owned.qualification?.error) throw owned.qualification.error;
  const qualification: any = owned.qualification?.data;
  if (!qualification || !owned.applicant.data) return fail(res, 404, "Academic qualification not found.");
  const applicationId = String(value(req.headers["x-application-id"], 80) || "");
  const fileName = String(value(req.headers["x-file-name"], 255) || "").replace(/[^a-zA-Z0-9._-]/g, "_");
  const mimeType = String(value(req.headers["x-mime-type"], 100) || "application/octet-stream").toLowerCase();
  if (!applicationId || !fileName) return fail(res, 400, "Application and certificate file are required.");
  if (!allowedMimeTypes.has(mimeType)) return fail(res, 400, "Only PDF, JPEG, PNG and WebP certificates are allowed.");
  const applicationOwned = await ownApplication(req, applicationId);
  const application: any = applicationOwned.application?.data;
  if (!application || !documentUploadStatuses.has(application.status)) return fail(res, 409, `Academic certificates cannot be changed while the application is ${application?.status ?? "unavailable"}.`);
  const body = req.body as Buffer;
  if (!Buffer.isBuffer(body) || body.length < 100) return fail(res, 400, "The selected certificate is empty or invalid.");
  const storagePath = `applicants/${owned.applicant.data.id}/${applicationId}/qualifications/${qualification.id}/${Date.now()}-${randomUUID().slice(0, 8)}-${fileName}`;
  const upload = await getSupabase().storage.from("idmc-private-documents").upload(storagePath, body, { contentType: mimeType, upsert: false });
  if (upload.error) throw upload.error;
  const previous = await getSupabase().from("application_documents").select("id,file_url").eq("application_id", applicationId).eq("document_type", "ACADEMIC_CERTIFICATE").eq("document_number", qualification.id);
  if (previous.error) throw previous.error;
  const documentStatus = application.status === "UNDER_REVIEW" ? "UNDER_REVIEW" : "PENDING";
  const saved = await getSupabase().from("application_documents").insert({ application_id: applicationId, document_type: "ACADEMIC_CERTIFICATE", document_name: fileName, file_url: storagePath, file_size: body.length, mime_type: mimeType, document_number: qualification.id, verification_status: documentStatus, uploaded_at: new Date().toISOString() }).select().single();
  if (saved.error) { await getSupabase().storage.from("idmc-private-documents").remove([storagePath]); throw saved.error; }
  if ((previous.data ?? []).length) {
    await getSupabase().from("application_documents").delete().in("id", (previous.data ?? []).map(row => row.id));
    await getSupabase().storage.from("idmc-private-documents").remove((previous.data ?? []).map(row => row.file_url));
  }
  send(res, saved.data, 201);
}));

router.post("/documents/upload", express.raw({ type: "application/octet-stream", limit: "6mb" }), handler(async (req, res) => {
  const applicant = await ownApplicant(req);
  if (applicant.error) throw applicant.error;
  if (!applicant.data) return fail(res, 400, "Save the applicant profile first.");
  const applicationId = String(value(req.headers["x-application-id"], 80) || "");
  const documentType = String(value(req.headers["x-document-type"], 80) || "").toUpperCase();
  const fileName = String(value(req.headers["x-file-name"], 255) || "").replace(/[^a-zA-Z0-9._-]/g, "_");
  const mimeType = String(value(req.headers["x-mime-type"], 100) || "application/octet-stream").toLowerCase();
  if (!applicationId || !documentType || !fileName) return fail(res, 400, "Application, document type and file are required.");
  if (!allowedDocumentTypes.has(documentType)) return fail(res, 400, "Unsupported application document type.");
  if (!allowedMimeTypes.has(mimeType)) return fail(res, 400, "Only PDF, JPEG, PNG and WebP documents are allowed.");
  const body = req.body as Buffer;
  if (!Buffer.isBuffer(body) || body.length < 100) return fail(res, 400, "The selected document is empty or invalid.");
  const owned = await ownApplication(req, applicationId);
  const application: any = owned.application?.data;
  if (!application || !documentUploadStatuses.has(application.status)) return fail(res, 409, `Documents cannot be uploaded while the application is ${application?.status ?? "unavailable"}.`);
  const storagePath = `applicants/${applicant.data.id}/${applicationId}/${Date.now()}-${randomUUID().slice(0, 8)}-${fileName}`;
  const upload = await getSupabase().storage.from("idmc-private-documents").upload(storagePath, body, { contentType: mimeType, upsert: false });
  if (upload.error) throw upload.error;
  const documentStatus = application.status === "UNDER_REVIEW" ? "UNDER_REVIEW" : "PENDING";
  const saved = await getSupabase().from("application_documents").insert({ application_id: applicationId, document_type: documentType, document_name: fileName, file_url: storagePath, file_size: body.length, mime_type: mimeType, verification_status: documentStatus, uploaded_at: new Date().toISOString() }).select().single();
  if (saved.error) { await getSupabase().storage.from("idmc-private-documents").remove([storagePath]); throw saved.error; }
  send(res, saved.data, 201);
}));

router.get("/applications/:id/readiness", handler(async (req, res) => {
  const owned = await ownApplication(req, String(req.params.id));
  const application: any = owned.application?.data;
  if (!application) return fail(res, 404, "Application not found.");
  const db = getSupabase();
  const [choices, qualifications, documents] = await Promise.all([
    db.from("application_choices").select("id,status").eq("application_id", application.id),
    db.from("academic_qualifications").select("id,verification_status,verification_comments,index_number,institution_name,grade").eq("applicant_id", application.applicant_id),
    db.from("application_documents").select("id,document_type,document_name,verification_status").eq("application_id", application.id),
  ]);
  for (const result of [choices, qualifications, documents]) if (result.error) throw result.error;
  const blockers: string[] = [];
  if (!(choices.data ?? []).length) blockers.push("Add at least one programme choice.");
  if (!(qualifications.data ?? []).length) blockers.push("Add and verify an academic qualification.");
  if ((qualifications.data ?? []).some(row => row.verification_status === "REJECTED")) blockers.push("A rejected qualification must be corrected before submission.");
  if ((qualifications.data ?? []).some(row => qualificationMeta(row.verification_comments).removalRequest?.status === "PENDING")) blockers.push("A qualification removal request is awaiting Admissions review.");
  if (!(documents.data ?? []).length) blockers.push("Upload at least one supporting document.");
  send(res, { ready: blockers.length === 0, blockers, application, choices: choices.data ?? [], qualifications: qualifications.data ?? [], documents: documents.data ?? [] });
}));

router.get("/applications/:id/offer", handler(async (req, res) => {
  const owned = await ownApplication(req, String(req.params.id));
  if (owned.application?.error) throw owned.application.error;
  const application: any = owned.application?.data;
  if (!application) return fail(res, 404, "Application not found.");
  const result = await getSupabase().from("admission_offers").select("*").eq("application_id", application.id).order("issued_at", { ascending: false }).limit(1).maybeSingle();
  if (result.error) throw result.error;
  if (!result.data) return fail(res, 404, "The Admissions Office has not issued an offer yet.");
  send(res, result.data);
}));

router.post("/applications/:id/offer/accept", handler(async (req, res) => {
  if (req.body?.confirmed !== true) return fail(res, 400, "Confirm that you accept the admission offer.");
  const owned = await ownApplication(req, String(req.params.id));
  if (owned.application?.error) throw owned.application.error;
  const application: any = owned.application?.data;
  const applicant: any = owned.applicant.data;
  if (!application || !applicant) return fail(res, 404, "Application not found.");
  if (application.status === "CONVERTED_TO_STUDENT") {
    const existing = await getSupabase().from("students").select("id,student_number,registration_number,student_status").eq("source_application_id", application.id).maybeSingle();
    if (existing.error) throw existing.error;
    return send(res, { application, student: existing.data, alreadyConverted: true });
  }
  if (application.status !== "ADMISSION_OFFERED") return fail(res, 409, `The offer cannot be accepted while the application is ${application.status}.`);
  const db = getSupabase();
  const offer = await db.from("admission_offers").select("*").eq("application_id", application.id).eq("offer_status", "ISSUED").order("issued_at", { ascending: false }).limit(1).maybeSingle();
  if (offer.error) throw offer.error;
  if (!offer.data) return fail(res, 409, "No active admission offer is available.");
  if (offer.data.expiry_date && offer.data.expiry_date < new Date().toISOString().slice(0, 10)) return fail(res, 409, "The admission offer has expired. Contact Admissions.");
  const accepted = await db.from("admission_acceptances").upsert({
    admission_offer_id: offer.data.id, acceptance_status: "ACCEPTED", accepted_at: new Date().toISOString(),
    declined_at: null, decline_reason: null, acceptance_ip_address: req.ip || null,
    acceptance_user_agent: String(req.headers["user-agent"] || "").slice(0, 1000), accepted_by: req.user!.id,
    updated_at: new Date().toISOString()
  }, { onConflict: "admission_offer_id" }).select("*").single();
  if (accepted.error) throw accepted.error;
  const converted = await db.rpc("convert_accepted_application_to_student", { p_application_id: application.id });
  if (converted.error) throw converted.error;
  const student = await db.from("students").update({
    user_id: req.user!.id, first_name: applicant.first_name, middle_name: applicant.middle_name,
    last_name: applicant.last_name, gender: applicant.gender, date_of_birth: applicant.date_of_birth,
    nationality: applicant.nationality, phone: applicant.phone, email: applicant.email,
    student_status: "PENDING_ACTIVATION", updated_at: new Date().toISOString()
  }).eq("id", converted.data).select("*").single();
  if (student.error) throw student.error;
  const role = await db.from("roles").select("id").eq("role_code", "STUDENT").eq("status", "ACTIVE").maybeSingle();
  if (role.error) throw role.error;
  if (!role.data) return fail(res, 409, "The active STUDENT role is not configured.");
  const assignment = await db.from("user_roles").upsert({ user_id: req.user!.id, role_id: role.data.id, assigned_by: req.user!.id, status: "ACTIVE" }, { onConflict: "user_id,role_id" });
  if (assignment.error) throw assignment.error;
  send(res, { applicationId: application.id, acceptance: accepted.data, student: student.data }, 201);
}));

router.get("/applications/:id/:document.pdf", handler(async (req, res) => {
  const owned = await ownApplication(req, String(req.params.id));
  if (owned.application?.error) throw owned.application.error;
  const application: any = owned.application?.data;
  const applicant: any = owned.applicant.data;
  if (!application || !applicant) return fail(res, 404, "Application not found.");
  const documentName = String(req.params.document || "");
  if (!["acknowledgement", "joining-instructions"].includes(documentName)) return fail(res, 404, "Application document not found.");
  const joining = documentName === "joining-instructions";
  const joiningStatuses = new Set(["SELECTED", "ADMISSION_OFFERED", "ACCEPTED", "CONVERTED_TO_STUDENT"]);
  if (joining && !joiningStatuses.has(application.status)) return fail(res, 409, "Joining instructions become available after admission approval.");
  if (!joining && editableStatuses.has(application.status)) return fail(res, 409, "Submit the application before downloading its acknowledgement.");
  const db = getSupabase();
  const [choice, year, qualifications] = await Promise.all([
    db.from("application_choices").select("programme_id").eq("application_id", application.id).order("choice_number").limit(1).maybeSingle(),
    db.from("academic_years").select("year_code,year_name").eq("id", application.academic_year_id).maybeSingle(),
    db.from("academic_qualifications").select("index_number,qualification_type").eq("applicant_id", applicant.id).order("created_at")
  ]);
  for (const result of [choice, year, qualifications]) if (result.error) throw result.error;
  let programmeName = "Pending programme confirmation";
  if (choice.data?.programme_id) {
    const programme = await db.from("programmes").select("programme_code,programme_name").eq("id", choice.data.programme_id).maybeSingle();
    if (programme.error) throw programme.error;
    if (programme.data) programmeName = `${programme.data.programme_code} - ${programme.data.programme_name}`;
  }
  const csee = (qualifications.data ?? []).find(row => row.qualification_type === "SECONDARY") ?? (qualifications.data ?? [])[0];
  const pdf = buildAdmissionPdf({
    kind: joining ? "JOINING_INSTRUCTIONS" : "ACKNOWLEDGEMENT",
    applicantName: [applicant.first_name, applicant.middle_name, applicant.last_name].filter(Boolean).join(" "),
    applicantNumber: applicant.applicant_number,
    applicationNumber: application.application_number,
    programmeName,
    academicYear: year.data?.year_code || year.data?.year_name || String(new Date().getUTCFullYear()),
    indexNumber: csee?.index_number || ""
  });
  const fileName = joining ? `IDMC-Joining-Instructions-${application.application_number.replace(/[^A-Za-z0-9-]/g, "-")}.pdf` : `IDMC-Application-Acknowledgement-${application.application_number.replace(/[^A-Za-z0-9-]/g, "-")}.pdf`;
  res.setHeader("Content-Type", "application/pdf");
  res.setHeader("Content-Disposition", `attachment; filename="${fileName}"`);
  res.setHeader("Content-Length", String(pdf.length));
  res.status(200).send(pdf);
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
  { path: "qualifications", table: "academic_qualifications", ownerColumn: "applicant_id", fields: { qualificationType: "qualification_type", institutionName: "institution_name", country: "country", awardName: "award_name", indexNumber: "index_number", startYear: "start_year", completionYear: "completion_year", grade: "grade", gpa: "gpa", fieldOfStudy: "field_of_study" } },
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
    if (config.path === "qualifications" && !(await editableApplication(req))) return fail(res, 409, "Academic qualifications are read-only after application submission. Ask Admissions to request a correction.");
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
    if (config.path === "qualifications" && !(await editableApplication(req))) return fail(res, 409, "Academic qualifications are read-only after application submission. Ask Admissions to request a correction.");
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
    if (config.path === "qualifications" && !(await editableApplication(req))) return fail(res, 409, "Academic qualifications are read-only after application submission. Ask Admissions to request a correction.");
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
  if (req.body?.confirmed !== true) return fail(res, 400, "Confirm that the application information is complete and correct before submission.");
  if (!choices.count || !qualifications.count || !documents.count) return fail(res, 400, "Add at least one programme choice, qualification and document before submission.");
  const rejected = await db.from("academic_qualifications").select("id", { count: "exact", head: true }).eq("applicant_id", application.applicant_id).eq("verification_status", "REJECTED");
  if (rejected.error) throw rejected.error;
  if (rejected.count) return fail(res, 409, "A rejected qualification must be corrected before submission.");
  const removalChecks = await db.from("academic_qualifications").select("verification_comments").eq("applicant_id", application.applicant_id);
  if (removalChecks.error) throw removalChecks.error;
  if ((removalChecks.data ?? []).some(row => qualificationMeta(row.verification_comments).removalRequest?.status === "PENDING")) return fail(res, 409, "Wait for Admissions to decide the qualification removal request before submitting.");
  const now = new Date().toISOString();
  const result = await db.from("applications").update({ status: "SUBMITTED", submitted_at: now, completion_percentage: 100, updated_at: now }).eq("id", application.id).select().single();
  if (result.error) throw result.error;
  send(res, result.data);
}));

export default router;
