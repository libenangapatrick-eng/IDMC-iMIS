import type { NextFunction, Request, Response } from "express";
import { getSupabase } from "../config/database.js";
import { rolesGrantPermission, rolesGrantRole } from "../utils/security.js";

type RoleAssignment = Record<string, any>;

export function requirePermission(permissionCode: string) {
  return async (
    req: Request,
    res: Response,
    next: NextFunction
  ): Promise<void> => {
    try {
      if (!req.user) {
        res.status(401).json({
          success: false,
          message: "Authentication required"
        });
        return;
      }

      const supabase = getSupabase();

      const { data, error } = await supabase
        .from("user_roles")
        .select(`
          id,
          status,
          expires_at,
          roles!inner (
            id,
            role_code,
            status,
            role_permissions!inner (
              permissions!inner (
                permission_code,
                status
              )
            )
          )
        `)
        .eq("user_id", req.user.id)
        .eq("status", "ACTIVE");

      if (error) {
        next(error);
        return;
      }

      const hasPermission = rolesGrantPermission(data as RoleAssignment[], permissionCode);

      if (!hasPermission) {
        res.status(403).json({
          success: false,
          message: `Permission denied: ${permissionCode}`
        });
        return;
      }

      next();
    } catch (error) {
      next(error);
    }
  };
}

export function requireRole(...roleCodes: string[]) {
  return async (
    req: Request,
    res: Response,
    next: NextFunction
  ): Promise<void> => {
    try {
      if (!req.user) {
        res.status(401).json({
          success: false,
          message: "Authentication required"
        });
        return;
      }

      const supabase = getSupabase();

      const { data, error } = await supabase
        .from("user_roles")
        .select(`
          status,
          expires_at,
          roles!inner (
            role_code,
            status
          )
        `)
        .eq("user_id", req.user.id)
        .eq("status", "ACTIVE");

      if (error) {
        next(error);
        return;
      }

      const hasRole = rolesGrantRole(data as RoleAssignment[], roleCodes);

      if (!hasRole) {
        res.status(403).json({
          success: false,
          message: "Required role not assigned"
        });
        return;
      }

      next();
    } catch (error) {
      next(error);
    }
  };
}
