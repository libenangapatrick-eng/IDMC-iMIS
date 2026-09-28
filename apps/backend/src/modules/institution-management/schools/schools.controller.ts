import type {
    Request,
    Response
} from "express";

import {
    campusBelongsToInstitution,
    createSchool,
    getSchool,
    listSchools,
    schoolInstitutionExists,
    updateSchool
} from "./schools.service.js";

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

export async function listSchoolsController(
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

        const campusId =
            normalizeString(
                req.query.campusId
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

        if (
            campusId &&
            !isValidUuid(campusId)
        ) {
            return sendError(
                res,
                400,
                "Invalid campusId."
            );
        }

        const result =
            await listSchools({
                page,
                limit,
                ...(search ? { search } : {}),
                ...(status ? { status } : {}),
                ...(institutionId ? { institutionId } : {}),
                ...(campusId && { campusId })
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

export async function getSchoolController(
    req: Request,
    res: Response
) {
    const { id } = req.params;

    if (!isValidUuid(id)) {
        return sendError(
            res,
            400,
            "Invalid school ID."
        );
    }

    try {
        const school =
            await getSchool(id);

        if (!school) {
            return sendError(
                res,
                404,
                "School not found."
            );
        }

        return sendSuccess(
            res,
            school
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

export async function createSchoolController(
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
            !(await schoolInstitutionExists(
                institutionId
            ))
        ) {
            return sendError(
                res,
                404,
                "Institution not found."
            );
        }

        const campusId =
            normalizeNullableString(
                req.body?.campus_id
            );

        if (
            campusId &&
            !isValidUuid(campusId)
        ) {
            return sendError(
                res,
                400,
                "Invalid campus_id."
            );
        }

        if (
            campusId &&
            !(await campusBelongsToInstitution(
                campusId,
                institutionId
            ))
        ) {
            return sendError(
                res,
                409,
                "The selected campus does not belong to the selected institution."
            );
        }

        const payload = {
            institution_id:
                institutionId,

            campus_id:
                campusId,

            school_code:
                requireString(
                    req.body?.school_code,
                    "school_code"
                ),

            school_name:
                requireString(
                    req.body?.school_name,
                    "school_name"
                ),

            dean_title:
                normalizeNullableString(
                    req.body?.dean_title
                ) ?? "Dean",

            email:
                normalizeNullableString(
                    req.body?.email
                ),

            phone:
                normalizeNullableString(
                    req.body?.phone
                ),

            status:
                normalizeString(
                    req.body?.status
                ) ?? "ACTIVE"
        };

        const school =
            await createSchool(
                payload
            );

        return sendCreated(
            res,
            school
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

export async function updateSchoolController(
    req: Request,
    res: Response
) {
    const { id } = req.params;

    if (!isValidUuid(id)) {
        return sendError(
            res,
            400,
            "Invalid school ID."
        );
    }

    const body = req.body ?? {};

    const update: Record<
        string,
        unknown
    > = {};

    const allowedFields = [
        "institution_id",
        "campus_id",
        "school_code",
        "school_name",
        "dean_title",
        "email",
        "phone",
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
                    ? normalizeString(
                        body[field]
                    )
                    : normalizeNullableString(
                        body[field]
                    );
        }
    }

    const institutionId =
        update.institution_id as
            | string
            | null
            | undefined;

    const campusId =
        update.campus_id as
            | string
            | null
            | undefined;

    if (institutionId) {
        if (
            !isValidUuid(institutionId)
        ) {
            return sendError(
                res,
                400,
                "Invalid institution_id."
            );
        }

        if (
            !(await schoolInstitutionExists(
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

    if (campusId) {
        if (
            !isValidUuid(campusId)
        ) {
            return sendError(
                res,
                400,
                "Invalid campus_id."
            );
        }

        if (
            institutionId &&
            !(await campusBelongsToInstitution(
                campusId,
                institutionId
            ))
        ) {
            return sendError(
                res,
                409,
                "The selected campus does not belong to the selected institution."
            );
        }
    }

    if (
        update.school_code === null
    ) {
        return sendError(
            res,
            400,
            "school_code cannot be empty."
        );
    }

    if (
        update.school_name === null
    ) {
        return sendError(
            res,
            400,
            "school_name cannot be empty."
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
        const school =
            await updateSchool(
                id,
                update
            );

        return sendSuccess(
            res,
            school
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




