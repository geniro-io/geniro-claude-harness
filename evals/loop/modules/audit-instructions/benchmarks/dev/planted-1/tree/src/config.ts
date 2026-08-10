export interface Config {
  port: number;
  databaseUrl: string;
  stripeKey: string;
}

export function loadConfig(): Config {
  return {
    port: Number(process.env.PORT ?? 3000),
    databaseUrl: process.env.DATABASE_URL ?? "",
    stripeKey: process.env.STRIPE_KEY ?? "",
  };
}
