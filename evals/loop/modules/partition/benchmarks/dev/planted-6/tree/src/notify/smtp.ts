export interface Mail {
  to: string;
  subject: string;
  body: string;
}

/** Thin wrapper over the SMTP client. Throws on any non-2xx response. */
export async function smtpSend(mail: Mail): Promise<void> {
  const res = await fetch(process.env.SMTP_URL ?? 'http://localhost:1025/send', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(mail),
  });
  if (!res.ok) {
    throw new Error(`smtp ${res.status}`);
  }
}
