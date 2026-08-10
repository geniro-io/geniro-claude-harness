export function Table({ rows }: { rows: string[] }) {
  return <table>{rows.map((r) => <tr key={r}><td>{r}</td></tr>)}</table>;
}
