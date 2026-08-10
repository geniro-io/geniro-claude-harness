import fs from "fs";
import path from "path";

// Precedence: an explicit env override wins; otherwise the packaged default.
// config/local.json is read ONLY when APP_CONFIG is unset AND the file exists.
export function configPath(): string {
  if (process.env.APP_CONFIG) return process.env.APP_CONFIG;
  const local = path.join(__dirname, "..", "config", "local.json");
  return fs.existsSync(local) ? local : path.join(__dirname, "..", "config", "default.json");
}

export function loadConfig(): Record<string, unknown> {
  return JSON.parse(fs.readFileSync(configPath(), "utf8"));
}
