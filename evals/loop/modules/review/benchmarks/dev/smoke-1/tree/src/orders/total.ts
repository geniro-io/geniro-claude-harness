export interface OrderItem {
  price: number;
  qty: number;
  discount?: { pct: number };
}

export function itemTotal(item: OrderItem): number {
  return item.price * item.qty;
}

export function orderTotal(items: OrderItem[]): number {
  return items.reduce((sum, it) => sum + itemTotal(it), 0);
}
