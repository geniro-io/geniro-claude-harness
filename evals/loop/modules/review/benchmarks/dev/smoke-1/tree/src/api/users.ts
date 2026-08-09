import { db } from "../db";

export async function getUser(id: string) {
  return db.query("SELECT * FROM users WHERE id = $1", [id]);
}
