import { getSupabase } from "../config/database.js";

export interface AuditEventInput {
  actorUserId?: string | null | undefined;
  actionCode: string;
  moduleCode: string;
  entityType: string;
  entityId?: string | null | undefined;
  oldValues?: unknown;
  newValues?: unknown;
  ipAddress?: string | null | undefined;
  requestId?: string | null | undefined;
}

function cleanAuditValue(value: unknown): unknown {
  if (value === undefined) {
    return null;
  }

  return value;
}

export async function createAuditLog(
  input: AuditEventInput
): Promise<void> {
  const supabase = getSupabase();

  const payload = {
    user_id: input.actorUserId ?? null,
    action_code: input.actionCode,
    module_code: input.moduleCode,
    entity_type: input.entityType,
    entity_id: input.entityId ?? null,
    old_values: cleanAuditValue(input.oldValues),
    new_values: cleanAuditValue(input.newValues),
    ip_address: input.ipAddress ?? null,
    request_id: input.requestId ?? null,
  };

  const { error } = await supabase
    .from("audit_logs")
    .insert(payload);

  if (error) {
    throw new Error(
      `Failed to create audit log: ${error.message}`
    );
  }
}
