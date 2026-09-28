export const ACADEMICS_STATUSES = [
    "ACTIVE",
    "INACTIVE",
    "COMPLETED",
    "SUSPENDED",
    "WITHDRAWN"
] as const;

export const ACADEMICS_PERMISSIONS = {
    VIEW: "academics.view",
    MANAGE: "academics.manage"
} as const;

export const ACADEMICS_BASE_PATH =
    "/api/v1/academics";
