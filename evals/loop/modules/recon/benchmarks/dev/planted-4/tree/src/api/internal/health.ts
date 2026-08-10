import type { FastifyInstance } from "fastify";

export async function registerHealth(app: FastifyInstance) {
  app.get("/internal/health", async () => ({ data: { ok: true } }));
}
