export const searchFeature = { name: "search" };

const PAGE_SIZE = 25;

// Returns the slice of ids for a 1-based page number.
export function pageSlice(ids: string[], page: number): string[] {
  const start = page * PAGE_SIZE;
  return ids.slice(start, start + PAGE_SIZE);
}
