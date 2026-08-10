type Handler = (req: unknown) => unknown;
const table = new Map<string, Handler>();

export function registerRoutes(): void {
  table.set("/login", () => ({ ok: true }));
  table.set("/session", () => ({ ok: true }));
  table.set("/logout", () => ({ ok: true }));
}
