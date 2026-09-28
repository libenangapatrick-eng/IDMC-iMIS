import type {
    Request,
    Response
} from "express";

import {
    createInstitution,
    getInstitution,
    listInstitutions,
    updateInstitution
} from "./institutions.service.js";

import {
    isValidUuid,
    mapSupabaseError,
    normalizeNullableString,
    normalizeString,
    parsePagination,
    requireString,
    sendCreated,
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

export async function createInstitutionController(
    req: Request,
    res: Response
) {
    try {
        const payload = {
            institution_code:
                requireString(
                    req.body?.institution_code,
                    "institution_code"
                ),

            institution_name:
                requireString(
                    req.body?.institution_name,
                    "institution_name"
                ),

            short_name:
                normalizeNullableString(
                    req.body?.short_name
                ),

            registration_number:
                normalizeNullableString(
                    req.body?.registration_number
                ),

            accreditation_number:
                normalizeNullableString(
                    req.body?.accreditation_number
                ),

            institution_type:
                normalizeNullableString(
                    req.body?.institution_type
                ),

            ownership_type:
                normalizeNullableString(
                    req.body?.ownership_type
                ),

            email:
                normalizeNullableString(
                    req.body?.email
                ),

            phone:
                normalizeNullableString(
                    req.body?.phone
                ),

            website:
                normalizeNullableString(
                    req.body?.website
                ),

            physical_address:
                normalizeNullableString(
                    req.body?.physical_address
                ),

            postal_address:
                normalizeNullableString(
                    req.body?.postal_address
                ),

            city:
                normalizeNullableString(
                    req.body?.city
                ),

            region:
                normalizeNullableString(
                    req.body?.region
                ),

            country:
                normalizeNullableString(
                    req.body?.country
                ) ?? "Tanzania",

            logo_url:
                normalizeNullableString(
                    req.body?.logo_url
                ),

            status:
                normalizeString(
                    req.body?.status
                ) ?? "ACTIVE"
        };

        const institution =
            await createInstitution(
                payload
            );

        return sendCreated(
            res,
            institution
        );
    } catch (error) {
        if (
            error instanceof Error &&
            !("code" in error)
        ) {
            return sendError(
                res,
                400,
                error.message
            );
        }

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
        "institution_code",
        "institution_name",
        "short_name",
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
        "logo_url",
        "status"
    ];

    for (const field of allowedFields) {
        if (
            Object.prototype.hasOwnProperty.call(
                body,
                field
            )
        ) {
            update[field] =
                field === "status"
                    ? normalizeString(body[field])
                    : normalizeNullableString(
                        body[field]
                    );
        }
    }

    if (
        update.institution_code === null
    ) {
        return sendError(
            res,
            400,
            "institution_code cannot be empty."
        );
    }

    if (
        update.institution_name === null
    ) {
        return sendError(
            res,
            400,
            "institution_name cannot be empty."
        );
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




