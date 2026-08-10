import { batchSize } from "./config";

export async function ingest(rows: string[]) {
  for (let i = 0; i < rows.length; i += batchSize) {
    await Promise.resolve(rows.slice(i, i + batchSize));
  }
}
