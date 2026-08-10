import { withRetry } from "./retry";

export async function schedule(job: string) {
  return withRetry(async () => job);
}
