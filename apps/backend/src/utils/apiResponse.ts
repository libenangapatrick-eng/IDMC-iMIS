import { Response } from "express";

export function successResponse(
  res: Response,
  data: unknown = null,
  message = "Request successful",
  statusCode = 200
) {
  return res.status(statusCode).json({
    success: true,
    message,
    data,
  });
}

export function errorResponse(
  res: Response,
  message = "Request failed",
  statusCode = 500,
  errors: unknown = null
) {
  return res.status(statusCode).json({
    success: false,
    message,
    errors,
  });
}
