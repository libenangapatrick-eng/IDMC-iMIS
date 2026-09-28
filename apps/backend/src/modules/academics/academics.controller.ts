import type { Request, Response } from "express";
import { academicsService } from "./academics.service.js";

export class AcademicsController {

    async list(req: Request, res: Response) {

        try {

            const institutionId =
                String(req.query.institutionId || "").trim();

            if (!institutionId) {
                return res.status(400).json({
                    message: "institutionId is required"
                });
            }

            const records =
                await academicsService.list(institutionId);

            return res.status(200).json({
                data: records,
                count: records.length
            });

        } catch (error) {

            console.error(
                "Academics list error:",
                error
            );

            return res.status(500).json({
                message: "Failed to load academic records"
            });
        }
    }

    async getById(req: Request, res: Response) {

        try {

            const institutionId =
                String(req.query.institutionId || "").trim();

            const id =
                String(req.params.id || "").trim();

            if (!institutionId || !id) {
                return res.status(400).json({
                    message:
                        "institutionId and id are required"
                });
            }

            const record =
                await academicsService.getById(
                    institutionId,
                    id
                );

            if (!record) {
                return res.status(404).json({
                    message:
                        "Academic record not found"
                });
            }

            return res.status(200).json(record);

        } catch (error) {

            console.error(
                "Academics get error:",
                error
            );

            return res.status(500).json({
                message:
                    "Failed to load academic record"
            });
        }
    }

    async create(req: Request, res: Response) {

        try {

            const input = req.body;

            if (
                !input ||
                !input.institutionId ||
                !input.studentId
            ) {
                return res.status(400).json({
                    message:
                        "institutionId and studentId are required"
                });
            }

            const record =
                await academicsService.create(input);

            return res.status(201).json(record);

        } catch (error) {

            console.error(
                "Academics create error:",
                error
            );

            return res.status(500).json({
                message:
                    "Failed to create academic record"
            });
        }
    }

    async update(req: Request, res: Response) {

        try {

            const id =
                String(req.params.id || "").trim();

            if (!id) {
                return res.status(400).json({
                    message: "id is required"
                });
            }

            const record =
                await academicsService.update(
                    id,
                    req.body
                );

            return res.status(200).json(record);

        } catch (error) {

            console.error(
                "Academics update error:",
                error
            );

            return res.status(500).json({
                message:
                    "Failed to update academic record"
            });
        }
    }

    async remove(req: Request, res: Response) {

        try {

            const institutionId =
                String(req.query.institutionId || "").trim();

            const id =
                String(req.params.id || "").trim();

            if (!institutionId || !id) {
                return res.status(400).json({
                    message:
                        "institutionId and id are required"
                });
            }

            await academicsService.remove(
                institutionId,
                id
            );

            return res.status(204).send();

        } catch (error) {

            console.error(
                "Academics delete error:",
                error
            );

            return res.status(500).json({
                message:
                    "Failed to delete academic record"
            });
        }
    }
}

export const academicsController =
    new AcademicsController();
