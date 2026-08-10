import { queue } from "./queue";

// Same-cluster call with a caller-held deadline: runs inline by convention.
export async function buildReport(deadlineMs: number) {
  const rows = await fetchRowsFromLocalService(deadlineMs);
  return rows.length;
}

export async function emailReport(id: string) {
  await queue.push({ kind: "email", id });
}

async function fetchRowsFromLocalService(_d: number): Promise<unknown[]> { return []; }
