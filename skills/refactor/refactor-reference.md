# Refactor — Detailed Reference

Detail sections extracted from `skills/refactor/SKILL.md` to keep the main skill body lean. The orchestrator reads this file when SKILL.md references one of the sections below by name.

## Contents

1. State machine — full ASCII diagram
2. State file schema — frontmatter + body sections
3. Phase 3 reviewer-agent spawn template

---

## 1. State machine — full ASCII diagram

state.md `phase:` enum transitions:

```
[entry] → plan ──┬── apply ──┬── verify ──┬── done
│ │ │
│ │ └── verify-summary-only (terminal — see verify-escalated branch)
│ │
│ └── apply-escalated ──┬── verify (keep what worked → partial-application note)
│ ├── reverted (terminal — "Revert all changes")
│ └── aborted (terminal)
│
└── plan-escalated ──┬── plan (user supplies missing context)
├── aborted (terminal)
└── routed (terminal — hard signal "Escalate")

verify ──┬── (happy: → done above)
│
└── verify-escalated ──┬── apply ("Run /implement" on PRODUCT-DECISION → exit /refactor)
├── reverted (terminal — "Revert this refactor")
├── verify-summary-only (terminal — "Document and ship as-is" → deferred-decision note)
└── adr-documented (terminal — "Document as ADR")
```

**Terminal states:** `done`, `verify-summary-only`, `reverted`, `aborted`, `routed`, `adr-documented`. The SessionStart recovery treats all six as "task complete — no resume needed".

**Non-terminal states:** `plan`, `apply`, `verify`. The recovery rolls these back to phase-entry and re-runs (idempotent — `approvals[]` ensures HIGH-step + PRODUCT-DECISION gates skip already-answered).

**Escalation states:** `plan-escalated` (hard signal OR baseline red), `apply-escalated` (≥30% blocked), `verify-escalated` (PRODUCT-DECISION or 1-round fix-loop exhausted). The recovery surfaces these to the user as "task was paused — last AUQ options:" so the user re-picks without losing context.

The `## Termination reason` body section is written on `aborted` / `reverted` / `routed` terminals.

---

## 2. State file schema

### state.md (T1 — session-bound, `.geniro/state/refactor/<slug>/state.md`)

Frontmatter:

```yaml
---
tier: T1
producer: refactor
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
phase: <enum per State Machine above>
status: <in-progress|done|failed>
non-resumable-actions: []                 # typically empty — refactor ships no commits
approvals: []                             # categories: refactor_high_step, refactor_product_decision
geniro_kind: refactor-state
geniro_schema_version: m8-v1
effort_tier: <Trivial|Small|Medium|Big>
task_slug: <slug>
worktree: <abs-path>
---
```

Body sections:

- `## Scope` — files + symbols in refactor scope
- `## Baseline` — Evidence Block from Phase 1 §1.2 step 5 (test count + pass status)
- `## Smells Detected` — (Medium+) orchestrator-inline output from Phase 1 §1.4
- `## Plan` — ordered steps + risk + consumer counts + KEEP/FILTER decisions
- `## Apply Summary` — executed / blocked / final-suite status
- `## Accepted Blocks` — (optional, path "Keep what worked")
- `## Review Findings` — (Medium+, after Phase 3) CRITICAL/HIGH/MEDIUM lists
- `## Persisted approvals` — render of frontmatter `approvals[]`
- `## Tool log` — selective logging (reviewer + custom reviewer spawns, escalations; smell detection and per-step execution log to `## Plan steps`)
- `## Errors`
- `## Open Questions` (escalation AUQs + outcome)
- `## Termination reason` (only on terminal `aborted` / `reverted` / `routed` states)

**No handoff file**: diff IS the deliverable; working tree is the channel.

---

## 3. Phase 3 reviewer-agent spawn template

For Medium and Big: spawn a fresh reviewer-agent. The agent reads its own criteria — do NOT pre-read into orchestrator context. Pre-inline content the loader echoed: `code-style.md` content under `## Code-style instructions`. Omit when the loader echoed `No code-style.md found — skipping.`

```
Agent(subagent_type="reviewer-agent", prompt="""
## Review: Refactor Diff
This is a refactor — behavior MUST be unchanged. CI already passed. Focus on invariants, not style.

WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]

DIFF: [paste git diff output]
PLAN-STEPS REPORT: [paste state.md `## Plan steps` rows with final status]
PROJECT CONVENTIONS: [paste relevant conventions from CLAUDE.md]

## Code-style instructions
[content here]

## Focus Areas
- Accidental public-API changes
- Test assertion mutations (imports-only changes are fine; assertion changes are NOT)
- Invariant drift (error shapes, return types, null-vs-undefined, ordering)
- New coupling introduced by extraction/move
- Dead-code removal that actually had references

## Review Criteria
Read and apply these criteria files:
- `${CLAUDE_PLUGIN_ROOT}/skills/review/bugs-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/architecture-criteria.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/review/tests-criteria.md`

Report findings with severity (CRITICAL/HIGH/MEDIUM) and confidence. Return findings as evidence. Do NOT emit an overall verdict — the orchestrating skill synthesizes findings and decides disposition.

Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call.
""", description="Review: refactor diff")
```

**Custom reviewers (Medium and Big only — same gate):** First, resolve `PRIMARY_ROOT` by running the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` via Bash — the helper requires the slot in scope to dual-glob local + main-worktree `review-extra/` files, and a linked worktree's `.geniro/instructions/` is gitignored and may be empty. Then apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` to discover user-authored review dimensions in `.geniro/instructions/review-extra/`. For each spawn-spec returned, append one additional `Agent(subagent_type="reviewer-agent",...)` to the SAME parallel batch as the independent reviewer above — same assistant response, parallel execution. The helper's `paths:` filter uses the refactor's changed-files list. Custom-reviewer findings flow through the same orchestrator disposition logic as independent-reviewer findings. If the helper aborts on hard-cap error, surface error + skip; do not proceed with review.
