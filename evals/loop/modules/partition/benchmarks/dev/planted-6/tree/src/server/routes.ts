import { printInvoice } from '../invoice/print';
import { summarize } from '../report/summary';

type Handler = (query: Record<string, string>) => Promise<string> | string;

/**
 * Every HTTP route the service answers. A route that is not in this table does
 * not exist — the server has no fallback and no auto-discovery.
 */
export const ROUTES: Record<string, Handler> = {
  '/invoices/print': async (q) => printInvoice(await loadInvoice(q.id)),
  '/reports/daily': async () => summarize(await loadAccountRows()),
};

declare function loadInvoice(id: string): Promise<Parameters<typeof printInvoice>[0]>;
declare function loadAccountRows(): Promise<Parameters<typeof summarize>[0]>;
