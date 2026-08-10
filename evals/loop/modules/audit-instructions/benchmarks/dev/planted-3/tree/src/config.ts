export const batchSize = Number(process.env.INGEST_BATCH_SIZE ?? 500);
export const bucket = process.env.INGEST_BUCKET ?? "";
