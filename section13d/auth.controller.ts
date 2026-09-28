import type { Request, Response } from "express";
import * as authService from "../services/auth.service.js";
import { logError } from "../../../utils/logger.js";

export async function login(req: Request, res: Response): Promise<void> {
  const identifier = String(req.body?.identifier ?? "").trim();
  const password = String(req.body?.password ?? "");
  const requestedAccountType = String(
    req.body?.accountType ?? "AUTO"
  ).trim().toUpperCase();

  if (!identifier || !password) {
    res.status(400).json({
      success: false,
      message: "Email, username or student number and password are required",
    });
    return;
  }

  if (!["AUTO", "STAFF", "STUDENT"].includes(requestedAccountType)) {
    res.status(400).json({
      success: false,
      message: "Account type must be STAFF or STUDENT",
    });
    return;
  }

  try {
    const session = await authService.login(
      identifier,
      password,
      requestedAccountType as authService.LoginAccountType
    );
    res.json({ success: true, data: session });
  } catch (error) {
    /* Keep the public response generic, but retain the real server-side cause. */
    logError(`Login failed for identifier ${identifier}`, error);
    res.status(401).json({
      success: false,
      message: "Invalid login credentials",
    });
  }
}

export async function me(req: Request, res: Response): Promise<void> {
  if (!req.user) {
    res.status(401).json({
      success: false,
      message: "Authentication required",
    });
    return;
  }

  const data = await authService.getCurrentUser(req.user.id);
  res.json({ success: true, data });
}

export async function authHealth(
  _req: Request,
  res: Response
): Promise<void> {
  res.json({
    success: true,
    module: "authentication",
    status: "online",
  });
}

