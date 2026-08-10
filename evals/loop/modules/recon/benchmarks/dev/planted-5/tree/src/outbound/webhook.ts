export interface Delivery {
  url: string;
  payload: unknown;
}

/**
 * Posts a delivery to a subscriber. A non-2xx response throws; today the
 * caller drops the delivery on the floor.
 */
export async function deliver(d: Delivery): Promise<void> {
  const res = await fetch(d.url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(d.payload),
  });
  if (!res.ok) throw new Error(`delivery to ${d.url} failed: ${res.status}`);
}
