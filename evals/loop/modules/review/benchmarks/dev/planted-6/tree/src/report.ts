import { db } from "./db";

export async function getOrderIds(customerId: string): Promise<string[]> {
  const rows = await db.query("SELECT id FROM orders WHERE customer_id = $1", [customerId]);
  return rows.map((r) => r.id);
}
