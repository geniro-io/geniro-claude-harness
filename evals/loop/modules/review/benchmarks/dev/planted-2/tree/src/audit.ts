import { db } from "./db";

export async function auditLog(event: string, payload: unknown): Promise<void> {
  await db.query("INSERT INTO audit_log (event, payload) VALUES ($1, $2)", [
    event,
    JSON.stringify(payload),
  ]);
}
