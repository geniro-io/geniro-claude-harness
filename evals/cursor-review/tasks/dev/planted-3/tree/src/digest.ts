import { formatNotification, User } from "./notify";

export function buildDigest(user: User, items: string[]): string {
  return formatNotification("Your weekly digest", items.join("\n"));
}
