import { formatMoney } from '../format/money';

export interface LineItem {
  description: string;
  cents: number;
}

export interface Invoice {
  id: string;
  issuedAt: string;
  lines: LineItem[];
}

export function printInvoice(invoice: Invoice): string {
  const body = invoice.lines
    .map((line) => `${line.description.padEnd(28)}${formatMoney(line.cents)}`)
    .join('\n');
  const total = invoice.lines.reduce((sum, line) => sum + line.cents, 0);
  return `INVOICE ${invoice.id}\n${body}\nTOTAL${' '.repeat(23)}${formatMoney(total)}\n`;
}
