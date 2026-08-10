export interface SpreadOptions {
  /** The nominal interval being spread. */
  cadenceMs: number;
  /** Never return less than this. */
  floorMs: number;
}

/**
 * Spreads a fixed cadence so a fleet of workers does not fire in lockstep.
 * Returns a value in [max(floorMs, cadenceMs/2), cadenceMs].
 */
export function spread(opts: SpreadOptions): number {
  const low = Math.max(opts.floorMs, opts.cadenceMs / 2);
  return low + Math.random() * Math.max(0, opts.cadenceMs - low);
}
