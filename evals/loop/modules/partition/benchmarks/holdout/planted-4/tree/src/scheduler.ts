import { LIMITS } from "./limits";

const queue: string[] = [];

export function enqueue(jobId: string): boolean {
  if (queue.length >= LIMITS.maxQueueDepth) return false;
  queue.push(jobId);
  return true;
}

export function drain(): string[] {
  return queue.splice(0, LIMITS.maxConcurrentJobs);
}
