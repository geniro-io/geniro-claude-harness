# Billing service — batch 9

Four approved items. They were scoped by different people and none of them was
described as blocking another.

## Todos

### todo-1 — Multi-currency amounts

Accounts outside the US are billed in their own currency. `formatMoney` must
take the ISO currency code alongside the amount and render the symbol and
separator that currency uses. Update the function and every place that calls it
today.

### todo-2 — Customer receipt

Add a receipt renderer: given a paid invoice, produce the customer-facing
receipt text — the line items, what was paid, and the payment method. Put it in
its own module under `src/receipt/`.

### todo-3 — Retry the due notice

A transient SMTP failure silently drops the "balance due" mail. Wrap the send in
three attempts with exponential backoff and give up loudly after the third.

### todo-4 — Healthcheck route

The load balancer needs something to poll. Add a `/healthz` route returning
`ok`. No auth, no dependencies.
