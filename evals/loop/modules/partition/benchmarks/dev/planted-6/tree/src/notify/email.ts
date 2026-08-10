import { formatMoney } from '../format/money';
import { smtpSend } from './smtp';

export interface DueNotice {
  to: string;
  accountName: string;
  balanceCents: number;
}

/**
 * The "your balance is due" mail. One shot, no retry — a transient SMTP
 * failure currently drops the notice on the floor.
 */
export async function sendDueNotice(notice: DueNotice): Promise<void> {
  const body =
    `Hi ${notice.accountName},\n\n` +
    `Your outstanding balance is ${formatMoney(notice.balanceCents)}.\n` +
    `Please settle it within 14 days.\n`;
  await smtpSend({ to: notice.to, subject: 'Balance due', body });
}
