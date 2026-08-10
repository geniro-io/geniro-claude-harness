import { attemptSeries } from "../lib/schedule";

import { fetchPage } from "./source";

/** Pulls every page of the partner feed, retrying a page that fails. */
export async function runImport(feedId: string): Promise<number> {
  let page = 0;
  let total = 0;
  for (;;) {
    const rows = await attemptSeries(() => fetchPage(feedId, page), {
      attempts: 4,
      baseMs: 250,
      spacing: "doubling",
    });
    if (rows.length === 0) return total;
    total += rows.length;
    page += 1;
  }
}
