import type { Request, Response } from "express";
import { decideStudentRequest, getFinanceWorkspace, getLecturerWorkspace, getRegistryWorkspace, listStaffAccounts, markLecturerAttendance, provisionStaffAccount, recordFinancePayment, recordLecturerMark, submitLecturerMark, submitLecturerResult } from "./staff-workspace.service.js";

function body(req: Request): Record<string, unknown> { return req.body && typeof req.body === "object" ? req.body : {}; }
async function run(res: Response, action: () => Promise<unknown>) {
  try { return res.json({ success: true, data: await action() }); }
  catch (error) { return res.status(400).json({ success: false, message: error instanceof Error ? error.message : "Staff workspace request failed." }); }
}
export const lecturerWorkspace = (req: Request, res: Response) => run(res, () => getLecturerWorkspace(req));
export const lecturerAttendance = (req: Request, res: Response) => run(res, () => markLecturerAttendance(req, body(req)));
export const lecturerMark = (req: Request, res: Response) => run(res, () => recordLecturerMark(req, body(req)));
export const lecturerMarkSubmit = (req: Request, res: Response) => run(res, () => submitLecturerMark(req, body(req)));
export const lecturerResultSubmit = (req: Request, res: Response) => run(res, () => submitLecturerResult(req, body(req)));
export const financeWorkspace = (req: Request, res: Response) => run(res, () => getFinanceWorkspace(req));
export const financePayment = (req: Request, res: Response) => run(res, () => recordFinancePayment(req, body(req)));
export const registryWorkspace = (req: Request, res: Response) => run(res, () => getRegistryWorkspace(req));
export const registryRequestDecision = (req: Request, res: Response) => run(res, () => decideStudentRequest(req, body(req)));
export const staffAccounts = (_req: Request, res: Response) => run(res, () => listStaffAccounts());
export const staffAccountProvision = (req: Request, res: Response) => run(res, () => provisionStaffAccount(req, body(req)));
