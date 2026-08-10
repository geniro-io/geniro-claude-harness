import { Router } from "express";
import { requireAdmin } from "../auth";

export const adminRouter = Router();

adminRouter.get("/admin/users", requireAdmin, async (_req, res) => {
  res.json({ users: [] });
});
