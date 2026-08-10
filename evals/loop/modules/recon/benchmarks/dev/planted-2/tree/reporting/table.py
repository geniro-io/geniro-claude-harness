"""Fixed-width table rendering.

Column widths are computed from the widest cell in each column, which means
every row must be in hand before the first line can be emitted.
"""
from typing import Iterable, Sequence


def render(headers: Sequence[str], rows: Iterable[Sequence[str]]) -> str:
    materialized = [list(map(str, r)) for r in rows]
    widths = [len(h) for h in headers]
    for row in materialized:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))
    out = [" | ".join(h.ljust(widths[i]) for i, h in enumerate(headers))]
    out.append("-+-".join("-" * w for w in widths))
    for row in materialized:
        out.append(" | ".join(c.ljust(widths[i]) for i, c in enumerate(row)))
    return "\n".join(out)
