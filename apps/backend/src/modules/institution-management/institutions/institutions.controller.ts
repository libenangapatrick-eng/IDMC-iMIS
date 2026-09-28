import type {
    Request,
    Response
} from "express";

import {
    getInstitution,
    getPrimaryInstitutionStructure,
    listInstitutions,
    updateInstitution
} from "./institutions.service.js";

import {
    isValidUuid,
    mapSupabaseError,
    normalizeNullableString,
    normalizeString,
    parsePagination,
    sendError,
    sendSuccess
} from "../shared/http.js";

export async function listInstitutionsController(
    req: Request,
    res: Response
) {
    try {
        const {
            page,
            limit
        } = parsePagination(req);

        const search =
            normalizeString(req.query.search);

        const status =
            normalizeString(req.query.status);

        const result =
            await listInstitutions({
                page,
                limit,
                ...(search ? { search } : {}),
                ...(status && { status })
            });

        return sendSuccess(res, {
            items: result.rows,
            pagination: {
                page,
                limit,
                total: result.total,
                totalPages:
                    Math.ceil(
                        result.total / limit
                    )
            }
        });
    } catch (error) {
        const mapped =
            mapSupabaseError(
                error as {
                    code?: string;
                    message?: string;
                }
            );

        return sendError(
            res,
            mapped.statusCode,
            mapped.message
        );
    }
}

export async function getInstitutionController(
    req: Request,
    res: Response
) {
    const { id } = req.params;

    if (!isValidUuid(id)) {
        return sendError(
            res,
            400,
            "Invalid institution ID."
        );
    }

    try {
        const institution =
            await getInstitution(id);

        if (!institution) {
            return sendError(
                res,
                404,
                "Institution not found."
            );
        }

        return sendSuccess(
            res,
            institution
        );
    } catch (error) {
        const mapped =
            mapSupabaseError(
                error as {
                    code?: string;
                    message?: string;
                }
            );

        return sendError(
            res,
            mapped.statusCode,
            mapped.message
        );
    }
}

export async function getPrimaryInstitutionStructureController(
    _req: Request,
    res: Response
) {
    try {
        const structure = await getPrimaryInstitutionStructure();
        if (!structure) {
            return sendError(res, 404, "The IDMS institution record was not found.");
        }
        return sendSuccess(res, structure);
    } catch (error) {
        const mapped = mapSupabaseError(error as { code?: string; message?: string });
        return sendError(res, mapped.statusCode, mapped.message);
    }
}

export async function createInstitutionController(
    _req: Request,
    res: Response
) {
    return sendError(
        res,
        409,
        "IDMC iMIS is locked to one institution. A second institution cannot be created."
    );
}

export async function updateInstitutionController(
    req: Request,
    res: Response
) {
    const { id } = req.params;

    if (!isValidUuid(id)) {
        return sendError(
            res,
            400,
            "Invalid institution ID."
        );
    }

    const body = req.body ?? {};

    const update: Record<
        string,
        unknown
    > = {};

    const allowedFields = [
        "registration_number",
        "accreditation_number",
        "institution_type",
        "ownership_type",
        "email",
        "phone",
        "website",
        "physical_address",
        "postal_address",
        "city",
        "region",
        "country",
        "logo_url"
    ];

    for (const field of allowedFields) {
        if (
            Object.prototype.hasOwnProperty.call(
                body,
                field
            )
        ) {
            update[field] =
                normalizeNullableString(body[field]);
        }
    }

    if (
        Object.keys(update).length === 0
    ) {
        return sendError(
            res,
            400,
            "No valid fields were supplied for update."
        );
    }

    try {
        const institution =
            await updateInstitution(
                id,
                update
            );

        return sendSuccess(
            res,
            institution
        );
    } catch (error) {
        const mapped =
            mapSupabaseError(
                error as {
                    code?: string;
                    message?: string;
                }
            );

        return sendError(
            res,
            mapped.statusCode,
            mapped.message
        );
    }
}




