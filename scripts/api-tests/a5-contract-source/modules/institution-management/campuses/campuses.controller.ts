import type {
    Request,
    Response
} from "express";

import {
    createCampus,
    getCampus,
    institutionExists,
    listCampuses,
    updateCampus
} from "./campuses.service.js";

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

export async function listCampusesController(
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

        const institutionId =
            normalizeString(
                req.query.institutionId
            );

        if (
            institutionId &&
            !isValidUuid(institutionId)
        ) {
            return sendError(
                res,
                400,
                "Invalid institutionId."
            );
        }

        const result =
            await listCampuses({
                page,
                limit,
                ...(search ? { search } : {}),
                ...(status ? { status } : {}),
                ...(institutionId && { institutionId })
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

export async function getCampusController(
    req: Request,
    res: Response
) {
    const { id } = req.params;

    if (!isValidUuid(id)) {
        return sendError(
            res,
            400,
            "Invalid campus ID."
        );
    }

    try {
        const campus =
            await getCampus(id);

        if (!campus) {
            return sendError(
                res,
                404,
                "Campus not found."
            );
        }

        return sendSuccess(
            res,
            campus
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

export async function createCampusController(
    req: Request,
    res: Response
) {
    try {
        const institutionId =
            requireString(
                req.body?.institution_id,
                "institution_id"
            );

        if (!isValidUuid(institutionId)) {
            return sendError(
                res,
                400,
                "Invalid institution_id."
            );
        }

        if (
            !(await institutionExists(
                institutionId
            ))
        ) {
            return sendError(
                res,
                404,
                "Institution not found."
            );
        }

        const payload = {
            institution_id:
                institutionId,

            campus_code:
                requireString(
                    req.body?.campus_code,
                    "campus_code"
                ),

            campus_name:
                requireString(
                    req.body?.campus_name,
                    "campus_name"
                ),

            campus_type:
                normalizeNullableString(
                    req.body?.campus_type
                ),

            physical_address:
                normalizeNullableString(
                    req.body?.physical_address
                ),

            city:
                normalizeNullableString(
                    req.body?.city
                ),

            region:
                normalizeNullableString(
                    req.body?.region
                ),

            phone:
                normalizeNullableString(
                    req.body?.phone
                ),

            email:
                normalizeNullableString(
                    req.body?.email
                ),

            status:
                normalizeString(
                    req.body?.status
                ) ?? "ACTIVE"
        };

        const campus =
            await createCampus(
                payload
            );

        return sendCreated(
            res,
            campus
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

export async function updateCampusController(
    req: Request,
    res: Response
) {
    const { id } = req.params;

    if (!isValidUuid(id)) {
        return sendError(
            res,
            400,
            "Invalid campus ID."
        );
    }

    const body = req.body ?? {};
    const update: Record<
        string,
        unknown
    > = {};

    const allowedFields = [
        "institution_id",
        "campus_code",
        "campus_name",
        "campus_type",
        "physical_address",
        "city",
        "region",
        "phone",
        "email",
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
        update.institution_id
    ) {
        const institutionId =
            update.institution_id;

        if (
            !isValidUuid(
                institutionId
            )
        ) {
            return sendError(
                res,
                400,
                "Invalid institution_id."
            );
        }

        if (
            !(await institutionExists(
                institutionId
            ))
        ) {
            return sendError(
                res,
                404,
                "Institution not found."
            );
        }
    }

    if (
        update.campus_code === null
    ) {
        return sendError(
            res,
            400,
            "campus_code cannot be empty."
        );
    }

    if (
        update.campus_name === null
    ) {
        return sendError(
            res,
            400,
            "campus_name cannot be empty."
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
        const campus =
            await updateCampus(
                id,
                update
            );

        return sendSuccess(
            res,
            campus
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




