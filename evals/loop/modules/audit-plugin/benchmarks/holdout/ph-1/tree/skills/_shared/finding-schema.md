# Reviewer finding schema (shared)

Every reviewer returns a Markdown table with these columns, one row per finding:

| Column | Content |
|---|---|
| `id` | `D<dim>-<n>` |
| `severity` | CRITICAL / HIGH / MEDIUM / LOW |
| `file:line` | Real location, verified by the reviewer before reporting |
| `issue` | One sentence |
| `evidence` | Verbatim quote from the cited location |
