import type { Request, Response, NextFunction } from "express";
import { redis } from "../cache/redis";

// On a workspace switch the session record is rewritten AND every cache entry
// namespaced to the outgoing workspace is dropped.
export async function switchWorkspace(req: Request, _res: Response, next: NextFunction) {
  const { userId, nextWorkspaceId } = req.body;
  const prev = req.session.workspaceId;

  req.session.workspaceId = nextWorkspaceId;
  await redis.del(`session:${userId}`);
  await redis.del(`workspace:${prev}:members`);

  next();
}
