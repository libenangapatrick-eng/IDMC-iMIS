import {
  Request,
  Response,
  NextFunction,
} from "express";

import {
  createUser,
  listUsers,
  listRoles,
  getUserById,
  updateUser,
  assignRole,
  removeRole,
} from "../services/users.service.js";

function getParam(
  req: Request,
  name: string
): string {
  const value = req.params[name];

  if (Array.isArray(value)) {
    return value[0] ?? "";
  }

  return value ?? "";
}

function getIpAddress(
  req: Request
): string | null {
  const forwarded =
    req.headers["x-forwarded-for"];

  if (typeof forwarded === "string") {
    return forwarded.split(",")[0]?.trim() ?? null;
  }

  return req.ip ?? null;
}

function getRequestId(
  req: Request
): string | null {
  const value =
    req.headers["x-request-id"];

  return typeof value === "string"
    ? value
    : null;
}

export async function listUsersController(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const users =
      await listUsers();

    res.json({
      success: true,
      data: users,
    });
  } catch (error) {
    next(error);
  }
}

export async function listRolesController(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const roles =
      await listRoles();

    res.json({
      success: true,
      data: roles,
    });
  } catch (error) {
    next(error);
  }
}

export async function getUserController(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const id =
      getParam(req, "id");

    const user =
      await getUserById(id);

    res.json({
      success: true,
      data: user,
    });
  } catch (error) {
    next(error);
  }
}

export async function createUserController(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: "Authentication required.",
      });

      return;
    }

    const {
      firstName,
      middleName,
      lastName,
      displayName,
      username,
      phone,
      email,
      password,
      initialRole,
      status,
    } = req.body;

    if (
      typeof firstName !== "string" ||
      !firstName.trim()
    ) {
      res.status(400).json({
        success: false,
        message: "First name is required.",
      });

      return;
    }

    if (
      typeof lastName !== "string" ||
      !lastName.trim()
    ) {
      res.status(400).json({
        success: false,
        message: "Last name is required.",
      });

      return;
    }

    if (
      typeof email !== "string" ||
      !email.trim()
    ) {
      res.status(400).json({
        success: false,
        message: "Email is required.",
      });

      return;
    }

    if (
      typeof password !== "string" ||
      password.length < 6
    ) {
      res.status(400).json({
        success: false,
        message:
          "Password must contain at least 6 characters.",
      });

      return;
    }

    const result =
      await createUser(
        {
          firstName,
          middleName,
          lastName,
          displayName,
          username,
          phone,
          email,
          password,
          initialRole,
          status,
        },

        req.user.id,

        getIpAddress(req),

        getRequestId(req)
      );

    res.status(201).json({
      success: true,
      message:
        "User created successfully and welcome email sent.",

      data: result,
    });
  } catch (error) {
    next(error);
  }
}

export async function updateUserController(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: "Authentication required.",
      });

      return;
    }

    const id =
      getParam(req, "id");

    const result =
      await updateUser(
        id,
        req.body,
        req.user.id,
        getIpAddress(req),
        getRequestId(req)
      );

    res.json({
      success: true,
      message:
        "User updated successfully.",

      data: result,
    });
  } catch (error) {
    next(error);
  }
}

export async function assignRoleController(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: "Authentication required.",
      });

      return;
    }

    const userId =
      getParam(req, "id");

    const roleCode =
      typeof req.body.roleCode === "string"
        ? req.body.roleCode
        : "";

    if (!roleCode) {
      res.status(400).json({
        success: false,
        message: "Role code is required.",
      });

      return;
    }

    const result =
      await assignRole(
        userId,
        roleCode,
        req.user.id,
        getIpAddress(req),
        getRequestId(req)
      );

    res.status(201).json({
      success: true,
      message:
        "Role assigned successfully.",

      data: result,
    });
  } catch (error) {
    next(error);
  }
}

export async function removeRoleController(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    if (!req.user) {
      res.status(401).json({
        success: false,
        message: "Authentication required.",
      });

      return;
    }

    const userId =
      getParam(req, "id");

    const roleId =
      getParam(req, "roleId");

    const result =
      await removeRole(
        userId,
        roleId,
        req.user.id,
        getIpAddress(req),
        getRequestId(req)
      );

    res.json({
      success: true,
      message:
        "Role removed successfully.",

      data: result,
    });
  } catch (error) {
    next(error);
  }
}
