export type Spacing = "fixed" | "doubling";

export interface AttemptOptions {
  /** How many times to run the thunk before giving up. */
  attempts: number;
  /** Milliseconds before the second attempt. */
  baseMs: number;
  /** `fixed` waits baseMs every time; `doubling` doubles each round. */
  spacing: Spacing;
  /** Optional per-wait transform, applied to the computed delay. */
  shape?: (delayMs: number, attempt: number) => number;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * Runs `thunk` until it resolves or the attempt budget is spent, waiting
 * between rounds according to `spacing`. The last error is rethrown.
 */
export async function attemptSeries<T>(
  thunk: () => Promise<T>,
  opts: AttemptOptions,
): Promise<T> {
  let lastError: unknown;
  for (let attempt = 1; attempt <= opts.attempts; attempt++) {
    try {
      return await thunk();
    } catch (err) {
      lastError = err;
      if (attempt === opts.attempts) break;
      const raw = opts.spacing === "doubling" ? opts.baseMs * 2 ** (attempt - 1) : opts.baseMs;
      await sleep(opts.shape ? opts.shape(raw, attempt) : raw);
    }
  }
  throw lastError;
}
