import type { Request, Response, NextFunction } from "express";

declare module "express" {
  interface Request {
    tenantId?: string;
  }
}

/** Resolves the bearer token to a tenant and attaches `req.tenantId`. */
export function requireTenant(req: Request, res: Response, next: NextFunction) {
  const token = req.header("authorization")?.replace(/^Bearer /, "");
  if (!token) {
    res.status(401).json({ error: { code: "unauthorized", message: "Missing token" } });
    return;
  }
  req.tenantId = token.split(".")[0];
  next();
}
