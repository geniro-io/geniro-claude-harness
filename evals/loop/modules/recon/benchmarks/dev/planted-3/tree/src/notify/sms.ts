import type { Notification } from "./email";

/** Placeholder — the SMS gateway contract is not settled yet. */
export async function sendSms(_n: Notification): Promise<void> {
  throw new Error("not implemented");
}
