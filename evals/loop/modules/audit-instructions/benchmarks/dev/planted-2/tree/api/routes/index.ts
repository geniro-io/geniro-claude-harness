import { registerHealth } from "./health";

export function registerRoutes(app: unknown) {
  registerHealth(app);
}
