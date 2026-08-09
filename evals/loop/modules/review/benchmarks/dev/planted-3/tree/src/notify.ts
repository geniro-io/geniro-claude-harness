export interface User {
  email: string;
  emailVerified: boolean;
  marketingOptIn: boolean;
}

export function formatNotification(subject: string, body: string): string {
  return `[Acme] ${subject}\n\n${body}`;
}

export async function sendPromoEmail(user: User, subject: string, body: string) {
  if (!user.emailVerified || !user.marketingOptIn) {
    return;
  }
  const message = formatNotification(subject, body);
  await deliver(user.email, message);
}

async function deliver(_to: string, _message: string): Promise<void> {}
