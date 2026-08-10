import { formatMoney } from '../format/money';

export interface AccountRow {
  name: string;
  billedCents: number;
}

/** One line per account, for the ops daily digest. */
export function summarize(rows: AccountRow[]): string {
  return rows
    .map((row) => `${row.name.padEnd(24)}${formatMoney(row.billedCents)}`)
    .join('\n');
}
