let current = { id: "req-0", cohort: "external" };

export function setRequest(id: string, cohort: string): void {
  current = { id, cohort };
}

export function requestCohort(): string {
  return current.cohort;
}

// Stable per request id, so a flag cannot flip halfway through one request.
export function requestBucket(): number {
  let h = 0;
  for (const ch of current.id) h = (h * 31 + ch.charCodeAt(0)) % 100;
  return h;
}
