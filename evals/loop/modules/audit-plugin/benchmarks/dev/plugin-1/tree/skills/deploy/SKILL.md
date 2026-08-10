---
name: deploy
description: "Use when shipping a release to staging or production — cuts the tag, runs the smoke suite, and promotes the build. Skip for local-only changes."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[environment | empty for staging]"
---

# Deploy — release pipeline

## Phases overview

1. **Phase 0 — Preflight.** Verify the working tree is clean and the tag does not exist.
2. **Phase 1 — Build.** Produce the artifact and record its digest.
3. **Phase 2 — Smoke.** Run the smoke suite against the built artifact.
4. **Phase 3 — Promote.** Move the artifact into the target environment.

## Loop invariants

1. **No promote without a green smoke run.** Phase 3 reads Phase 2's result file; a missing result is a failure, never a pass.
2. **State writes go through the helper.** Write `state.md` via `atomic_state_write` from `${CLAUDE_PLUGIN_ROOT}/lib/atomic-write.sh` — a direct write truncates and rewrites, so a reader hitting that window sees a partial file.

## PHASE 0 — Preflight

Confirm the tree is clean. Read the rollback contract at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/rollback-contract.md` before proceeding — it names what a half-promoted release leaves behind.

## PHASE 1 — Build

Build the artifact. Record the digest in the state file.

## PHASE 2 — Smoke

Run the smoke suite. Write the result to the state file.

## PHASE 3 — Promote

Promote the artifact. When promotion fails midway, hand off to `/geniro:promote` for the manual completion walk.

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/deploy/steps-reference.md` — per-phase step detail
- `${CLAUDE_PLUGIN_ROOT}/skills/deploy/SKILL.md` §Phase 4 — the rollback walk, run when a promote is reverted
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-write.md` — state-write helper API
