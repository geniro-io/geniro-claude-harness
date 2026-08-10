export function Button({ label }: { label: string }) {
  return <button className="p-2" aria-label={label}>{label}</button>;
}
