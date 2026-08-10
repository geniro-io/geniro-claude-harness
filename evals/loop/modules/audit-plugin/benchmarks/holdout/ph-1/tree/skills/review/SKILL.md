---
name: review
description: "Use when reviewing a pending diff — parallel dimension reviewers, verified findings, a tiered report. Skip for auditing instruction files."
context: main
model: inherit
allowed-tools: [Read, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[branch | PR number | empty for the working diff]"
---

# Review — pending-diff review

## Phases overview

1. **Phase 0 — Triage.** Resolve the diff and load custom instructions.
2. **Phase 1 — Reviewers.** Spawn one reviewer per dimension in ONE response.
3. **Phase 2 — Verify.** Re-read every cited location; drop what does not hold.
4. **Phase 3 — Report.** Render the tiered table.

## PHASE 0 — Triage

Resolve the diff. Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/instruction-loader.md` with `SKILL_SLUG: review`, `LOAD_TIER: rules-only`, `MODE: initial-load`. Extract the `## Rules` block into `$PROJECT_RULES` for the Phase 1 spawn template.

## PHASE 1 — Reviewers

Spawn one reviewer per dimension — bugs, security, tests — in ONE response; separate turns serialize the batch and double wall-time. Paste `$PROJECT_RULES` into each prompt.

Spawn `geniro:coverage-agent` alongside them to map which changed lines the suite exercises.

## PHASE 2 — Verify

Read each cited location and confirm the quoted evidence is there. Drop the rest.

## PHASE 3 — Report

Render the table, then offer the fix gate. Pass `--legacy` to emit the flat pre-2.0 report shape instead.

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/instruction-loader.md` — loader slots and blocks
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-schema.md` — the reviewer finding table
