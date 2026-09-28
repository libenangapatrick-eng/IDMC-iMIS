import { createHash, randomUUID } from "node:crypto";
import { Router, type Request } from "express";
import { getSupabase } from "../../config/database.js";
import { authenticate } from "../../middleware/auth.js";
import { requirePermission } from "../../middleware/rbac.js";
import { createAuditLog } from "../../services/audit.service.js";
import { parseSpreadsheet, type SpreadsheetRow } from "./spreadsheet.js";

type Row = Record<string, any>;
const router = Router();
router.use(authenticate);

const allowedStatuses = new Set(["PENDING_ACTIVATION","ACTIVE","DEFERRED","SUSPENDED","WITHDRAWN","COMPLETED","GRADUATED","EXPELLED","INACTIVE"]);
const key = (value: unknown) => String(value ?? "").trim();
const upper = (value: unknown) => key(value).toUpperCase();
const integer = (value: unknown) => /^\d+$/.test(key(value)) ? Number(value) : null;
const field = (row: SpreadsheetRow, ...names: string[]) => {
  const entry = Object.entries(row).find(([name]) => names.includes(name.replace(/[\s_-]/g, "").toLowerCase()));
  return key(entry?.[1]);
};
const actor = (req: Request) => req.user!.id;

function officialRegistrationNumber(indexNumber: string, completionYear: number | null): string | null {
  let normalized = upper(indexNumber).replace(/\s+/g, "");
  let year = completionYear;
  const complete = normalized.match(/^(S\d{4})[-/](\d{4})\/(\d{4})$/);
  if (complete) { normalized = `${complete[1]}/${complete[2]}`; year = Number(complete[3]); }
  const match = normalized.match(/^(S\d{4})[-/](\d{4})$/);
  if (!match || !year || year < 1950 || year > new Date().getUTCFullYear()) return null;
  return `N${match[1]}/${match[2]}/${year}`;
}

async function allExistingStudentNumbers() {
  const db = getSupabase();
  const rows: Row[] = [];
  const pageSize = 1000;
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await db.from("students").select("id,student_number,registration_number").range(from, from + pageSize - 1);
    if (error) throw error;
    rows.push(...(data ?? []));
    if ((data?.length ?? 0) < pageSize) break;
  }
  return rows;
}

async function references() {
  const db = getSupabase();
  const [institutions, cohorts, programmes, versions, curricula, years, semesters, existing] = await Promise.all([
    db.from("institutions").select("id,institution_code,institution_name,status").eq("institution_code", "IDMS"),
    db.from("student_cohorts").select("id,institution_id,cohort_code,cohort_name,entry_year,status,default_academic_year_id"),
    db.from("programmes").select("id,institution_id,programme_code,programme_name,status,department_id,school_id"),
    db.from("programme_versions").select("id,programme_id,version_code,version_name,effective_from,effective_to,status"),
    db.from("curricula").select("id,programme_version_id,curriculum_code,curriculum_name,status"),
    db.from("academic_years").select("id,year_code,year_name,status,start_date,end_date"),
    db.from("semesters").select("id,academic_year_id,semester_code,semester_name,semester_number,status"),
    allExistingStudentNumbers(),
  ]);
  for (const result of [institutions, cohorts, programmes, versions, curricula, years, semesters]) if (result.error) throw result.error;
  return { institution: institutions.data?.[0], cohorts: cohorts.data ?? [], programmes: programmes.data ?? [], versions: versions.data ?? [], curricula: curricula.data ?? [], years: years.data ?? [], semesters: semesters.data ?? [], existing };
}

async function validateRows(inputRows: SpreadsheetRow[]) {
  if (!Array.isArray(inputRows) || !inputRows.length) throw new Error("The import contains no student rows.");
  if (inputRows.length > 5000) throw new Error("One batch cannot exceed 5,000 students.");
  const refs = await references();
  if (!refs.institution) throw new Error("Official IDMS institution record was not found.");
  const institution = refs.institution;
  const existing = new Set(refs.existing.map((row: Row) => upper(row.student_number)));
  const existingRegistrations = new Set(refs.existing.map((row: Row) => upper(row.registration_number)).filter(Boolean));
  const seen = new Set<string>();
  const seenRegistrations = new Set<string>();
  const rows = inputRows.map((raw, index) => {
    const studentNumber = upper(field(raw, "studentnumber", "registrationnumber", "regno"));
    const firstName = field(raw, "firstname", "givenname");
    const middleName = field(raw, "middlename");
    const lastName = field(raw, "lastname", "surname");
    const cohortYear = integer(field(raw, "cohortyear", "cohort", "entryyear", "admissionyear"));
    const programmeCode = upper(field(raw, "programmecode", "programme", "programcode"));
    const versionCode = upper(field(raw, "programmeversioncode", "programversioncode", "versioncode", "programmeversion"));
    const academicYearCode = field(raw, "academicyear", "entryacademicyear") || (cohortYear ? `${cohortYear}/${cohortYear + 1}` : "");
    const sourceIndexNumber = upper(field(raw, "formfourindex", "indexnumber", "cseeindex"));
    const sourceExamYear = integer(field(raw, "formfouryear", "completionyear", "cseeyear"));
    const registrationNumber = upper(field(raw, "officialregistrationnumber", "nectaregistrationnumber")) || officialRegistrationNumber(sourceIndexNumber, sourceExamYear);
    const status = upper(field(raw, "studentstatus", "status") || "ACTIVE");
    const errors: string[] = [];
    if (!studentNumber) errors.push("STUDENT_NUMBER_REQUIRED");
    if (!firstName) errors.push("FIRST_NAME_REQUIRED");
    if (!lastName) errors.push("LAST_NAME_REQUIRED");
    if (!cohortYear || cohortYear < 2023 || cohortYear > 2026) errors.push("COHORT_YEAR_MUST_BE_2023_TO_2026");
    const programme = refs.programmes.find((row: Row) => upper(row.programme_code) === programmeCode);
    if (!programme) errors.push("UNKNOWN_PROGRAMME_CODE");
    const version = refs.versions.find((row: Row) => row.programme_id === programme?.id && upper(row.version_code) === versionCode);
    if (!version) errors.push("UNKNOWN_PROGRAMME_VERSION");
    const cohort = refs.cohorts.find((row: Row) => Number(row.entry_year) === cohortYear);
    if (!cohort) errors.push("COHORT_NOT_CONFIGURED");
    const academicYear = refs.years.find((row: Row) => key(row.year_code) === academicYearCode);
    if (!academicYear) errors.push("UNKNOWN_ACADEMIC_YEAR");
    if (!allowedStatuses.has(status)) errors.push("INVALID_STUDENT_STATUS");
    let validationStatus = "VALID";
    if (studentNumber && (existing.has(studentNumber) || seen.has(studentNumber))) { errors.push("DUPLICATE_STUDENT_NUMBER"); validationStatus = "DUPLICATE"; }
    if (registrationNumber && (existingRegistrations.has(registrationNumber) || seenRegistrations.has(registrationNumber))) { errors.push("DUPLICATE_REGISTRATION_NUMBER"); validationStatus = "DUPLICATE"; }
    if (studentNumber) seen.add(studentNumber);
    if (registrationNumber) seenRegistrations.add(registrationNumber);
    if (errors.length && validationStatus !== "DUPLICATE") validationStatus = "INVALID";
    const curriculum = refs.curricula.find((row: Row) => row.programme_version_id === version?.id && row.status === "ACTIVE") ?? refs.curricula.find((row: Row) => row.programme_version_id === version?.id);
    return {
      rowNumber: index + 2,
      raw,
      validationStatus,
      errors,
      normalized: {
        student_number: studentNumber, first_name: firstName, middle_name: middleName || null, last_name: lastName,
        registration_number: registrationNumber, source_index_number: sourceIndexNumber || null, source_exam_year: sourceExamYear,
        gender: upper(field(raw, "gender")) || null, date_of_birth: field(raw, "dateofbirth", "dob") || null,
        phone: field(raw, "phone", "phonenumber") || null, email: field(raw, "email") || null,
        admission_year: cohortYear, student_status: status, institution_id: institution.id,
        cohort_id: cohort?.id ?? null, programme_id: programme?.id ?? null, programme_version_id: version?.id ?? null,
        curriculum_id: curriculum?.id ?? null, entry_academic_year_id: academicYear?.id ?? null,
        programme_code: programmeCode, programme_version_code: versionCode, academic_year_code: academicYearCode,
      },
    };
  });
  return { rows, summary: { total: rows.length, valid: rows.filter((r) => r.validationStatus === "VALID").length, invalid: rows.filter((r) => r.validationStatus === "INVALID").length, duplicates: rows.filter((r) => r.validationStatus === "DUPLICATE").length } };
}

async function createBatch(req: Request, fileName: string, sourceFormat: string, fileBase64: string | null, rows: SpreadsheetRow[]) {
  const db = getSupabase();
  const validation = await validateRows(rows);
  const institutionId = validation.rows[0]!.normalized.institution_id;
  const now = new Date();
  const batchNumber = `HIST-${now.toISOString().replace(/\D/g, "").slice(0, 14)}-${randomUUID().slice(0, 6).toUpperCase()}`;
  const { data: batch, error } = await db.from("historical_import_batches").insert({
    batch_number: batchNumber, institution_id: institutionId, source_format: sourceFormat, source_file_name: fileName || null,
    source_file_sha256: fileBase64 ? createHash("sha256").update(fileBase64).digest("hex") : null,
    cohort_year: validation.rows.every((r) => r.normalized.admission_year === validation.rows[0]!.normalized.admission_year) ? validation.rows[0]!.normalized.admission_year : null,
    status: validation.summary.invalid || validation.summary.duplicates ? "VALIDATED" : "READY",
    total_rows: validation.summary.total, valid_rows: validation.summary.valid, invalid_rows: validation.summary.invalid,
    duplicate_rows: validation.summary.duplicates, uploaded_by: actor(req), validated_at: now.toISOString(),
  }).select("*").single();
  if (error || !batch) throw error ?? new Error("Unable to create import batch.");
  const { error: rowError } = await db.from("historical_import_rows").insert(validation.rows.map((row) => ({
    batch_id: batch.id, row_number: row.rowNumber, raw_data: row.raw, normalized_data: row.normalized,
    validation_status: row.validationStatus, validation_errors: row.errors,
  })));
  if (rowError) throw rowError;
  await createAuditLog({ actorUserId: actor(req), actionCode: "HISTORICAL_IMPORT_VALIDATE", moduleCode: "historical_students", entityType: "historical_import_batch", entityId: batch.id, newValues: { batch_number: batchNumber, ...validation.summary }, requestId: req.requestId, ipAddress: req.ip });
  return { batch, ...validation };
}

async function batchProgress(batchId: string) {
  const db = getSupabase();
  const { data: rows, error } = await db.from("historical_import_rows").select("validation_status").eq("batch_id", batchId);
  if (error) throw error;
  const counts: Record<string, number> = {};
  for (const row of rows ?? []) counts[row.validation_status] = (counts[row.validation_status] ?? 0) + 1;
  const pending = (counts.VALID ?? 0) + (counts.PENDING ?? 0);
  return {
    total: rows?.length ?? 0,
    imported: counts.IMPORTED ?? 0,
    skipped: counts.SKIPPED ?? 0,
    invalid: counts.INVALID ?? 0,
    duplicates: counts.DUPLICATE ?? 0,
    pending,
    processed: (counts.IMPORTED ?? 0) + (counts.SKIPPED ?? 0),
    percent: rows?.length ? Math.round((((counts.IMPORTED ?? 0) + (counts.SKIPPED ?? 0)) / rows.length) * 100) : 0,
  };
}

async function confirmBatch(req: Request, batchId: string) {
  const db = getSupabase();
  const { data: batch, error: batchError } = await db.from("historical_import_batches").select("*").eq("id", batchId).maybeSingle();
  if (batchError) throw batchError;
  if (!batch) throw new Error("Historical import batch was not found.");
  if (batch.status !== "READY" && batch.status !== "IMPORTING") {
    if (["COMPLETED", "COMPLETED_WITH_ERRORS"].includes(batch.status)) return { batch, progress: await batchProgress(batchId), completed: true };
    throw new Error("Fix every invalid or duplicate row and create a clean READY batch before confirming import.");
  }
  const chunkSize = Math.min(50, Math.max(5, Number(req.body?.chunkSize ?? 25)));
  const { data: rows, error: rowError } = await db.from("historical_import_rows").select("*").eq("batch_id", batchId).eq("validation_status", "VALID").order("row_number").limit(chunkSize);
  if (rowError) throw rowError;
  if (batch.status === "READY") {
    const { error: startError } = await db.from("historical_import_batches").update({ status: "IMPORTING", confirmed_by: actor(req), confirmed_at: new Date().toISOString() }).eq("id", batchId);
    if (startError) throw startError;
  }
  const studentSource = batch.source_format === "MANUAL" ? "MANUAL_ENTRY" : "HISTORICAL_IMPORT";
  let imported = 0; let skipped = 0;
  for (const importRow of rows ?? []) {
    const value = importRow.normalized_data as Row;
    let createdStudentId: string | null = null;
    try {
      const { data: existing, error: existingError } = await db.from("students").select("id,source_reference").eq("student_number", value.student_number).maybeSingle();
      if (existingError) throw existingError;
      if (existing) {
        if (existing.source_reference === batch.batch_number) {
          await db.from("historical_import_rows").update({ validation_status: "IMPORTED", student_id: existing.id, imported_at: new Date().toISOString(), validation_errors: [] }).eq("id", importRow.id);
          imported += 1;
        } else {
          skipped += 1;
          await db.from("historical_import_rows").update({ validation_status: "SKIPPED", validation_errors: ["DUPLICATE_FOUND_DURING_CONFIRM"] }).eq("id", importRow.id);
        }
        continue;
      }
      const { data: student, error } = await db.from("students").insert({
        institution_id: value.institution_id, student_number: value.student_number, registration_number: value.registration_number,
        source_index_number: value.source_index_number, source_exam_year: value.source_exam_year, first_name: value.first_name,
        middle_name: value.middle_name, last_name: value.last_name, gender: value.gender, date_of_birth: value.date_of_birth,
        phone: value.phone, email: value.email, admission_year: value.admission_year, entry_type: studentSource,
        student_status: value.student_status, cohort_id: value.cohort_id, programme_id: value.programme_id,
        programme_version_id: value.programme_version_id, curriculum_id: value.curriculum_id,
        entry_academic_year_id: value.entry_academic_year_id, source_type: studentSource, source_reference: batch.batch_number,
      }).select("id").single();
      if (error || !student) throw error ?? new Error("Student insert returned no record.");
      createdStudentId = student.id;
      const { error: programmeHistoryError } = await db.from("student_programme_history").insert({ student_id: student.id, programme_id: value.programme_id, programme_version_id: value.programme_version_id, change_type: "INITIAL", effective_from: `${value.admission_year}-01-01`, reason: `Historical import ${batch.batch_number}`, approved_by: actor(req), approved_at: new Date().toISOString(), import_batch_id: batch.id });
      if (programmeHistoryError) throw programmeHistoryError;
      const { error: statusHistoryError } = await db.from("student_status_history").insert({ student_id: student.id, old_status: null, new_status: value.student_status, reason: `Historical import ${batch.batch_number}`, changed_by: actor(req), import_batch_id: batch.id });
      if (statusHistoryError) throw statusHistoryError;
      const { error: importRowError } = await db.from("historical_import_rows").update({ validation_status: "IMPORTED", student_id: student.id, imported_at: new Date().toISOString() }).eq("id", importRow.id);
      if (importRowError) throw importRowError;
      imported += 1;
    } catch (error) {
      skipped += 1;
      if (createdStudentId) {
        await db.from("students").update({
          student_status: "INACTIVE",
          archived_at: new Date().toISOString(),
          archived_by: actor(req),
          notes: `Incomplete import ${batch.batch_number}; reconciliation required.`,
        }).eq("id", createdStudentId);
      }
      await db.from("historical_import_rows").update({ validation_status: "SKIPPED", validation_errors: [error instanceof Error ? error.message : "IMPORT_FAILED"] }).eq("id", importRow.id);
    }
  }
  const progress = await batchProgress(batchId);
  const isComplete = progress.pending === 0;
  const finalStatus = isComplete ? (progress.skipped ? "COMPLETED_WITH_ERRORS" : "COMPLETED") : "IMPORTING";
  const { data: completed, error: updateError } = await db.from("historical_import_batches").update({ status: finalStatus, imported_rows: progress.imported, skipped_rows: progress.skipped, completed_at: isComplete ? new Date().toISOString() : null }).eq("id", batchId).select("*").single();
  if (updateError) throw updateError;
  if (isComplete) await createAuditLog({ actorUserId: actor(req), actionCode: "HISTORICAL_IMPORT_CONFIRM", moduleCode: "historical_students", entityType: "historical_import_batch", entityId: batchId, oldValues: batch, newValues: completed, requestId: req.requestId, ipAddress: req.ip });
  return { batch: completed, progress, completed: isComplete, processedThisRequest: imported + skipped };
}

router.get("/reference-data", requirePermission("historical_students.view"), async (_req, res, next) => { try { const data = await references(); res.json({ success: true, data: { cohorts: data.cohorts, programmes: data.programmes, programmeVersions: data.versions, curricula: data.curricula, academicYears: data.years, semesters: data.semesters } }); } catch (e) { next(e); } });
router.get("/template", requirePermission("historical_students.view"), (_req, res) => res.json({ success: true, data: { columns: ["studentNumber","officialRegistrationNumber","formFourIndex","formFourYear","firstName","middleName","lastName","gender","dateOfBirth","phone","email","cohortYear","programmeCode","programmeVersionCode","academicYear","studentStatus"] } }));
router.post("/validate", requirePermission("historical_students.validate"), async (req, res, next) => { try { const rows = req.body?.fileBase64 ? parseSpreadsheet(req.body.fileName, req.body.fileBase64) : req.body?.rows; res.json({ success: true, data: await validateRows(rows) }); } catch (e) { next(e); } });
router.post("/imports", requirePermission("historical_students.validate"), async (req, res, next) => { try { const fileName = key(req.body?.fileName) || "manual-entry"; const source = req.body?.fileBase64 ? parseSpreadsheet(fileName, req.body.fileBase64) : req.body?.rows; const format = fileName.toLowerCase().endsWith(".xlsx") ? "XLSX" : req.body?.fileBase64 ? "CSV" : "MANUAL"; res.status(201).json({ success: true, data: await createBatch(req, fileName, format, req.body?.fileBase64 ?? null, source) }); } catch (e) { next(e); } });
router.get("/imports", requirePermission("historical_students.view"), async (req, res, next) => { try { const page = Math.max(1, Number(req.query.page ?? 1)); const limit = Math.min(100, Math.max(1, Number(req.query.limit ?? 25))); const from=(page-1)*limit; const { data,error,count }=await getSupabase().from("historical_import_batches").select("*",{count:"exact"}).order("created_at",{ascending:false}).range(from,from+limit-1); if(error) throw error; res.json({success:true,data:{rows:data??[],page,limit,total:count??0}}); } catch(e){next(e);} });
router.get("/imports/:id", requirePermission("historical_students.view"), async (req,res,next)=>{try{const db=getSupabase();const [batch,rows]=await Promise.all([db.from("historical_import_batches").select("*").eq("id",req.params.id).maybeSingle(),db.from("historical_import_rows").select("*").eq("batch_id",req.params.id).order("row_number")]);if(batch.error)throw batch.error;if(rows.error)throw rows.error;if(!batch.data)throw new Error("Import batch was not found.");res.json({success:true,data:{batch:batch.data,rows:rows.data??[]}});}catch(e){next(e);}});
router.get("/imports/:id/progress", requirePermission("historical_students.view"), async (req,res,next)=>{try{const db=getSupabase();const {data:batch,error}=await db.from("historical_import_batches").select("*").eq("id",req.params.id).maybeSingle();if(error)throw error;if(!batch)throw new Error("Import batch was not found.");res.json({success:true,data:{batch,progress:await batchProgress(String(req.params.id)),completed:["COMPLETED","COMPLETED_WITH_ERRORS"].includes(batch.status)}});}catch(e){next(e);}});
router.post("/imports/:id/confirm", requirePermission("historical_students.import"), async (req,res,next)=>{try{res.json({success:true,data:await confirmBatch(req,String(req.params.id))});}catch(e){next(e);}});
router.post("/imports/:id/rollback", requirePermission("historical_students.rollback"), async (req,res,next)=>{try{const db=getSupabase();const {data:batch,error}=await db.from("historical_import_batches").select("*").eq("id",req.params.id).maybeSingle();if(error)throw error;if(!batch||!['COMPLETED','COMPLETED_WITH_ERRORS'].includes(batch.status))throw new Error("Only a completed import can be rolled back.");const {data:rows,error:rowsError}=await db.from("historical_import_rows").select("id,student_id").eq("batch_id",batch.id).eq("validation_status","IMPORTED");if(rowsError)throw rowsError;const ids=(rows??[]).map((r:Row)=>r.student_id).filter(Boolean);if(ids.length){const {error:updateError}=await db.from("students").update({student_status:"INACTIVE",archived_at:new Date().toISOString(),archived_by:actor(req),notes:`Historical batch ${batch.batch_number} rolled back: ${key(req.body?.reason)||'No reason supplied'}`}).in("id",ids).eq("source_reference",batch.batch_number);if(updateError)throw updateError;await db.from("historical_import_rows").update({validation_status:"ROLLED_BACK"}).eq("batch_id",batch.id).eq("validation_status","IMPORTED");}const {data:updated,error:updateBatchError}=await db.from("historical_import_batches").update({status:"ROLLED_BACK",rolled_back_by:actor(req),rolled_back_at:new Date().toISOString(),rollback_reason:key(req.body?.reason)||null}).eq("id",batch.id).select("*").single();if(updateBatchError)throw updateBatchError;await createAuditLog({actorUserId:actor(req),actionCode:"HISTORICAL_IMPORT_ROLLBACK",moduleCode:"historical_students",entityType:"historical_import_batch",entityId:batch.id,oldValues:batch,newValues:updated,requestId:req.requestId,ipAddress:req.ip});res.json({success:true,data:updated});}catch(e){next(e);}});
router.get("/quality", requirePermission("historical_students.view"), async (req,res,next)=>{try{const {data,error}=await getSupabase().from("historical_student_quality_v").select("*").order("cohort_year").order("student_number");if(error)throw error;const rows=data??[];const summary={total:rows.length,complete:rows.filter((r:Row)=>r.has_programme&&r.has_programme_version&&r.has_curriculum&&r.has_academic_year&&r.has_academic_records).length,missingProgramme:rows.filter((r:Row)=>!r.has_programme).length,missingVersion:rows.filter((r:Row)=>!r.has_programme_version).length,missingCurriculum:rows.filter((r:Row)=>!r.has_curriculum).length,missingAcademicYear:rows.filter((r:Row)=>!r.has_academic_year).length,missingAcademicRecords:rows.filter((r:Row)=>!r.has_academic_records).length,missingGraduation:rows.filter((r:Row)=>!r.has_graduation_record).length,missingAlumni:rows.filter((r:Row)=>!r.has_alumni_record).length};res.json({success:true,data:{summary,rows}});}catch(e){next(e);}});

export default router;
