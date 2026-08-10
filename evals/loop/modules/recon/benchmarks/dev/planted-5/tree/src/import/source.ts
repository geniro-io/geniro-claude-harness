export async function fetchPage(feedId: string, page: number): Promise<string[]> {
  const res = await fetch(`https://partner.example/feeds/${feedId}?page=${page}`);
  if (!res.ok) throw new Error(`feed ${feedId} page ${page}: ${res.status}`);
  return (await res.json()) as string[];
}
