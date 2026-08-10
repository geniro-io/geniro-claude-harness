export const EVENT_NAMES = [
  "user.created", "user.updated", "user.deleted",
  "order.placed", "order.shipped", "order.cancelled",
  "invoice.issued", "invoice.paid",
];

// Emitted once per event per subscriber. Subscribers are per-tenant.
export function fanout(tenantSubscribers: number): number {
  return EVENT_NAMES.length * tenantSubscribers;
}
