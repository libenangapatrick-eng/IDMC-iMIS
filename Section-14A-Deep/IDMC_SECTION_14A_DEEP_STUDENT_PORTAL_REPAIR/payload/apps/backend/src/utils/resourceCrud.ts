import type { NextFunction, Request, Response } from "express";
import { getSupabase } from "../config/database.js";
import { createAuditLog } from "../services/audit.service.js";
import { requirePermission } from "../middleware/rbac.js";

type FieldMap = Record<string, string>;

type CrudConfig = {
  moduleCode: string;
  entityType: string;
  table: string;
  permissionView: string;
  permissionManage: string;
  searchFields?: string[];
  filterFields?: string[];
  fields: FieldMap;
  defaultOrderField?: string;
};

function valueOrUndefined(value: unknown): unknown {
  return value === "" ? null : value;
}

function mapBody(body: unknown, fields: FieldMap): Record<string, unknown> {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new Error("Request body must be a JSON object");
  }

  const source = body as Record<string, unknown>;
  const result: Record<string, unknown> = {};

  for (const [apiField, dbField] of Object.entries(fields)) {
    if (Object.prototype.hasOwnProperty.call(source, apiField)) {
      result[dbField] = valueOrUndefined(source[apiField]);
      continue;
    }

    if (Object.prototype.hasOwnProperty.call(source, dbField)) {
      result[dbField] = valueOrUndefined(source[dbField]);
    }
  }

  return result;
}

function requireId(req: Request): string {
  const id = String(req.params.id ?? "").trim();
  if (!id) {
    const error = new Error("id is required") as Error & { statusCode?: number };
    error.statusCode = 400;
    throw error;
  }
  return id;
}

function actor(req: Request): string | null {
  return req.user?.id ?? null;
}

/**
 * True only when the fetched row actually has a locked_at column
 * (checked at runtime, not from a hardcoded table list) and that
 * column is set. Tables without a locked_at column -- and tables
 * whose locked_at means something else, like a background-worker
 * claim lock -- are unaffected because the column either is not
 * present or (for those) this function is never reached from a
 * generic CRUD route in the first place.
 */
function isRecordLocked(row: Record<string, unknown>): boolean {
  return (
    Object.prototype.hasOwnProperty.call(row, "locked_at") &&
    Boolean(row.locked_at)
  );
}

async function audit(req: Request, config: CrudConfig, actionCode: string, entityId: string | null, oldValues: unknown, newValues: unknown) {
  try {
    await createAuditLog({
      actorUserId: actor(req),
      actionCode,
      moduleCode: config.moduleCode,
      entityType: config.entityType,
      entityId,
      oldValues,
      newValues,
      ipAddress: req.ip ?? null,
      requestId: typeof req.headers["x-request-id"] === "string" ? req.headers["x-request-id"] : null,
    });
  } catch (error) {
    console.warn("Audit logging failed", error);
  }
}

export function createCrudHandlers(config: CrudConfig) {
  const list = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const pageRaw = Number(req.query.page ?? 1);
      const limitRaw = Number(req.query.limit ?? 25);
      const page = Number.isInteger(pageRaw) && pageRaw > 0 ? pageRaw : 1;
      const limit = Number.isInteger(limitRaw) && limitRaw > 0 && limitRaw <= 100 ? limitRaw : 25;
      const from = (page - 1) * limit;
      const to = from + limit - 1;

      let query = getSupabase()
        .from(config.table)
        .select("*", { count: "exact" })
        .range(from, to);

      const search = String(req.query.search ?? "").trim();
      if (search && config.searchFields?.length) {
        query = query.or(
          config.searchFields
            .map((field) => `${field}.ilike.%${search.replace(/%/g, "\\%")}%`)
            .join(",")
        );
      }

      for (const field of config.filterFields ?? []) {
        const value = req.query[field];
        if (typeof value === "string" && value.trim()) {
          query = query.eq(field, value.trim());
        }
      }

      const orderField = config.defaultOrderField ?? "created_at";
      query = query.order(orderField, { ascending: false });

      const { data, error, count } = await query;
      if (error) throw error;

      return res.status(200).json({
        success: true,
        data: data ?? [],
        meta: { page, limit, total: count ?? 0 },
      });
    } catch (error) {
      next(error);
    }
  };

  const getById = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const id = requireId(req);
      const { data, error } = await getSupabase()
        .from(config.table)
        .select("*")
        .eq("id", id)
        .maybeSingle();

      if (error) throw error;
      if (!data) {
        return res.status(404).json({ success: false, message: `${config.entityType} not found` });
      }

      return res.status(200).json({ success: true, data });
    } catch (error) {
      next(error);
    }
  };

  const create = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const payload = mapBody(req.body, config.fields);

      /*
       * Applicants require applicant_number in the database.
       * Applicant numbers are system-generated and must not be
       * manually entered by the applicant.
       */
      if (
        config.table === "applicants" &&
        !payload.applicant_number
      ) {
        const now = new Date();

        const year = String(now.getUTCFullYear());

        const randomPart =
          Math.random()
            .toString(36)
            .slice(2, 8)
            .toUpperCase();

        const timePart =
          String(Date.now()).slice(-8);

        payload.applicant_number =
          `APP-${year}-${timePart}-${randomPart}`;
      }

      /*
       * Link applicant profile to the authenticated user
       * whenever auth_user_id was not explicitly supplied.
       */
      if (
        config.table === "applicants" &&
        !payload.auth_user_id &&
        req.user?.authUserId
      ) {
        payload.auth_user_id = req.user.authUserId;
      }

      if (
        config.table === "applications" &&
        !payload.application_number
      ) {
        const year = String(new Date().getUTCFullYear());
        const timePart = String(Date.now()).slice(-8);
        const randomPart = Math.random().toString(36).slice(2, 8).toUpperCase();
        payload.application_number = `APL-${year}-${timePart}-${randomPart}`;
      }

      if (!Object.keys(payload).length) {
        const error = new Error("No allowed fields supplied") as Error & { statusCode?: number };
        error.statusCode = 400;
        throw error;
      }

      const { data, error } = await getSupabase()
        .from(config.table)
        .insert(payload)
        .select("*")
        .single();

      if (error) throw error;

      await audit(req, config, `${config.entityType.toUpperCase()}_CREATE`, data.id ?? null, null, data);
      return res.status(201).json({ success: true, data });
    } catch (error) {
      next(error);
    }
  };

  const update = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const id = requireId(req);
      const payload = mapBody(req.body, config.fields);

      /*
       * Link applicant profile to the authenticated user
       * whenever auth_user_id was not explicitly supplied.
       */
      if (
        config.table === "applicants" &&
        !payload.auth_user_id &&
        req.user?.authUserId
      ) {
        payload.auth_user_id = req.user.authUserId;
      }

      if (!Object.keys(payload).length) {
        const error = new Error("No allowed fields supplied") as Error & { statusCode?: number };
        error.statusCode = 400;
        throw error;
      }

      const supabase = getSupabase();
      const currentResult = await supabase
        .from(config.table)
        .select("*")
        .eq("id", id)
        .maybeSingle();

      if (currentResult.error) throw currentResult.error;
      if (!currentResult.data) {
        return res.status(404).json({ success: false, message: `${config.entityType} not found` });
      }

      if (isRecordLocked(currentResult.data)) {
        return res.status(423).json({
          success: false,
          message: `${config.entityType} is locked and can no longer be modified.`,
        });
      }

      const { data, error } = await supabase
        .from(config.table)
        .update(payload)
        .eq("id", id)
        .select("*")
        .single();

      if (error) throw error;

      await audit(req, config, `${config.entityType.toUpperCase()}_UPDATE`, id, currentResult.data, data);
      return res.status(200).json({ success: true, data });
    } catch (error) {
      next(error);
    }
  };

  const remove = async (req: Request, res: Response, next: NextFunction) => {
    try {
      const id = requireId(req);
      const supabase = getSupabase();

      const currentResult = await supabase
        .from(config.table)
        .select("*")
        .eq("id", id)
        .maybeSingle();

      if (currentResult.error) throw currentResult.error;
      if (!currentResult.data) {
        return res.status(404).json({ success: false, message: `${config.entityType} not found` });
      }

      if (isRecordLocked(currentResult.data)) {
        return res.status(423).json({
          success: false,
          message: `${config.entityType} is locked and can no longer be deleted.`,
        });
      }

      const { error } = await supabase
        .from(config.table)
        .delete()
        .eq("id", id);

      if (error) throw error;

      await audit(req, config, `${config.entityType.toUpperCase()}_DELETE`, id, currentResult.data, null);
      return res.status(204).send();
    } catch (error) {
      next(error);
    }
  };

  return { list, getById, create, update, remove };
}

export function registerCrudResource(
  router: import("express").Router,
  config: CrudConfig,
  path: string
) {
  const handlers = createCrudHandlers(config);
  router.get(path, requirePermission(config.permissionView), handlers.list);
  router.get(`${path}/:id`, requirePermission(config.permissionView), handlers.getById);
  router.post(path, requirePermission(config.permissionManage), handlers.create);
  router.patch(`${path}/:id`, requirePermission(config.permissionManage), handlers.update);
  router.delete(`${path}/:id`, requirePermission(config.permissionManage), handlers.remove);
}


