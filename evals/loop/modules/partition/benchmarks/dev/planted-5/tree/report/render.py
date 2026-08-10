"""Fixed-width account report.

Columns are DISCOVERED, not registered: every module under ``report.columns``
that defines ``HEADER`` and ``cell(account)`` is a column, and the report shows
them in the order the package lists them. Adding a column is therefore a matter
of dropping a file in — there is deliberately no central column list to edit.

The table is fixed-width: each column is padded to the widest cell in it, so a
new column re-flows nothing but its own space, while a change to any cell's
text can change the padding of the whole table.
"""

from __future__ import annotations

import pkgutil
from importlib import import_module

from . import columns as columns_pkg


def _columns():
    for info in sorted(pkgutil.iter_modules(columns_pkg.__path__), key=lambda i: i.name):
        module = import_module(f"{columns_pkg.__name__}.{info.name}")
        if hasattr(module, "HEADER") and hasattr(module, "cell"):
            yield module


def render(accounts: list[dict]) -> str:
    """Render the fixed-width report for ``accounts``."""
    mods = list(_columns())
    rows = [[m.HEADER for m in mods]]
    rows.extend([[m.cell(a) for m in mods] for a in accounts])
    widths = [max(len(row[i]) for row in rows) for i in range(len(mods))]
    lines = [
        "  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)).rstrip()
        for row in rows
    ]
    lines.insert(1, "  ".join("-" * w for w in widths))
    return "\n".join(lines) + "\n"
