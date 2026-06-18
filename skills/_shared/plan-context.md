# Plan Context Reference

How `/geniro:review` ingests and threads plan/spec intent through reviewers, the relevance filter, and the spec-compliance + regressions dimensions. Schema-aware loader that parses the spec's 11-section `spec.md` format when present, falling back to prose detection when no frontmatter is found.

## Contents

- §1 — Accepted Input Forms
- §2 — Detection — schema vs prose
- §3 — Structured-section parser
- §4 — Prose mode (fallback)
- §5 — Decision-Marker Convention
- §6 — Cap Rationale
- §7 — Decision Type values (canonical)
- §8 — Worked Example

---

## 1. Accepted Input Forms

The orchestrator collects PLAN CONTEXT from up to five sources (item 6 is the empty fallback, not a source), in this **priority order**:

1. **`--plan <path>` flag** (`$ARGUMENTS`) — explicit path to a spec.md / plan.md / design-doc file. Highest priority. Example: `review HEAD~5..HEAD --plan .geniro/planning/feat-auth/spec.md`.
2. **PR body plan-reference** — when in PR mode, scan the PR body for a `geniro-plan: <path>` line (a manual convention — a user adds this line to the PR body to point /review at the on-disk spec.md; no skill writes it automatically). If found, treat as a pointer to the on-disk spec.md.
3. **Auto-discovered spec.md** — walk `.geniro/planning/*/spec.md`. First match wins (most-recently-modified preferred).
4. **Auto-discovered project files** — `docs/spec.md`, `docs/plan.md`, `PLAN.md`, `SPEC.md`. Skipped silently if absent.
5. **PR body as opaque prose** — when PR mode but no `geniro-plan:` reference found, fall back to `gh pr view <ref> --json body` content treated as prose.
6. **None** — no PR body, no `--plan`, no project files. PLAN CONTEXT renders as the literal string `none` in every reviewer prompt.

**Concatenation rule:** when ≥1 source resolves to a structured spec.md (frontmatter detected — see §2 Detection), that source's structured-section blob is the canonical PLAN CONTEXT. Other sources (if any) are dropped — section-tagged structured blob and prose blob do not mix cleanly. When NO source has frontmatter, the prose concat behavior runs: non-empty sources concatenated with source-delimiter, capped at ~3000 chars total.

---

## 2. Detection — schema vs prose

Read the first 20 lines of the candidate file. If frontmatter contains:

```yaml
geniro_kind: design-doc
geniro_schema_version: m5-v1   # or m5-v2 / m5-v3 — all accepted
```

→ switch to **structured-section parser**. All of `m5-v1`, `m5-v2`, and `m5-v3` carry the same 11-section body schema; `m5-v2` and `m5-v3` expose `workflow_refs[]` in frontmatter (`/geniro:plan` writes them by default when a tracker reference is fetched), and `m5-v3` additionally enriches each `workflow_refs[]` entry with parent-epic + sibling chain context (parent title/status/scope, sibling sub-task statuses, a `chain_fetched_at` timestamp). Downstream readers MUST accept all three versions.

If frontmatter absent, OR `geniro_kind` is anything other than `design-doc`, OR `geniro_schema_version` is missing OR is a value other than `m5-v1` / `m5-v2` / `m5-v3` → fall back to **prose mode**.

---

## 3. Structured-section parser

When frontmatter detected, parse the 11 named sections. Section-header format is rigid (`## 1. Objective` through `## 11. Done Condition`) — the spec template emits 11 numeric headers.

Sections expected:

| # | Header text | Body purpose |
|---|---|---|
| 1 | Objective | One-sentence goal statement |
| 2 | Scope — Included | Bullet list of files/modules/surfaces touched |
| 3 | Scope — Excluded | Bullet list of explicitly-out-of-scope items |
| 4 | Assumptions | Conditional preconditions |
| 5 | Risks | Risks + mitigations |
| 6 | Steps | Numbered execution steps |
| 7 | Tools Required | CLI binaries / libraries / MCP connectors needed |
| 8 | Approval Points | Where mid-execution AUQ fires |
| 9 | Validation | Test types / manual verification |
| 10 | Rollback-Recovery | How to undo |
| 11 | Done Condition | Observable signal of completion |

Plus the goal-state **frontmatter** block (parsed separately):

```yaml
budget:
max_files_to_edit: <int|null>
max_lines_changed: <int|null>
time_budget: <duration|null>
checkpoints: [<list of {step_anchor, name}>]
forbidden_actions: [<list>]
approval_required_for: [<list>]
tools_required: [<list>]
lifecycle: draft | approved | superseded
```

### Pre-inline schema (structured mode)

```
PLAN CONTEXT:
--- Frontmatter goal-state ---
budget: { max_files_to_edit: N, max_lines_changed: M, time_budget: T }
checkpoints: [{step_anchor: step-3, name: "post-migration"}, …]
forbidden_actions: ["do NOT bypass auth middleware", …]
approval_required_for: ["DB schema changes", …]
tools_required: ["kubectl", "helm", …]
lifecycle: approved
--- Section 1 (Objective) ---
<body>
--- Section 2 (Scope — Included) ---
<body>
…
--- Section 11 (Done Condition) ---
<body>
```

**Cap:** structured mode honors a ~6000-char total cap (2× the prose mode's 3000 char cap, since the section-tagged format adds delimiter overhead and the reviewer benefits from section anchors). Truncation policy: if total exceeds cap, drop bodies of sections 4 (Assumptions) and 5 (Risks) first (less critical for diff-completeness checks); keep section 1, 2, 3, 6, 9, 11 always.

### Why structured wins

Spec-compliance reviewer can cite specific sections ("section 2 names `src/api/auth/*` but diff touches no auth file") instead of grepping prose. Findings carry section anchors in evidence — auditable, not fuzzy.

---

## 4. Prose mode (fallback)

When no frontmatter is detected, treat PLAN CONTEXT as opaque prose:

```
PLAN CONTEXT:
--- Source: <PR body | docs/spec.md | docs/plan.md | PLAN.md | SPEC.md> ---
<content, capped at ~3000 chars total across all sources; truncate with "[…truncated…]" marker if needed>
--- Source: <next source if any> ---
<content>
```

When no sources resolve, the entire field collapses to:

```
PLAN CONTEXT: none
```

In prose mode, spec-compliance reviewer runs checks 1-9 only (skips checks #10 Done Condition + #11 Tools Required — see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/spec-compliance-criteria.md` prose fallback). Emit a structured `open_questions[]` entry with `id: spec-compliance-prose-fallback`, `source: spec-compliance`, `status: unresolved`, `question: "PLAN CONTEXT lacks structured frontmatter — checks 10 (Done Condition) and 11 (Tools Required) skipped. Confirm whether these are covered out-of-band, or upgrade the spec/design doc to the structured schema."`.

---

## 5. Decision-Marker Convention

Project plans commonly label decisions with markers like `D-XX:` or `[D09]`. Reviewers should treat any line beginning with such a marker as an authoritative intent statement. This applies in both structured mode (markers may appear in any section body) and prose mode.

**Example marker line in a plan:**

```
D-09: existing timeline entries are NOT backfilled.
```

When a reviewer encounters a finding like "missing backfill for old timeline rows," it must:

- Tag the finding `[ALIGNS-WITH-PLAN-D-09]` (preserve the decision ID in the tag for traceability)
- NOT report it as a bug

When a reviewer encounters a finding that contradicts a marker (e.g., the plan says "use COALESCE" but the code uses raw NULL), it must:

- Tag the finding `[DIVERGES-FROM-PLAN-D-XX]`
- The Phase 3 §3.3 KEEP/FILTER intent reconciliation will then verify and either keep as a bug or auto-demote to `[INTENT-CHECK]`.

---

## 6. Cap Rationale

Schema-mode ~6000-char total cap exists because:

- Section-tagged format adds delimiter overhead (~10% of total).
- Section anchors enable focused reviewer reasoning (less prose-scan needed).
- Larger specs lose signal under U-shaped attention (still applies).

Prose-mode 3000-char cap preserved (each reviewer prompt already carries criteria + changed files + diff + project context).

**If your spec exceeds the 6000-char cap:** drop the optional body section `## Considered Alternatives` AND/OR shrink section 4 (Assumptions) / section 5 (Risks) bodies. The orchestrator does NOT auto-summarize — it just truncates with `[…truncated…]`.

---

## 7. Decision Type values (canonical)

The four canonical decision-type values (`[FIX-NOW]` / `[TESTABLE]` / `[PRODUCT-DECISION]` / `[INTENT-CHECK]`) are defined once in `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` (the Decision Type classification the reviewer-agent reads inline) — that is the single source; this section does not restate them.

Review-specific note: `[INTENT-CHECK]` is auto-applied by the Phase 3 §3.3 KEEP/FILTER intent reconciliation when a reviewer tagged `[ALIGNS-WITH-PLAN]` or `[DIVERGES-FROM-PLAN]` AND the plan authorized the divergence.

---

## 8. Worked Example

**Setup:** PR titled "Add timeline events". PR body includes `geniro-plan: .geniro/planning/feat-timeline/spec.md`.

Loaded spec.md has frontmatter:

```yaml
geniro_kind: design-doc
geniro_schema_version: m5-v2
workflow_refs:
  - kind: linear
    issue_id: CI-303
    url: https://linear.app/.../CI-303/...
    fetched_at: 2026-05-26T10:42:13Z
    status: In Progress
budget:
max_files_to_edit: 5
max_lines_changed: 300
forbidden_actions: ["do NOT backfill existing timeline rows"]
lifecycle: approved
```

Section 1 (Objective): "Add a timeline-events table with insert path."
Section 2 (Scope — Included): "`migrations/2026-04-add-timeline.sql`, `src/timeline/events.ts`, `tests/timeline.test.ts`"
Section 11 (Done Condition): "all 5 acceptance tests green AND telemetry shows ≥1 successful event insert"

Three reviewer findings come back:

1. **Bugs reviewer:** "Missing backfill for existing rows in `migrations/2026-04-add-timeline.sql`. Old data won't appear in the timeline UI."
2. **Architecture reviewer:** "Timestamp column lacks `WITH TIME ZONE` in `schema/events.sql:14`. Recommend `TIMESTAMPTZ` for portability."
3. **Spec-compliance reviewer (Check #10):** "Done Condition (section 11) names "telemetry shows ≥1 successful event insert" but diff carries no metric emission. Add `metrics.increment('timeline.event.insert')` at the writer."

**Reviewer self-tagging (Phase 2):**

- Finding 1 — reviewer sees `forbidden_actions: ["do NOT backfill"]` in frontmatter, tags `[ALIGNS-WITH-PLAN]` (intentional, not a bug). Routed to `[INTENT-CHECK]` decision-type, not bug severity.
- Finding 2 — no plan reference. Untagged, regular review path.
- Finding 3 — spec-compliance finding with section 11 anchor, severity HIGH (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/spec-compliance-criteria.md` Severity Tagging).

**Phase 3 §3.3 KEEP/FILTER intent reconciliation:**

- Finding 1 — already `[ALIGNS-WITH-PLAN]`, exits the bug pipeline; appears in the report as `[INTENT-CHECK]` with the frontmatter citation (`forbidden_actions[0]`), not in CRITICAL/HIGH.
- Finding 2 — no plan tag, normal severity scoring → `[TESTABLE]` or regular bug-severity per rubric.
- Finding 3 — spec-compliance dimension; severity HIGH preserved.

**Net result:** the report calls out one `[INTENT-CHECK]` item (frontmatter-authorized backfill skip), one regular bug, and one HIGH spec-compliance finding with section-11 citation. Zero false bug reports against the explicit plan.
