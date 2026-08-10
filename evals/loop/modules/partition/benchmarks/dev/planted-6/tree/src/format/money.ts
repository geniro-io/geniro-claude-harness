/**
 * The single money renderer for this service.
 *
 * Every user-visible amount goes through here — the symbol, the thousands
 * separator, and the minor-unit rounding live in this function and nowhere
 * else, so a change to how we print money is a change to one file. Formatting
 * an amount inline anywhere else is a review blocker; the three existing
 * call sites (invoice print, report summary, notification email) are the
 * pattern to follow.
 */
export function formatMoney(cents: number): string {
  const whole = Math.trunc(cents / 100);
  const minor = Math.abs(cents % 100)
    .toString()
    .padStart(2, '0');
  return `$${whole.toLocaleString('en-US')}.${minor}`;
}
