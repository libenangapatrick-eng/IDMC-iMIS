import type { Request, Response, NextFunction } from 'express';
import * as financeService from '../services/finance.service.js';

function success(res: Response, data: unknown) {
  return res.status(200).json({
    success: true,
    data
  });
}

function getParam(
  req: Request,
  name: string
): string {
  const value = req.params[name];

  if (typeof value !== 'string' || value.length === 0) {
    const error = new Error(`Missing or invalid route parameter: ${name}`);
    (error as Error & { statusCode?: number }).statusCode = 400;
    throw error;
  }

  return value;
}

export async function listFeeStructures(
  _req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    return success(res, await financeService.getFeeStructures());
  } catch (error) {
    next(error);
  }
}

export async function getFeeStructure(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const id = getParam(req, 'id');

    const result =
      await financeService.getFeeStructureById(id);

    if (!result) {
      return res.status(404).json({
        success: false,
        message: 'Fee structure not found.'
      });
    }

    return success(res, result);
  } catch (error) {
    next(error);
  }
}

export async function getFinancialAccount(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const studentId = getParam(req, 'studentId');

    const result =
      await financeService.getStudentFinancialAccount(studentId);

    if (!result) {
      return res.status(404).json({
        success: false,
        message: 'Student financial account not found.'
      });
    }

    return success(res, result);
  } catch (error) {
    next(error);
  }
}

export async function getCharges(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const studentId = getParam(req, 'studentId');

    return success(
      res,
      await financeService.getStudentCharges(studentId)
    );
  } catch (error) {
    next(error);
  }
}

export async function getInvoices(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const studentId = getParam(req, 'studentId');

    return success(
      res,
      await financeService.getStudentInvoices(studentId)
    );
  } catch (error) {
    next(error);
  }
}

export async function getPayments(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const studentId = getParam(req, 'studentId');

    return success(
      res,
      await financeService.getStudentPayments(studentId)
    );
  } catch (error) {
    next(error);
  }
}

export async function getRefunds(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const studentId = getParam(req, 'studentId');

    return success(
      res,
      await financeService.getStudentRefunds(studentId)
    );
  } catch (error) {
    next(error);
  }
}

export async function getScholarships(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const studentId = getParam(req, 'studentId');

    return success(
      res,
      await financeService.getStudentScholarships(studentId)
    );
  } catch (error) {
    next(error);
  }
}

export async function getAdjustments(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const studentId = getParam(req, 'studentId');

    return success(
      res,
      await financeService.getStudentAdjustments(studentId)
    );
  } catch (error) {
    next(error);
  }
}

export async function getTransactions(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const studentId = getParam(req, 'studentId');

    return success(
      res,
      await financeService.getStudentFinancialTransactions(studentId)
    );
  } catch (error) {
    next(error);
  }
}

