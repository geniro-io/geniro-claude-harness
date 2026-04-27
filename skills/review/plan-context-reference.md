# Plan Context Reference

How `/geniro:review` ingests and threads plan/spec intent through reviewers, the relevance filter, and the judge pass.

## 1. Accepted Input Forms

The orchestrator collects PLAN CONTEXT from up to four sources, in this **priority order**:

1. **PR body** — when in PR mode (PR ref form), `gh pr view <ref> --json baseRefName,headRefName,body,title` returns the PR title + body. Treat as the authoritative intent statement when present.
2. **Explicit `--plan <path>` flag** — passed in `$ARGUMENTS`. Example: `review HEAD~5..HEAD --plan docs/plan.md`. Reads the file content as-is.
3. **Auto-discovered project files** — checked in this order, first match wins for each filename: `docs/spec.md`, `docs/plan.md`, `PLAN.md`, `SPEC.md`. Skipped silently if absent.
4. **None** — no PR body, no `--plan`, no project files. PLAN CONTEXT is rendered as the literal string `none` in every reviewer prompt.

**Concatenation:** Non-empty sources are concatenated in the order above, each prefixed with a source delimiter (see schema below). The `--plan` flag does **not** suppress auto-discovered files — both contribute. The PR body always leads when in PR mode.

## 2. Pre-Inline Schema

The orchestrator formats PLAN CONTEXT for every reviewer prompt (5 standard + conditional design + every batched-mode variant), the relevance-filter-agent prompt, and the judge pass:

```
PLAN CONTEXT:
--- Source: <PR body | docs/spec.md | docs/plan.md | PLAN.md | SPEC.md | none> ---
<content, capped at ~3000 chars total across all sources; truncate with "[…truncated…]" marker if needed>
--- Source: <next source if any> ---
<content>
```

When no sources resolve, the entire field collapses to:

```
PLAN CONTEXT: none
```

## 3. Decision-Marker Convention

Project plans commonly label decisions with markers like `D-XX:` or `[D09]`. Reviewers should treat any line beginning with such a marker as an authoritative intent statement.

**Example marker line in a plan:**

```
D-09: existing timeline entries are NOT backfilled.
```

When a reviewer encounters a finding like "missing backfill for old timeline rows," it must:

- Tag the finding `[ALIGNS-WITH-PLAN-D-09]` (preserve the decision ID in the tag for traceability)
- NOT report it as a bug

When a reviewer encounters a finding that contradicts a marker (e.g., the plan says "use COALESCE" but the code uses raw NULL), it must:

- Tag the finding `[DIVERGES-FROM-PLAN-D-XX]`
- The Phase 4 judge Step 0 reconciliation will then verify and either keep as a bug or auto-demote to `[INTENT-CHECK]`.

## 4. Cap Rationale

The ~3000-character total cap exists because:

- Each reviewer prompt already carries criteria + changed files + diff + project context. Plan context is one more field competing for the same window.
- A typical PR body + a 1-page decision summary fits well under 3000 chars.
- Larger plan documents (multi-page specs, long ADRs) lose signal when stuffed verbatim into every reviewer prompt — the reviewer's attention spreads thin (U-shaped attention curve, see SKILL.md batched-mode rationale).

**If your plan exceeds the cap:** summarize externally (extract the decision list, drop prose) and either pass the summary via `--plan` or commit it as `docs/plan.md`. The orchestrator does NOT auto-summarize — it just truncates with `[…truncated…]`.

## Decision Type values (canonical)

The four canonical decision-type values, shared with `agents/reviewer-agent.md`:

- `[FIX-NOW]` — Mechanical correction, obvious target, low risk (e.g., test title vs assertion mismatch, typo, broken cross-reference).
- `[TESTABLE]` — Defense-in-depth or edge case worth a test before action (e.g., empty-string guard, boundary case).
- `[PRODUCT-DECISION]` — Multiple valid resolution paths; needs human triage (e.g., snapshot vs live-fetch trade-off, COALESCE vs CHECK vs catch+log).
- `[INTENT-CHECK]` — Looks like a divergence from explicit plan; verify against spec before treating as bug. Auto-applied by Phase 4 Step 0 when a reviewer tagged `[ALIGNS-WITH-PLAN]` or `[DIVERGES-FROM-PLAN]` and the plan authorized the divergence.

## 5. Worked Example

**Setup:** PR titled "Add timeline events". PR body contains:

```
Adds timeline events table + insert path.

D-09: existing timeline entries are NOT backfilled.
D-10: events use UTC timestamps without timezone column.
```

Three reviewer findings come back:

1. **Bugs reviewer:** "Missing backfill for existing rows in `migrations/2026-04-add-timeline.sql`. Old data won't appear in the timeline UI."
2. **Architecture reviewer:** "Timestamp column lacks `WITH TIME ZONE` in `schema/events.sql:14`. Recommend `TIMESTAMPTZ` for portability."
3. **Tests reviewer:** "No test for the empty-events-list rendering path in `tests/timeline.test.ts`. Should add boundary case."

**Reviewer self-tagging (Phase 2):**

- Finding 1 — reviewer sees `D-09` in PLAN CONTEXT, tags `[ALIGNS-WITH-PLAN-D-09]` (intentional, not a bug). Routed to `[INTENT-CHECK]` decision-type, not a bug severity.
- Finding 2 — reviewer sees `D-10` mandates "without timezone column," contradicts its own suggestion. Tags `[DIVERGES-FROM-PLAN-D-10]`.
- Finding 3 — no plan reference. Untagged, regular review path.

**Phase 4 Step 0 reconciliation (judge):**

- Finding 1 — already `[ALIGNS-WITH-PLAN]`, exits the bug pipeline; appears in the report as `[INTENT-CHECK]` with the plan citation, not in CRITICAL/HIGH.
- Finding 2 — `[DIVERGES-FROM-PLAN-D-10]` → judge re-reads PLAN CONTEXT, confirms `D-10` explicitly authorizes the divergence → demote to `[INTENT-CHECK]`, exclude from CRITICAL/HIGH severity.
- Finding 3 — no plan tag, normal severity scoring → ends up `[TESTABLE]` (defense-in-depth boundary case).

**Net result:** the report calls out two `[INTENT-CHECK]` items (with plan-decision citations) for human triage, plus one `[TESTABLE]` finding. Zero false bug reports against the explicit plan.
