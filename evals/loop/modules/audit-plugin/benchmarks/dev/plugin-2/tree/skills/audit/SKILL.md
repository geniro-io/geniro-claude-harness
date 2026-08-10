---
name: audit
description: "Use when auditing this plugin's own helpers and hooks for correctness before a release."
context: main
model: inherit
allowed-tools: [Read, Bash, Glob, Grep]
argument-hint: "[path | empty for the whole repo]"
---

# Audit — helper and hook correctness

## Phases overview

1. **Phase 0 — Inventory.** Enumerate `lib/` and `hooks/`.
2. **Phase 1 — Run.** Execute `tests/run-all.sh` and capture the result.
3. **Phase 2 — Report.** Write the findings table.

## Retry policy

A failed step is retried at most 3 times before the run aborts.

## Helper contracts

- `telemetry_enabled` returns `true` or `false`; call it with no argument to read the default settings path.
- `cache_key` hashes stdin; `file_key` hashes a named file.
- `query_learnings <tag>` returns matching entries newest first.
