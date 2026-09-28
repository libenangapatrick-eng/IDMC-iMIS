import type {
    Request,
    Response
} from "express";

import {
    createDepartment,
    departmentInstitutionExists,
    getDepartment,
    listDepartments,
    schoolBelongsToInstitution,
    updateDepartment
} from "./departments.service.js";

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

export async function listDepartmentsController(
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

        const schoolId =
            normalizeString(
                req.query.schoolId
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
            schoolId &&
            !isValidUuid(schoolId)
        ) {
            return sendError(
                res,
                400,
                "Invalid schoolId."
            );
        }

        const result =
            await listDepartments({
                page,
                limit,
                ...(search ? { search } : {}),
                ...(status ? { status } : {}),
                ...(institutionId ? { institutionId } : {}),
                ...(schoolId && { schoolId })
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

export async function getDepartmentController(
    req: Request,
    res: Response
) {
    const { id } = req.params;

    if (!isValidUuid(id)) {
        return sendError(
            res,
            400,
            "Invalid department ID."
        );
    }

    try {
        const department =
            await getDepartment(id);

        if (!department) {
            return sendError(
                res,
                404,
                "Department not found."
            );
        }

        return sendSuccess(
            res,
            department
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

export async function createDepartmentController(
    req: Request,
    res: Response
) {
    try {
        const institutionId =
            requireString(
                req.body?.institution_id,
                "institution_id"
            );

        const schoolId =
            requireString(
                req.body?.school_id,
                "school_id"
            );

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
            !isValidUuid(schoolId)
        ) {
            return sendError(
                res,
                400,
                "Invalid school_id."
            );
        }

        if (
            !(await departmentInstitutionExists(
                institutionId
            ))
        ) {
            return sendError(
                res,
                404,
                "Institution not found."
            );
        }

        if (
            !(await schoolBelongsToInstitution(
                schoolId,
                institutionId
            ))
        ) {
            return sendError(
                res,
                409,
                "The selected school does not belong to the selected institution."
            );
        }

        const payload = {
            institution_id:
                institutionId,

            school_id:
                schoolId,

            department_code:
                requireString(
                    req.body?.department_code,
                    "department_code"
                ),

            department_name:
                requireString(
                    req.body?.department_name,
                    "department_name"
                ),

            head_title:
                normalizeNullableString(
                    req.body?.head_title
                ) ?? "Headof Department",

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

        const department =
            await createDepartment(
                payload
            );

        return sendCreated(
            res,
            department
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

export async function updateDepartmentController(
    req: Request,
    res: Response
) {
    const { id } = req.params;

    if (!isValidUuid(id)) {
        return sendError(
            res,
            400,
            "Invalid department ID."
        );
    }

    const body = req.body ?? {};
    const update: Record<
        string,
        unknown
    > = {};

    const allowedFields = [
        "institution_id",
        "school_id",
        "department_code",
        "department_name",
        "head_title",
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

    const schoolId =
        update.school_id as
            | string
            | null
            | undefined;

    if (institutionId) {
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
            !(await departmentInstitutionExists(
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

    if (schoolId) {
        if (
            !isValidUuid(
                schoolId
            )
        ) {
            return sendError(
                res,
                400,
                "Invalid school_id."
            );
        }

        if (
            institutionId &&
            !(await schoolBelongsToInstitution(
                schoolId,
                institutionId
            ))
        ) {
            return sendError(
                res,
                409,
                "The selected school does not belong to the selected institution."
            );
        }
    }

    if (
        update.department_code === null
    ) {
        return sendError(
            res,
            400,
            "department_code cannot be empty."
        );
    }

    if (
        update.department_name === null
    ) {
        return sendError(
            res,
            400,
            "department_name cannot be empty."
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
        const department =
            await updateDepartment(
                id,
                update
            );

        return sendSuccess(
            res,
            department
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




