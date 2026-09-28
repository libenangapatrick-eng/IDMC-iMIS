import { randomUUID } from "node:crypto";
import express, { Router, type NextFunction, type Request, type Response } from "express";
import { getSupabase } from "../../config/database.js";
import { authenticate } from "../../middleware/auth.js";
import { requirePermission } from "../../middleware/rbac.js";
import { registerCrudResource } from "../../utils/resourceCrud.js";

const router = Router();
router.use(authenticate);

const documentText = (value: unknown, max: number) => { const result = String(value ?? "").trim(); return result ? result.slice(0, max) : null; };
router.post("/documents/upload", requirePermission("documents.manage"), express.raw({ type: "application/octet-stream", limit: "12mb" }), async (req: Request, res: Response, next: NextFunction) => {
  const db = getSupabase();
  let storagePath: string | null = null;
  try {
    const body = req.body as Buffer, institutionId = documentText(req.headers["x-institution-id"], 80), title = documentText(req.headers["x-document-title"], 255), documentType = documentText(req.headers["x-document-type"], 100);
    const originalName = documentText(req.headers["x-file-name"], 255)?.replace(/[^a-zA-Z0-9._-]/g, "_") ?? null;
    const mimeType = documentText(req.headers["x-mime-type"], 120) ?? "application/octet-stream";
    if (!institutionId || !title || !documentType) return res.status(400).json({ success: false, message: "Institution, document title and document type are required." });
    if (!Buffer.isBuffer(body) || !body.length || !originalName) return res.status(400).json({ success: false, message: "Choose a document file to upload." });
    const allowed = new Set(["application/pdf", "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/vnd.ms-excel", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "image/jpeg", "image/png", "image/webp"]);
    if (!allowed.has(mimeType)) return res.status(415).json({ success: false, message: "Allowed files: PDF, Word, Excel, JPG, PNG and WEBP." });
    const institution = await db.from("institutions").select("id").eq("id", institutionId).maybeSingle();
    if (institution.error) throw institution.error;
    if (!institution.data) return res.status(404).json({ success: false, message: "The selected institution does not exist." });
    storagePath = `institutional/${institutionId}/${Date.now()}-${randomUUID().slice(0, 8)}-${originalName}`;
    const upload = await db.storage.from("idmc-private-documents").upload(storagePath, body, { contentType: mimeType, upsert: false });
    if (upload.error) throw upload.error;
    const documentNumber = documentText(req.headers["x-document-number"], 100) ?? `DOC-${new Date().getUTCFullYear()}-${Date.now()}-${randomUUID().slice(0, 5).toUpperCase()}`;
    const saved = await db.from("documents").insert({ institution_id: institutionId, document_number: documentNumber, title, document_type: documentType,
      module_code: documentText(req.headers["x-module-code"], 100), visibility: documentText(req.headers["x-visibility"], 30) ?? "PRIVATE", status: "ACTIVE", current_version: 1,
      file_name: originalName, mime_type: mimeType, file_size_bytes: body.length, storage_path: storagePath, description: documentText(req.headers["x-description"], 2000), owner_user_id: req.user?.id ?? null, created_by: req.user?.id ?? null, updated_by: req.user?.id ?? null }).select("*").single();
    if (saved.error) throw saved.error;
    const version = await db.from("document_versions").insert({ document_id: saved.data.id, version_number: 1, file_name: originalName, mime_type: mimeType, file_size_bytes: body.length, storage_path: storagePath, uploaded_by: req.user?.id ?? null }).select("id").single();
    if (version.error) { await db.from("documents").delete().eq("id", saved.data.id); throw version.error; }
    res.status(201).json({ success: true, data: saved.data });
  } catch (error) { if (storagePath) await db.storage.from("idmc-private-documents").remove([storagePath]); next(error); }
});

registerCrudResource(router, {
  moduleCode: "COMMUNICATIONS", entityType: "announcements", table: "announcements",
  permissionView: "communications.view", permissionManage: "communications.manage",
  searchFields: ["announcement_number","title","summary","body"], filterFields: ["institution_id","status","announcement_type","priority"],
  defaultOrderField: "publish_at",
  fields: {
    institutionId:"institution_id", announcementNumber:"announcement_number", title:"title", summary:"summary",
    body:"body", announcementType:"announcement_type", priority:"priority", status:"status",
    publishAt:"publish_at", expireAt:"expire_at", publishedBy:"published_by", publishedAt:"published_at",
    createdBy:"created_by", updatedBy:"updated_by"
  }
}, "/announcements");

registerCrudResource(router, {
  moduleCode: "COMMUNICATIONS", entityType: "announcement_audiences", table: "announcement_audiences",
  permissionView: "communications.view", permissionManage: "communications.manage",
  searchFields: ["audience_type","audience_label"], filterFields: ["announcement_id","audience_type"],
  defaultOrderField: "created_at",
  fields: {
    announcementId:"announcement_id", audienceType:"audience_type", audienceRefId:"audience_ref_id", audienceLabel:"audience_label"
  }
}, "/announcement-audiences");

registerCrudResource(router, {
  moduleCode: "DOCUMENTS", entityType: "documents", table: "documents",
  permissionView: "documents.view", permissionManage: "documents.manage",
  searchFields: ["document_number","title","document_type","module_code","file_name"],
  filterFields: ["institution_id","module_code","entity_type","entity_id","visibility","status","owner_user_id"],
  defaultOrderField: "created_at",
  fields: {
    institutionId:"institution_id", documentNumber:"document_number", title:"title", documentType:"document_type",
    moduleCode:"module_code", entityType:"entity_type", entityId:"entity_id", visibility:"visibility", status:"status",
    currentVersion:"current_version", fileName:"file_name", mimeType:"mime_type", fileSizeBytes:"file_size_bytes",
    fileUrl:"file_url", storagePath:"storage_path", description:"description", ownerUserId:"owner_user_id",
    createdBy:"created_by", updatedBy:"updated_by"
  }
}, "/documents");

registerCrudResource(router, {
  moduleCode: "DOCUMENTS", entityType: "document_versions", table: "document_versions",
  permissionView: "documents.view", permissionManage: "documents.manage",
  searchFields: ["file_name","mime_type","change_summary"], filterFields: ["document_id","version_number","uploaded_by"],
  defaultOrderField: "uploaded_at",
  fields: {
    documentId:"document_id", versionNumber:"version_number", fileName:"file_name", mimeType:"mime_type",
    fileSizeBytes:"file_size_bytes", fileUrl:"file_url", storagePath:"storage_path",
    changeSummary:"change_summary", uploadedBy:"uploaded_by"
  }
}, "/document-versions");

registerCrudResource(router, {
  moduleCode: "HELPDESK", entityType: "helpdesk_categories", table: "helpdesk_categories",
  permissionView: "helpdesk.view", permissionManage: "helpdesk.manage",
  searchFields: ["category_code","category_name","description"], filterFields: ["institution_id","status","default_priority"],
  defaultOrderField: "created_at",
  fields: {
    institutionId:"institution_id", categoryCode:"category_code", categoryName:"category_name",
    description:"description", defaultPriority:"default_priority", status:"status"
  }
}, "/helpdesk/categories");

registerCrudResource(router, {
  moduleCode: "HELPDESK", entityType: "helpdesk_tickets", table: "helpdesk_tickets",
  permissionView: "helpdesk.view", permissionManage: "helpdesk.manage",
  searchFields: ["ticket_number","subject","description","resolution_summary"],
  filterFields: ["institution_id","category_id","requester_user_id","requester_student_id","assigned_to_user_id","priority","status","source"],
  defaultOrderField: "created_at",
  fields: {
    institutionId:"institution_id", ticketNumber:"ticket_number", categoryId:"category_id",
    requesterUserId:"requester_user_id", requesterStudentId:"requester_student_id", assignedToUserId:"assigned_to_user_id",
    subject:"subject", description:"description", priority:"priority", status:"status", source:"source",
    dueAt:"due_at", firstResponseAt:"first_response_at", resolvedAt:"resolved_at", closedAt:"closed_at",
    resolutionSummary:"resolution_summary"
  }
}, "/helpdesk/tickets");

registerCrudResource(router, {
  moduleCode: "HELPDESK", entityType: "helpdesk_messages", table: "helpdesk_messages",
  permissionView: "helpdesk.view", permissionManage: "helpdesk.manage",
  searchFields: ["body","message_type"], filterFields: ["ticket_id","sender_user_id","sender_student_id","message_type","is_internal"],
  defaultOrderField: "created_at",
  fields: {
    ticketId:"ticket_id", senderUserId:"sender_user_id", senderStudentId:"sender_student_id",
    messageType:"message_type", body:"body", isInternal:"is_internal", attachmentUrl:"attachment_url"
  }
}, "/helpdesk/messages");

export default router;
