# Plan Context Reference

How `/geniro:review` ingests and threads plan/spec intent through reviewers, the relevance filter, and the spec-compliance dimension. Schema-aware loader that parses the spec's 10-section `spec.md` format when present, falling back to prose detection when no frontmatter is found.

---

## 1. Accepted Input Forms

The orchestrator collects PLAN CONTEXT from up to four sources, in this **priority order**:

1. **`--plan <path>` flag** (`$ARGUMENTS`) — explicit path to a spec.md / plan.md / design-doc file. Highest priority. Example: `review HEAD~5..HEAD --plan .geniro/planning/feat-auth/spec.md`.
2. **PR body plan-reference** — when in PR mode, scan the PR body for a `geniro-plan: <path>` line (a convention emitted by `/plan` Phase 9 hand-off message). If found, treat as a pointer to the on-disk spec.md.
3. **Auto-discovered spec.md** — walk `.geniro/planning/*/spec.md`. First match wins (most-recently-modified preferred).
4. **Auto-discovered project files** — `docs/spec.md`, `docs/plan.md`, `PLAN.md`, `SPEC.md`. Skipped silently if absent.
5. **PR body as opaque prose** — when PR mode but no `geniro-plan:` reference found, fall back to `gh pr view <ref> --json body` content treated as prose.
6. **None** — no PR body, no `--plan`, no project files. PLAN CONTEXT renders as the literal string `none` in every reviewer prompt.

**Concatenation rule:** when ≥1 source resolves to a structured spec.md (frontmatter detected — see), that source's structured-section blob is the canonical PLAN CONTEXT. Other sources (if any) are dropped — section-tagged structured blob and prose blob do not mix cleanly. When NO source has frontmatter, the prose concat behavior runs: non-empty sources concatenated with source-delimiter, capped at ~3000 chars total.

---

## 2. Detection — schema vs prose

Read the first 20 lines of the candidate file. If frontmatter contains:

```yaml
geniro_kind: design-doc
geniro_schema_version: m5-v1   # or m5-v2 — both accepted
```

→ switch to **structured-section parser**. Both `m5-v1` and `m5-v2` carry the same 10-section body schema; `m5-v2` additionally exposes `workflow_refs[]` in frontmatter (`/plan` Impl-10 onward writes m5-v2 by default when a tracker reference is fetched). Downstream readers MUST accept either version.

If frontmatter absent, OR `geniro_kind` is anything other than `design-doc`, OR `geniro_schema_version` is missing OR is a value other than `m5-v1` / `m5-v2` → fall back to **prose mode**.

---

## 3. Structured-section parser

When frontmatter detected, parse the 10 named sections per Section header format is rigid (`## 1. Objective` through `## 11. Done Condition` — 10 sections numbered 1-11, since is split into 3a/3b would be N/A; the spec template emits 11 numeric headers beyond 10 logical sections per the spec-template).

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

In prose mode, spec-compliance reviewer runs checks 1-9 only (skips checks #10 Done Condition + #11 Tools Required — see `spec-compliance-criteria.md` prose fallback). Emit a structured `open_questions[]` entry with `source: spec-compliance`, `status: unresolved`, `question: "PLAN CONTEXT lacks structured frontmatter — checks 10 (Done Condition) and 11 (Tools Required) skipped. Confirm whether these are covered out-of-band, or upgrade the spec/design doc to the structured schema."`.

---

## 5. Decision-Marker Convention

Project plans commonly label decisions with markers like `D-XX:` or `[D09]`. Reviewers should treat any line beginning with such a marker as an authoritative intent statement. This applies in both mode (markers may appear in any section body) and prose mode.

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

---

## 6. Cap Rationale

Schema-mode ~6000-char total cap exists because:

- Section-tagged format adds delimiter overhead (~10% of total).
- Section anchors enable focused reviewer reasoning (less prose-scan needed).
- Larger specs lose signal under U-shaped attention (still applies).

Prose-mode 3000-char cap preserved (each reviewer prompt already carries criteria + changed files + diff + project context).

**If your spec exceeds the 6000-char cap:** drop frontmatter `## Considered Alternatives` (optional section) AND/OR shrink section 4 (Assumptions) / section 5 (Risks) bodies. The orchestrator does NOT auto-summarize — it just truncates with `[…truncated…]`.

---

## 7. Decision Type values (canonical)

The four canonical decision-type values, shared with `agents/reviewer-agent.md`:

- `[FIX-NOW]` — Mechanical correction, obvious target, low risk (e.g., test title vs assertion mismatch, typo, broken cross-reference).
- `[TESTABLE]` — Defense-in-depth or edge case worth a test before action (e.g., empty-string guard, boundary case).
- `[PRODUCT-DECISION]` — Multiple valid resolution paths; needs human triage (e.g., snapshot vs live-fetch trade-off, COALESCE vs CHECK vs catch+log).
- `[INTENT-CHECK]` — Looks like a divergence from explicit plan; verify against spec before treating as bug. Auto-applied by Phase 4 Step 0 when a reviewer tagged `[ALIGNS-WITH-PLAN]` or `[DIVERGES-FROM-PLAN]` AND the plan authorized the divergence.

---

## 8. Worked Example

**Setup:** PR titled "Add timeline events". PR body includes `geniro-plan:.geniro/planning/feat-timeline/spec.md`.

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
- Finding 3 — spec-compliance finding with section 11 anchor, severity HIGH (per spec-compliance-criteria.md Severity Tagging).

**Phase 4 Step 0 reconciliation (judge):**

- Finding 1 — already `[ALIGNS-WITH-PLAN]`, exits the bug pipeline; appears in the report as `[INTENT-CHECK]` with the frontmatter citation (`forbidden_actions[0]`), not in CRITICAL/HIGH.
- Finding 2 — no plan tag, normal severity scoring → `[TESTABLE]` or regular bug-severity per rubric.
- Finding 3 — spec-compliance dimension; severity HIGH preserved.

**Net result:** the report calls out one `[INTENT-CHECK]` item (frontmatter-authorized backfill skip), one regular bug, and one HIGH spec-compliance finding with section-11 citation. Zero false bug reports against the explicit plan.
