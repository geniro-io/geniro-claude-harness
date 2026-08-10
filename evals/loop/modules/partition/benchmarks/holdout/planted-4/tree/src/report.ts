export function formatDuration(ms: number): string {
  return `${Math.round(ms / 1000)}s`;
}
