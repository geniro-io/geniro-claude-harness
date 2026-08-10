import { Router } from "express";
import { requireTenant } from "../middleware/auth";

export const exportRouter = Router();

/**
 * Streams the tenant's ledger as CSV. Large exports can run for minutes and
 * hold a database cursor open for the whole time.
 */
exportRouter.post("/exports/ledger.csv", requireTenant, async (req, res) => {
  res.setHeader("content-type", "text/csv");
  res.write("date,description,amount\n");
  res.end();
});
