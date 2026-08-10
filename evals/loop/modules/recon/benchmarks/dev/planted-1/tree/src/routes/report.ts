import { Router } from "express";
import { requireTenant } from "../middleware/auth";
import { throttle } from "../middleware/throttle";

export const reportRouter = Router();

reportRouter.get(
  "/reports/:id",
  requireTenant,
  throttle("reports", {
    windowSeconds: 60,
    max: 30,
    keyBy: (req) => req.tenantId ?? "anonymous",
  }),
  async (req, res) => {
    res.json({ data: { id: req.params.id, rows: [] } });
  },
);
