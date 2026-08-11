import { Router } from "express";
import { readProfile, writeProfile, type Profile } from "../cache/profile";
import { loadProfileFromDb } from "../db/profile";

export const profileRouter = Router();

profileRouter.get("/me", async (req, res) => {
  const userId = req.session.userId;
  const workspaceId = req.session.workspaceId;

  const cached = await readProfile(userId);
  if (cached) return res.json(cached);

  const fresh: Profile = await loadProfileFromDb(userId, workspaceId);
  await writeProfile(fresh);
  res.json(fresh);
});
