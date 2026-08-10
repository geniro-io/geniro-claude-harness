export const exportFeature = { name: "export" };

const DELIMITER = ",";

export function toCsv(rows: string[][]): string {
  return rows.map((r) => r.join(DELIMITER)).join("\n");
}
