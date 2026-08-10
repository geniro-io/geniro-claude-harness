import Fastify from "fastify";
import { loadConfig } from "./config";

const config = loadConfig();
const app = Fastify({ logger: true });

app.get("/health", async () => ({ ok: true }));

app.listen({ port: config.port });
