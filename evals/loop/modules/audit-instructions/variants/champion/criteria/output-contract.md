## Finding output contract

Every reviewer returns a Markdown table with EXACTLY these columns, one row per finding, capped at 25 rows (rank by impact; note "N further low-impact items omitted" if capped):

| Column | Content |
|---|---|
| `id` | `D<dim>-<n>` (e.g. `D3-4`); sub-reviewer spawns keep their unique label (`D5a-2`, `D4-shardB-1`) |
| `tier` | per the consuming skill's severity-tier table |
| `file:line` | Real location — verified by the reviewer with Read before reporting. Use `file:start-end` for ranges. |
| `issue` | One sentence, plain English |
| `evidence` | Verbatim quote (≤2 lines) from the cited location — the orchestrator re-verifies this quote exists |
| `fix` | Concrete suggested change, one sentence |
| `effort` | S / M / L |

A finding without a verifiable `file:line` + `evidence` is inadmissible — drop it rather than guessing a location. A consuming skill may narrow a column's rules for its domain (a secrets-auditing skill cites location and shape in `evidence`, never the value); the narrowing lives in that skill's reference, beside its citation of this section.

