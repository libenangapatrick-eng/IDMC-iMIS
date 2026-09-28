import type { Request, Response } from "express";

export interface PaginationResult<T> {
    data: T[];
    pagination: {
        page: number;
        limit: number;
        total: number;
        totalPages: number;
    };
}

export function parsePagination(
    req: Request
): { page: number; limit: number } {
    const rawPage = Number(req.query.page ?? 1);
    const rawLimit = Number(req.query.limit ?? 25);

    const page = Number.isFinite(rawPage)
        ? Math.max(1, Math.floor(rawPage))
        : 1;

    const limit = Number.isFinite(rawLimit)
        ? Math.min(100, Math.max(1, Math.floor(rawLimit)))
        : 25;

    return {
        page,
        limit
    };
}

export function normalizeString(
    value: unknown
): string | null {
    if (typeof value !== "string") {
        return null;
    }

    const normalized = value.trim();

    return normalized.length > 0
        ? normalized
        : null;
}

export function requireString(
    value: unknown,
    fieldName: string
): string {
    const normalized = normalizeString(value);

    if (!normalized) {
        throw new Error(`${fieldName} is required.`);
    }

    return normalized;
}

export function normalizeNullableString(
    value: unknown
): string | null {
    if (value === undefined || value === null) {
        return null;
    }

    return normalizeString(value);
}

export function isValidUuid(
    value: unknown
): value is string {
    return (
        typeof value === "string" &&
        /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
            value
        )
    );
}

export function sendSuccess(
    res: Response,
    data: unknown,
    statusCode = 200
) {
    return res.status(statusCode).json({
        success: true,
        data
    });
}

export function sendCreated(
    res: Response,
    data: unknown
) {
    return res.status(201).json({
        success: true,
        data
    });
}

export function sendError(
    res: Response,
    statusCode: number,
    message: string,
    details?: unknown
) {
    return res.status(statusCode).json({
        success: false,
        error: {
            message,
            ...(details !== undefined
                ? { details }
                : {})
        }
    });
}

export function mapSupabaseError(
    error: { code?: string; message?: string } | null
) {
    if (!error) {
        return {
            statusCode: 500,
            message: "Database operation failed."
        };
    }

    if (error.code === "23505") {
        return {
            statusCode: 409,
            message: "A record with the same unique value already exists."
        };
    }

    if (error.code === "23503") {
        return {
            statusCode: 409,
            message: "The selected related record does not exist or cannot be used."
        };
    }

    return {
        statusCode: 500,
        message: error.message || "Database operation failed."
    };
}


