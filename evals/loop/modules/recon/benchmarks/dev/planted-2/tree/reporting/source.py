from typing import Iterator, Sequence


def fetch_rows() -> tuple[Sequence[str], Iterator[Sequence[str]]]:
    """Yields ledger rows lazily — the result set does not fit in memory."""
    headers = ("date", "description", "amount")

    def gen() -> Iterator[Sequence[str]]:
        for i in range(1_000_000):
            yield (f"2026-01-{i % 28 + 1:02d}", f"entry {i}", f"{i}.00")

    return headers, gen()
