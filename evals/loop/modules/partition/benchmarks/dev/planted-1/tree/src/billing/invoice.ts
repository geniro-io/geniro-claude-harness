import type { User } from "../types/user";

export interface Invoice {
  id: string;
  owner: User;
  cents: number;
  voided: boolean;
}

const ledger: Invoice[] = [];

export function buildInvoice(owner: User, cents: number): Invoice {
  const inv: Invoice = { id: crypto.randomUUID(), owner, cents, voided: false };
  ledger.push(inv);
  return inv;
}

export function voidInvoice(id: string): boolean {
  const inv = ledger.find((i) => i.id === id);
  if (!inv) return false;
  inv.voided = true;
  return true;
}
