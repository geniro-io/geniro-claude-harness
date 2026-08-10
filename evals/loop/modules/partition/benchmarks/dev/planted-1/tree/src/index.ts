// Public surface of @acme/core. Consumers import from the package root only;
// deep imports are blocked by the lint rule in eslint.config.mjs.
export { createSession, touchSession, endSession } from "./auth/session";
export { buildInvoice, voidInvoice } from "./billing/invoice";
export { registerRoutes } from "./routes";
export type { User, UserRole } from "./types/user";
