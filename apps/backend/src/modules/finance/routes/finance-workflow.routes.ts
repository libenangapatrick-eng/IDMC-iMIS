import { randomUUID } from "node:crypto";
import express, { Router, type Request, type Response } from "express";
import { getSupabase } from "../../../config/database.js";
import { requirePermission } from "../../../middleware/rbac.js";

type Row = Record<string, any>;
const router = Router();

function actor(req: Request): string {
  if (!req.user?.id) throw new Error("Authenticated IDMC identity is unavailable.");
  return req.user.id;
}
function param(req: Request, name: string): string {
  const value = req.params[name];
  if (typeof value !== "string" || !value) throw new Error(`Missing route parameter: ${name}.`);
  return value;
}
function text(value: unknown, max = 2000): string | null {
  const clean = String(value ?? "").trim();
  return clean ? clean.slice(0, max) : null;
}
function amount(value: unknown, label = "Amount"): number {
  const number = Number(value);
  if (!Number.isFinite(number) || number <= 0) throw new Error(`${label} must be greater than zero.`);
  return Math.round(number * 100) / 100;
}
function rows(value: any): Row[] { return Array.isArray(value) ? value : []; }
function code(prefix: string): string {
  return `${prefix}-${new Date().toISOString().slice(0, 10).replaceAll("-", "")}-${randomUUID().slice(0, 8).toUpperCase()}`;
}
function handle(action: (req: Request) => Promise<unknown>) {
  return async (req: Request, res: Response) => {
    try { res.json({ success: true, data: await action(req) }); }
    catch (error) {
      const message = error instanceof Error ? error.message : "Finance workflow failed.";
      res.status(/not found|does not belong/i.test(message) ? 404 : 400).json({ success: false, message });
    }
  };
}
function userName(user: Row | undefined): string {
  if (!user) return "—";
  return user.display_name || [user.first_name, user.middle_name, user.last_name].filter(Boolean).join(" ") || user.user_number || "—";
}
async function userMap(ids: Array<string | null | undefined>): Promise<Map<string, Row>> {
  const unique = [...new Set(ids.filter(Boolean).map(String))];
  if (!unique.length) return new Map();
  const result = await getSupabase().from("users").select("id,user_number,display_name,first_name,middle_name,last_name,email").in("id", unique);
  if (result.error) throw result.error;
  return new Map(rows(result.data).map(item => [String(item.id), item]));
}
async function ownStudent(req: Request): Promise<Row> {
  const result = await getSupabase().from("students").select("*").eq("user_id", actor(req)).maybeSingle();
  if (result.error) throw result.error;
  if (!result.data) throw new Error("Authenticated account is not linked to a student record.");
  return result.data;
}
async function history(entityType: string, entityId: string, action: string, previous: string | null, next: string, by: string, comment?: string | null) {
  const result = await getSupabase().from("finance_workflow_history").insert({ entity_type: entityType, entity_id: entityId, action, previous_status: previous, new_status: next, performed_by: by, comment: comment ?? null });
  if (result.error) throw result.error;
}

async function financeStudents(query = ""): Promise<Row[]> {
  const db = getSupabase();
  let studentQuery: any = db.from("students").select("id,student_number,first_name,middle_name,last_name,email,phone,student_status,programme_id,admission_year").order("student_number").limit(1000);
  const q = query.trim();
  if (q) studentQuery = studentQuery.or(`student_number.ilike.%${q.replace(/[,%()]/g, "")}%,first_name.ilike.%${q.replace(/[,%()]/g, "")}%,last_name.ilike.%${q.replace(/[,%()]/g, "")}%`);
  const students = await studentQuery;
  if (students.error) throw students.error;
  const list = rows(students.data);
  const ids = list.map(item => item.id);
  const programmeIds = [...new Set(list.map(item => item.programme_id).filter(Boolean))];
  const accounts = ids.length ? await db.from("student_financial_accounts").select("*").in("student_id", ids) : { data: [], error: null };
  const programmes = programmeIds.length ? await db.from("programmes").select("id,programme_code,programme_name").in("id", programmeIds) : { data: [], error: null };
  if (accounts.error) throw accounts.error;
  if (programmes.error) throw programmes.error;
  const accountMap = new Map(rows(accounts.data).map(item => [item.student_id, item]));
  const programmeMap = new Map(rows(programmes.data).map(item => [item.id, item]));
  return list.map(item => ({ ...item, full_name: [item.first_name,item.middle_name,item.last_name].filter(Boolean).join(" "), programme: programmeMap.get(item.programme_id) ?? null, account: accountMap.get(item.id) ?? null }));
}

async function studentBundle(studentId: string): Promise<Row> {
  const db = getSupabase();
  const student = await db.from("students").select("*").eq("id", studentId).maybeSingle();
  if (student.error) throw student.error;
  if (!student.data) throw new Error("Student was not found.");
  const [account, charges, invoices, payments, requests, assignments] = await Promise.all([
    db.from("student_financial_accounts").select("*").eq("student_id", studentId).maybeSingle(),
    db.from("student_charges").select("*").eq("student_id", studentId).order("charge_date", { ascending: false }),
    db.from("invoices").select("*").eq("student_id", studentId).order("invoice_date", { ascending: false }),
    db.from("payments").select("*").eq("student_id", studentId).order("payment_date", { ascending: false }),
    db.from("student_payment_requests").select("*").eq("student_id", studentId).order("requested_at", { ascending: false }),
    db.from("student_fee_structure_assignments").select("*").eq("student_id", studentId).order("assigned_at", { ascending: false }),
  ]);
  for (const result of [account, charges, invoices, payments, requests, assignments]) if (result.error) throw result.error;
  const confirms = await userMap(rows(payments.data).map(item => item.confirmed_by));
  return { student: student.data, account: account.data, charges: charges.data ?? [], invoices: invoices.data ?? [], payments: rows(payments.data).map(item => ({ ...item, confirmed_by_name: userName(confirms.get(String(item.confirmed_by))) })), payment_requests: requests.data ?? [], assignments: assignments.data ?? [] };
}

async function assignStructure(studentId: string, feeStructureId: string, semester: string, by: string): Promise<Row> {
  const db = getSupabase();
  const existing = await db.from("student_fee_structure_assignments").select("*").eq("student_id", studentId).eq("fee_structure_id", feeStructureId).eq("semester", semester).maybeSingle();
  if (existing.error) throw existing.error;
  if (existing.data?.assignment_status === "INVOICED") return { assignment: existing.data, reused: true };
  const structure = await db.from("fee_structures").select("*").eq("id", feeStructureId).eq("status", "ACTIVE").maybeSingle();
  if (structure.error || !structure.data) throw new Error("Published fee structure was not found.");
  const itemsResult = await db.from("fee_items").select("*").eq("fee_structure_id", feeStructureId).eq("amount_confirmed", true).order("display_order");
  if (itemsResult.error) throw itemsResult.error;
  const items = rows(itemsResult.data).filter(item => Number(item.semester_amount ?? item.amount) > 0);
  if (!items.length) throw new Error("Fee structure has no confirmed charge items.");
  let assignment = existing.data;
  if (!assignment) {
    const created = await db.from("student_fee_structure_assignments").insert({ student_id: studentId, fee_structure_id: feeStructureId, semester, assignment_status: "PENDING", assigned_by: by }).select().single();
    if (created.error) throw created.error;
    assignment = created.data;
  }
  const total = items.reduce((sum, item) => sum + Number(item.semester_amount ?? item.amount ?? 0), 0);
  const invoiceNumber = code("INV");
  try {
    const invoice = await db.from("invoices").insert({ student_id: studentId, invoice_number: invoiceNumber, invoice_date: new Date().toISOString().slice(0,10), due_date: new Date(Date.now()+30*86400000).toISOString().slice(0,10), academic_year: structure.data.academic_year, semester, subtotal: total, total_amount: total, amount_paid: 0, balance_amount: total, status: "ISSUED", currency_code: structure.data.currency_code || "TZS", issued_by: by, issued_at: new Date().toISOString(), created_by: by, notes: `Automatically generated from ${structure.data.fee_structure_name}` }).select().single();
    if (invoice.error) throw invoice.error;
    const chargeRows = items.map(item => ({ student_id: studentId, fee_structure_id: feeStructureId, fee_item_id: item.id, charge_number: code("CHG"), description: item.fee_item_name, academic_year: structure.data.academic_year, semester, original_amount: Number(item.semester_amount ?? item.amount), status: "POSTED", charge_date: new Date().toISOString().slice(0,10), due_date: new Date(Date.now()+30*86400000).toISOString().slice(0,10), created_by: by, updated_by: by }));
    const charges = await db.from("student_charges").insert(chargeRows).select();
    if (charges.error) throw charges.error;
    const invoiceItems = rows(charges.data).map(charge => ({ invoice_id: invoice.data.id, student_charge_id: charge.id, description: charge.description, quantity: 1, unit_amount: Number(charge.original_amount), discount_amount: 0 }));
    const insertedItems = await db.from("invoice_items").insert(invoiceItems);
    if (insertedItems.error) throw insertedItems.error;
    await db.rpc("refresh_invoice_financials", { p_invoice_id: invoice.data.id });
    await db.rpc("refresh_student_financial_account", { p_student_id: studentId });
    const updated = await db.from("student_fee_structure_assignments").update({ invoice_id: invoice.data.id, assignment_status: "INVOICED", error_message: null, updated_at: new Date().toISOString() }).eq("id", assignment.id).select().single();
    if (updated.error) throw updated.error;
    return { assignment: updated.data, invoice: invoice.data, charges: charges.data, reused: false };
  } catch (error) {
    await db.from("student_fee_structure_assignments").update({ assignment_status: "FAILED", error_message: error instanceof Error ? error.message : "Invoice generation failed", updated_at: new Date().toISOString() }).eq("id", assignment.id);
    throw error;
  }
}

router.get("/catalog", requirePermission("finance.portal.view"), handle(async () => {
  const result = await getSupabase().from("institutional_fee_catalog").select("*").eq("status", "ACTIVE").order("display_order");
  if (result.error) throw result.error;
  return result.data ?? [];
}));

router.get("/students", requirePermission("finance.portal.view"), handle(req => financeStudents(String(req.query.q ?? ""))));
router.get("/students/:studentId", requirePermission("finance.portal.view"), handle(req => studentBundle(param(req,"studentId"))));

router.post("/fee-structures/publish", requirePermission("finance.fees.publish"), handle(async req => {
  const db = getSupabase(); const by = actor(req);
  const academicYear = text(req.body?.academicYear, 20); const semester = text(req.body?.semester, 50) || "SEMESTER 1";
  const structureName = text(req.body?.name, 200); const programmeLevel = text(req.body?.programmeLevel, 50) || "ALL";
  const inputItems = Array.isArray(req.body?.items) ? req.body.items : [];
  if (!academicYear || !structureName) throw new Error("Academic year and fee structure name are required.");
  const selectedItems = inputItems.map((item: Row, index: number) => ({ fee_item_code: text(item.code,100), fee_item_name: text(item.name,200), category: text(item.category,50) || "OTHER", amount: Number(item.semesterAmount || 0), semester_amount: Number(item.semesterAmount || 0), annual_amount: Number(item.annualAmount || Number(item.semesterAmount || 0)*2), amount_confirmed: Boolean(item.confirmed), is_mandatory: item.mandatory !== false, display_order: index+1 })).filter((item: Row) => item.fee_item_code && item.fee_item_name && item.amount_confirmed && item.amount > 0);
  if (!selectedItems.length) throw new Error("Enter and confirm at least one fee item amount before publishing.");
  const structureCode = code(`FEE-${programmeLevel.replace(/[^A-Z0-9]/gi, "").toUpperCase() || "ALL"}`);
  const totalSemester = selectedItems.reduce((sum: number,item: Row) => sum+item.semester_amount,0);
  const totalAnnual = selectedItems.reduce((sum: number,item: Row) => sum+item.annual_amount,0);
  const structure = await db.from("fee_structures").insert({ fee_structure_code: structureCode, fee_structure_name: structureName, academic_year: academicYear, semester, description: `${programmeLevel} | Semester ${totalSemester} | Annual ${totalAnnual}`, status: "ACTIVE", currency_code: "TZS", billing_frequency: "SEMESTER", semesters_per_year: 2, effective_from: new Date().toISOString().slice(0,10), published_by: by, published_at: new Date().toISOString(), created_by: by, updated_by: by }).select().single();
  if (structure.error) throw structure.error;
  const items = await db.from("fee_items").insert(selectedItems.map((item: Row) => ({ ...item, fee_structure_id: structure.data.id }))).select();
  if (items.error) throw items.error;
  let assigned = 0; const failures: Row[] = [];
  if (req.body?.applyToAll === true) {
    const students = await db.from("students").select("id,student_number").eq("student_status", "ACTIVE").limit(5000);
    if (students.error) throw students.error;
    for (const student of rows(students.data)) {
      try { await assignStructure(student.id, structure.data.id, semester, by); assigned += 1; }
      catch (error) { failures.push({ student_number: student.student_number, message: error instanceof Error ? error.message : "Failed" }); }
    }
  }
  return { fee_structure: structure.data, fee_items: items.data, totals: { semester: totalSemester, annual: totalAnnual }, assigned_students: assigned, failures };
}));

router.post("/students/:studentId/generate-invoice", requirePermission("finance.fees.publish"), handle(req => {
  const structureId = text(req.body?.feeStructureId,80); const semester = text(req.body?.semester,50) || "SEMESTER 1";
  if (!structureId) throw new Error("Fee structure is required.");
  return assignStructure(param(req,"studentId"), structureId, semester, actor(req));
}));

async function recordPayment(studentId: string, invoiceId: string, inputAmount: number, method: string, reference: string | null, by: string, controlNumber?: string | null): Promise<Row> {
  const db = getSupabase();
  const invoice = await db.from("invoices").select("*").eq("id", invoiceId).eq("student_id", studentId).maybeSingle();
  if (invoice.error || !invoice.data) throw new Error("Invoice does not belong to the selected student.");
  const balance = Number(invoice.data.balance_amount || 0);
  if (balance <= 0) throw new Error("Invoice is already fully paid.");
  if (inputAmount > balance) throw new Error(`Payment cannot exceed the invoice balance of TZS ${balance.toLocaleString("en-TZ")}.`);
  const payment = await db.from("payments").insert({ student_id: studentId, payment_number: code("PAY"), external_reference: reference, control_number: controlNumber, payment_method: method, provider: method === "CONTROL_NUMBER" ? "IDMC_CONTROL_NUMBER" : "MANUAL_FINANCE", amount: inputAmount, currency_code: "TZS", payment_date: new Date().toISOString(), status: "CONFIRMED", confirmed_by: by, confirmed_at: new Date().toISOString(), created_by: by, updated_by: by }).select().single();
  if (payment.error) throw payment.error;
  const allocation = await db.from("payment_allocations").insert({ payment_id: payment.data.id, invoice_id: invoiceId, allocated_amount: inputAmount, allocation_reference: code("ALLOC"), status: "ACTIVE", created_by: by }).select().single();
  if (allocation.error) throw allocation.error;
  const invoiceRefresh = await db.rpc("refresh_invoice_financials", { p_invoice_id: invoiceId }); if (invoiceRefresh.error) throw invoiceRefresh.error;
  const accountRefresh = await db.rpc("refresh_student_financial_account", { p_student_id: studentId }); if (accountRefresh.error) throw accountRefresh.error;
  return { payment: payment.data, allocation: allocation.data };
}

router.post("/students/:studentId/payments", requirePermission("finance.payments.confirm"), handle(async req => {
  const invoiceId = text(req.body?.invoiceId,80); if (!invoiceId) throw new Error("Invoice is required.");
  return recordPayment(param(req,"studentId"), invoiceId, amount(req.body?.amount), String(req.body?.paymentMethod || "BANK").toUpperCase(), text(req.body?.reference,150), actor(req), text(req.body?.controlNumber,100));
}));

router.get("/payment-requests", requirePermission("finance.portal.view"), handle(async () => {
  const db = getSupabase();
  const result = await db.from("student_payment_requests").select("*").order("requested_at", { ascending: false }).limit(1000);
  if (result.error) throw result.error;
  const requests = rows(result.data); const studentIds = [...new Set(requests.map(item => item.student_id))];
  const students = studentIds.length ? await db.from("students").select("id,student_number,first_name,middle_name,last_name").in("id", studentIds) : { data: [], error: null };
  if (students.error) throw students.error;
  const map = new Map(rows(students.data).map(item => [item.id,item]));
  return requests.map(item => ({ ...item, student: map.get(item.student_id) ?? null }));
}));

router.post("/payment-requests/:id/control-number", requirePermission("finance.payments.confirm"), handle(async req => {
  const db = getSupabase(); const by = actor(req); const id=param(req,"id");
  const current = await db.from("student_payment_requests").select("*").eq("id",id).maybeSingle();
  if (current.error || !current.data) throw new Error("Payment request was not found.");
  if (!["PENDING_PROVIDER","FAILED"].includes(current.data.request_status)) throw new Error("Control number can only be issued for a pending request.");
  const controlNumber = text(req.body?.controlNumber,100) || `IDMC${Date.now()}${Math.floor(Math.random()*900+100)}`;
  const updated = await db.from("student_payment_requests").update({ control_number: controlNumber, provider_reference: code("CN"), request_status: "ISSUED", provider_message: "Control number issued by the Finance Office.", issued_at: new Date().toISOString(), reviewed_by: by, reviewed_at: new Date().toISOString(), finance_notes: text(req.body?.notes,2000), updated_at: new Date().toISOString() }).eq("id",id).select().single();
  if (updated.error) throw updated.error;
  await history("PAYMENT_REQUEST",id,"ISSUE_CONTROL_NUMBER",current.data.request_status,"ISSUED",by,text(req.body?.notes,2000));
  return updated.data;
}));

router.post("/student/payment-requests/:id/receipt", requirePermission("students.payments.upload_receipt"), express.raw({ type: "application/octet-stream", limit: "6mb" }), handle(async req => {
  const db = getSupabase(); const student = await ownStudent(req); const body = req.body as Buffer; const id=param(req,"id");
  const request = await db.from("student_payment_requests").select("*").eq("id",id).eq("student_id",student.id).maybeSingle();
  if (request.error || !request.data) throw new Error("Payment request does not belong to the authenticated student.");
  if (!["ISSUED","REJECTED"].includes(request.data.request_status)) throw new Error("Receipt can only be uploaded for an issued or rejected payment request.");
  const fileName = text(req.headers["x-file-name"],255)?.replace(/[^a-zA-Z0-9._-]/g,"_");
  const mime = text(req.headers["x-mime-type"],100) || "application/octet-stream";
  if (!Buffer.isBuffer(body) || !body.length || !fileName) throw new Error("Receipt file is required.");
  if (!["application/pdf","image/jpeg","image/png","image/webp"].includes(mime)) throw new Error("Only PDF, JPG, PNG and WEBP receipts are accepted.");
  const path = `finance/receipts/${student.id}/${Date.now()}-${randomUUID().slice(0,8)}-${fileName}`;
  const upload = await db.storage.from("idmc-private-documents").upload(path,body,{contentType:mime,upsert:false}); if (upload.error) throw upload.error;
  const updated = await db.from("student_payment_requests").update({ receipt_file_path:path, receipt_file_name:fileName, receipt_mime_type:mime, receipt_uploaded_at:new Date().toISOString(), receipt_uploaded_by:actor(req), request_status:"RECEIPT_UPLOADED", provider_message:"Receipt uploaded; awaiting Finance confirmation.", updated_at:new Date().toISOString() }).eq("id",id).select().single();
  if (updated.error) { await db.storage.from("idmc-private-documents").remove([path]); throw updated.error; }
  await history("PAYMENT_REQUEST",id,"UPLOAD_RECEIPT",request.data.request_status,"RECEIPT_UPLOADED",actor(req),null);
  return updated.data;
}));

router.get("/payment-requests/:id/receipt", requirePermission("finance.portal.view"), handle(async req => {
  const request = await getSupabase().from("student_payment_requests").select("receipt_file_path,receipt_file_name").eq("id",param(req,"id")).maybeSingle();
  if (request.error || !request.data?.receipt_file_path) throw new Error("Receipt was not found.");
  const signed = await getSupabase().storage.from("idmc-private-documents").createSignedUrl(request.data.receipt_file_path,300);
  if (signed.error) throw signed.error;
  return { url:signed.data.signedUrl,file_name:request.data.receipt_file_name,expires_in:300 };
}));

router.post("/payment-requests/:id/confirm", requirePermission("finance.payments.confirm"), handle(async req => {
  const db = getSupabase(); const by=actor(req); const id=param(req,"id");
  const request = await db.from("student_payment_requests").select("*").eq("id",id).maybeSingle();
  if (request.error || !request.data) throw new Error("Payment request was not found.");
  if (request.data.request_status !== "RECEIPT_UPLOADED") throw new Error("Student must upload a receipt before Finance confirmation.");
  if (!request.data.invoice_id) throw new Error("Payment request has no invoice.");
  const recorded = await recordPayment(request.data.student_id,request.data.invoice_id,Number(request.data.amount),"CONTROL_NUMBER",text(req.body?.reference,150) || request.data.provider_reference,by,request.data.control_number);
  const updated = await db.from("student_payment_requests").update({ request_status:"CONFIRMED", payment_id:recorded.payment.id, reviewed_by:by, reviewed_at:new Date().toISOString(), finance_notes:text(req.body?.notes,2000), paid_at:new Date().toISOString(), provider_message:"Payment confirmed by the Finance Office.", updated_at:new Date().toISOString() }).eq("id",id).select().single();
  if (updated.error) throw updated.error;
  await history("PAYMENT_REQUEST",id,"CONFIRM_PAYMENT",request.data.request_status,"CONFIRMED",by,text(req.body?.notes,2000));
  return { request:updated.data,...recorded };
}));

router.get("/student/dashboard", requirePermission("students.self.view"), handle(async req => {
  const student = await ownStudent(req); const bundle = await studentBundle(student.id);
  const structures = await getSupabase().from("fee_structures").select("*,fee_items(*)").eq("status","ACTIVE").order("published_at",{ascending:false});
  if (structures.error) throw structures.error;
  return {...bundle,fee_structures:structures.data??[]};
}));

router.get("/expenses", requirePermission("finance.portal.view"), handle(async () => {
  const db=getSupabase(); const result=await db.from("finance_expense_requests").select("*,finance_expense_participants(*)").order("created_at",{ascending:false}); if(result.error) throw result.error;
  const items=rows(result.data); const map=await userMap(items.flatMap(item=>[item.requested_by,item.finance_reviewed_by,item.approved_by,item.paid_by]));
  return items.map(item=>({...item,requested_by_name:userName(map.get(String(item.requested_by))),finance_reviewed_by_name:userName(map.get(String(item.finance_reviewed_by))),approved_by_name:userName(map.get(String(item.approved_by))),paid_by_name:userName(map.get(String(item.paid_by)))}));
}));

router.get("/staff/expenses", requirePermission("staff.finance.request_own"), handle(async req => {
  const result=await getSupabase().from("finance_expense_requests").select("*,finance_expense_participants(*)").eq("requested_by",actor(req)).order("created_at",{ascending:false});
  if(result.error)throw result.error;
  return result.data??[];
}));

router.post("/staff/expenses", requirePermission("staff.finance.request_own"), handle(async req => {
  const db=getSupabase(); const by=actor(req); const type=String(req.body?.expenseType||"").toUpperCase();
  if(!["PURCHASE","MEETING_ALLOWANCE","TRAVEL","OPERATIONS","OTHER"].includes(type)) throw new Error("Select a valid expense type.");
  const title=text(req.body?.title,200); const description=text(req.body?.description,4000); if(!title||!description) throw new Error("Title and description are required.");
  const created=await db.from("finance_expense_requests").insert({request_number:code("EXP"),requested_by:by,expense_type:type,title,description,amount:amount(req.body?.amount),meeting_date:text(req.body?.meetingDate,10),status:"SUBMITTED"}).select().single(); if(created.error) throw created.error;
  const participants=Array.isArray(req.body?.participants)?req.body.participants:[];
  if(type==="MEETING_ALLOWANCE"&&participants.length){const insert=await db.from("finance_expense_participants").insert(participants.map((item:Row)=>({expense_request_id:created.data.id,staff_id:text(item.staffId,80),participant_name:text(item.name,200)||"Staff",allowance_amount:Number(item.amount||0)})));if(insert.error)throw insert.error;}
  await history("EXPENSE_REQUEST",created.data.id,"SUBMIT",null,"SUBMITTED",by,null); return created.data;
}));

router.patch("/expenses/:id/review", requirePermission("finance.expenses.review"), handle(async req => {
  const db=getSupabase(); const by=actor(req); const id=param(req,"id"); const current=await db.from("finance_expense_requests").select("*").eq("id",id).maybeSingle(); if(current.error||!current.data)throw new Error("Expense request was not found."); if(current.data.status!=="SUBMITTED")throw new Error("Only submitted requests can receive Finance review.");
  const next=req.body?.approve===false?"REJECTED":"FINANCE_REVIEWED"; const updated=await db.from("finance_expense_requests").update({status:next,finance_reviewed_by:by,finance_reviewed_at:new Date().toISOString(),finance_comment:text(req.body?.comment,2000),updated_at:new Date().toISOString()}).eq("id",id).select().single();if(updated.error)throw updated.error;await history("EXPENSE_REQUEST",id,"FINANCE_REVIEW",current.data.status,next,by,text(req.body?.comment,2000));return updated.data;
}));

router.patch("/expenses/:id/approve", requirePermission("finance.expenses.approve"), handle(async req => {
  const db=getSupabase();const by=actor(req);const id=param(req,"id");const current=await db.from("finance_expense_requests").select("*").eq("id",id).maybeSingle();if(current.error||!current.data)throw new Error("Expense request was not found.");if(current.data.status!=="FINANCE_REVIEWED")throw new Error("Principal approval requires Finance review first.");const next=req.body?.approve===false?"REJECTED":"PRINCIPAL_APPROVED";const updated=await db.from("finance_expense_requests").update({status:next,approved_by:by,approved_at:new Date().toISOString(),approval_comment:text(req.body?.comment,2000),updated_at:new Date().toISOString()}).eq("id",id).select().single();if(updated.error)throw updated.error;if(next==="PRINCIPAL_APPROVED"){const participants=await db.from("finance_expense_participants").update({payment_status:"APPROVED"}).eq("expense_request_id",id).eq("payment_status","PENDING");if(participants.error)throw participants.error;}await history("EXPENSE_REQUEST",id,"PRINCIPAL_APPROVAL",current.data.status,next,by,text(req.body?.comment,2000));return updated.data;
}));

router.patch("/expenses/:id/pay", requirePermission("finance.expenses.pay"), handle(async req => {
  const db=getSupabase();const by=actor(req);const id=param(req,"id");const current=await db.from("finance_expense_requests").select("*").eq("id",id).maybeSingle();if(current.error||!current.data)throw new Error("Expense request was not found.");if(current.data.status!=="PRINCIPAL_APPROVED")throw new Error("Only Principal-approved expenses can be paid.");const reference=text(req.body?.reference,150);if(!reference)throw new Error("Payment reference is required.");const updated=await db.from("finance_expense_requests").update({status:"PAID",paid_by:by,paid_at:new Date().toISOString(),payment_reference:reference,updated_at:new Date().toISOString()}).eq("id",id).select().single();if(updated.error)throw updated.error;await db.from("finance_expense_participants").update({payment_status:"PAID",payment_reference:reference,paid_at:new Date().toISOString()}).eq("expense_request_id",id).eq("payment_status","APPROVED");await history("EXPENSE_REQUEST",id,"PAY",current.data.status,"PAID",by,reference);return updated.data;
}));

export default router;
