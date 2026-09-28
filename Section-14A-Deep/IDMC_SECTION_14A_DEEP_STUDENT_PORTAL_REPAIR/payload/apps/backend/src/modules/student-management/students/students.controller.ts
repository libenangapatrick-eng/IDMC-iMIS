import type { Request, Response } from "express";

import {
    createStudent,
    getMyStudentRecord,
    getStudentById,
    listStudents,
    updateStudent,
} from "./students.service.js";
import {
    changeOwnPassword,
    getStudentPortal,
    respondToCoursework,
    submitCourseEvaluation,
    submitHelpdeskTicket,
    submitServiceRequest,
    updateOwnPhoto,
    updateOwnProfile,
} from "./student-self-service.service.js";

function sendSuccess(
    res: Response,
    data: unknown
) {

    return res.status(200).json({
        success: true,
        data,
    });
}

function sendCreated(
    res: Response,
    data: unknown
) {

    return res.status(201).json({
        success: true,
        data,
    });
}

function sendError(
    res: Response,
    status: number,
    message: string
) {

    return res.status(status).json({
        success: false,
        message,
    });
}

function getBody(
    req: Request
) {

    return (
        req.body &&
        typeof req.body === "object"
            ? req.body
            : {}
    );
}

async function runSelfService(
    res: Response,
    action: () => Promise<unknown>
) {
    try {
        return sendSuccess(res, await action());
    } catch (error) {
        return sendError(
            res,
            400,
            error instanceof Error
                ? error.message
                : "Student self-service request failed."
        );
    }
}

export const getMyStudentPortalController = (req: Request, res: Response) =>
    runSelfService(res, () => getStudentPortal(req));

export const updateMyProfileController = (req: Request, res: Response) =>
    runSelfService(res, () => updateOwnProfile(req, getBody(req)));

export const updateMyProfilePhotoController = (req: Request, res: Response) =>
    runSelfService(res, () => updateOwnPhoto(req, getBody(req)));

export const respondToCourseworkController = (req: Request, res: Response) =>
    runSelfService(res, () => respondToCoursework(req, getBody(req)));

export const submitCourseEvaluationController = (req: Request, res: Response) =>
    runSelfService(res, () => submitCourseEvaluation(req, getBody(req)));

export const submitServiceRequestController = (req: Request, res: Response) =>
    runSelfService(res, () => submitServiceRequest(req, getBody(req)));

export const submitHelpdeskTicketController = (req: Request, res: Response) =>
    runSelfService(res, () => submitHelpdeskTicket(req, getBody(req)));

export const changeMyPasswordController = (req: Request, res: Response) =>
    runSelfService(res, () => changeOwnPassword(req, getBody(req)));

export async function listStudentsController(
    req: Request,
    res: Response
) {

    try {

        const page =
            Number(req.query.page ?? 1);

        const limit =
            Number(req.query.limit ?? 25);

        const search =
            typeof req.query.search === "string"
                ? req.query.search
                : undefined;

        const status =
            typeof req.query.status === "string"
                ? req.query.status
                : undefined;

        const institutionId =
            typeof req.query.institutionId === "string"
                ? req.query.institutionId
                : undefined;

        const result =
            await listStudents(
                page,
                limit,
                search,
                status,
                institutionId
            );

        return sendSuccess(
            res,
            result
        );

    } catch (error) {

        console.error(
            "List students failed:",
            error
        );

        return sendError(
            res,
            500,
            error instanceof Error
                ? error.message
                : "Unable to load students."
        );
    }
}

export async function getStudentController(
    req: Request,
    res: Response
) {

    try {

        const id =
            String(req.params.id);

        const result =
            await getStudentById(id);

        return sendSuccess(
            res,
            result
        );

    } catch (error) {

        return sendError(
            res,
            404,
            error instanceof Error
                ? error.message
                : "Student not found."
        );
    }
}

export async function getMyStudentController(
    req: Request,
    res: Response
) {

    try {

        const result =
            await getMyStudentRecord(req);

        return sendSuccess(
            res,
            result
        );

    } catch (error) {

        return sendError(
            res,
            404,
            error instanceof Error
                ? error.message
                : "Student record not found."
        );
    }
}

export async function createStudentController(
    req: Request,
    res: Response
) {

    try {

        const result =
            await createStudent(
                req,
                getBody(req) as never
            );

        return sendCreated(
            res,
            result
        );

    } catch (error) {

        console.error(
            "Create student failed:",
            error
        );

        return sendError(
            res,
            400,
            error instanceof Error
                ? error.message
                : "Unable to create student."
        );
    }
}

export async function updateStudentController(
    req: Request,
    res: Response
) {

    try {

        const id =
            String(req.params.id);

        const result =
            await updateStudent(
                req,
                id,
                getBody(req) as never
            );

        return sendSuccess(
            res,
            result
        );

    } catch (error) {

        console.error(
            "Update student failed:",
            error
        );

        return sendError(
            res,
            400,
            error instanceof Error
                ? error.message
                : "Unable to update student."
        );
    }
}
