import type { FastifyInstance } from "fastify";

import { registerStripeWebhook } from "./stripe";

export async function registerWebhooks(app: FastifyInstance) {
  await registerStripeWebhook(app);
}
