# Custom-instruction loader (shared)

Loads the project's rule files at a skill's phase boundary.

## Slots

Invoke with `SKILL_SLUG`, `LOAD_TIER` (`rules-only` or `full`), and `MODE`
(`initial-load` or `refresh`).

## Blocks

A project's `.plugin/instructions/global.md` may declare these blocks. The
loader extracts each one and hands it to the invoking skill:

- `## Rules` — always extracted; every skill applies them.
- `## Data Sources` — read-only fact-verification sources, opt-in per project.
- `## Review Extras` — extra reviewer dimensions to spawn alongside the built-in
  set. The invoking skill spawns one reviewer per entry, passing the entry's
  criteria verbatim.
