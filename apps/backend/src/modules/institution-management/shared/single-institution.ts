import type { NextFunction, Request, Response } from "express";

import { institutionDb } from "./institution-db.js";

export const PRIMARY_INSTITUTION_CODE = "IDMS";
export const PRIMARY_INSTITUTION_NAME =
    "Institute of Development and Medical Sciences";

export async function getPrimaryInstitution() {
    const { data, error } = await institutionDb
        .from("institutions")
        .select("*")
        .eq("institution_code", PRIMARY_INSTITUTION_CODE)
        .maybeSingle();

    if (error) throw error;
    if (!data) {
        throw new Error(
            "The primary IDMS institution record is missing. Run the Section 20D database reconciliation."
        );
    }

    return data;
}

export async function bindPrimaryInstitution(
    req: Request,
    res: Response,
    next: NextFunction
) {
    if (!["POST", "PUT", "PATCH"].includes(req.method)) {
        next();
        return;
    }

    try {
        const institution = await getPrimaryInstitution();
        req.body = {
            ...(req.body ?? {}),
            institution_id: institution.id
        };
        next();
    } catch (error) {
        res.status(503).json({
            success: false,
            message:
                error instanceof Error
                    ? error.message
                    : "The primary institution could not be resolved."
        });
    }
}
