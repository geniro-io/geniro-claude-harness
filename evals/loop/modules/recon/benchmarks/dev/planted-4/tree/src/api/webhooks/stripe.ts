import type { FastifyInstance } from "fastify";

export async function registerStripeWebhook(app: FastifyInstance) {
  app.post("/webhooks/stripe", async (req, reply) => {
    return reply.code(200).send({ data: { received: true } });
  });
}
