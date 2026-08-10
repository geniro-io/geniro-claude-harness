// Every quota the scheduler enforces lives here. The scheduler reads this object
// once at boot; nothing else defines a limit.
export const LIMITS = {
  maxConcurrentJobs: 4,
  maxQueueDepth: 200,
  jobTimeoutMs: 60_000,
};
