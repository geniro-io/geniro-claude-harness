import { rateLimit } from "./limiter";

export function registerRoutes(app: any) {
  app.post("/login", rateLimit({ perMinute: 10 }), loginHandler);
  app.get("/session", sessionHandler);
  app.post("/logout", logoutHandler);
}

function loginHandler() {}
function sessionHandler() {}
function logoutHandler() {}
