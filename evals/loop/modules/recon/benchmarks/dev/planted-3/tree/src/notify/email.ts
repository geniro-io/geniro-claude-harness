import nodemailer from "nodemailer";

const transport = nodemailer.createTransport({ url: process.env.SMTP_URL });

export interface Notification {
  to: string;
  subject: string;
  body: string;
}

export async function sendEmail(n: Notification): Promise<void> {
  await transport.sendMail({ to: n.to, subject: n.subject, text: n.body });
}
