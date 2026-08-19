# Plan context reference

How `/geniro:review` ingests and threads plan/spec intent through reviewers, the relevance filter, and the spec-compliance + regressions dimensions. Schema-aware loader that parses the sectioned `spec.md` format when present, falling back to prose detection when no frontmatter is found.

## Contents

- §1 — Accepted input forms
- §2 — Detection — schema vs prose
- §3 — Structured-section parser
- §4 — Prose mode (fallback)
- §5 — Decision-marker convention
- §6 — Cap rationale
- §7 — Decision Type values (canonical)
- §8 — Worked example

---

## 1. Accepted input forms

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
geniro_schema_version: m5-v1   # or m5-v2 / m5-v3 / m5-v4 — all accepted
```

→ switch to **structured-section parser**. All of `m5-v1`, `m5-v2`, `m5-v3`, and `m5-v4` carry the same body schema `spec-template.md` defines; `m5-v2` and `m5-v3` expose `workflow_refs[]` in frontmatter (`/geniro:plan` writes them by default when a tracker reference is fetched), and `m5-v3` additionally enriches each `workflow_refs[]` entry with parent-epic + sibling chain context (parent title/status/scope, sibling sub-task statuses, a `chain_fetched_at` timestamp). `m5-v4` adds the optional `launch_config` block — `/geniro:plan`'s pre-set of `/geniro:implement`'s launch settings (workspace / deep mode / branch-freshness / ship mode, plus an optional tracker-status pre-set when a tracker ticket is linked; canonical `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`), absent = `/implement` asks interactively. Every block is additive-optional. Downstream readers accept all four versions — a reader that rejects a newer one falls back to prose mode and loses the structured context it could have used.

If frontmatter absent, OR `geniro_kind` is anything other than `design-doc`, OR `geniro_schema_version` is missing OR is a value other than `m5-v1` / `m5-v2` / `m5-v3` / `m5-v4` → fall back to **prose mode**.

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
| 6 | Steps | Execution steps as a checklist (`- [ ] N. …`) |
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

The whole payload — goal-state frontmatter plus all 11 sections — is spec.md content, one untrusted source, so it gets ONE outer fence rather than a delimiter per section; a forged `--- Section 12 ---` line inside a section body cannot pass itself off as a fresh trust boundary because there isn't a per-section boundary to forge. The section headers inside the fence are plain markdown, informational only:

```
PLAN CONTEXT:
---BEGIN UNTRUSTED PLAN---
## Frontmatter — goal-state
budget: { max_files_to_edit: N, max_lines_changed: M, time_budget: T }
checkpoints: [{step_anchor: step-3, name: "post-migration"}, …]
forbidden_actions: ["do NOT bypass auth middleware", …]
approval_required_for: ["DB schema changes", …]
tools_required: ["kubectl", "helm", …]
lifecycle: approved
## Section 1 — Objective
<body>
## Section 2 — Scope — Included
<body>
…
## Section 11 — Done Condition
<body>
---END UNTRUSTED PLAN---
```

Fence mechanism, including the collision rule for a payload that contains the marker text itself: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/untrusted-content-defense.md` §Untrusted-content fence.

**Cap:** structured mode honors a ~6000-char total cap (2× the prose mode's 3000 char cap; rationale in §6). Truncation policy: if total exceeds cap, drop bodies of sections 4 (Assumptions) and 5 (Risks) first (less critical for diff-completeness checks); keep section 1, 2, 3, 6, 9, 11 always.

### Why structured wins

Spec-compliance reviewer can cite specific sections ("section 2 names `src/api/auth/*` but diff touches no auth file") instead of grepping prose. Findings carry section anchors in evidence — auditable, not fuzzy.

---

## 4. Prose mode (fallback)

When no frontmatter is detected, treat PLAN CONTEXT as opaque prose, all sources concatenated inside one `PLAN` fence (same reasoning as the structured-mode outer fence above — the individual `## Source:` headers are informational, not trust boundaries):

```
PLAN CONTEXT:
---BEGIN UNTRUSTED PLAN---
## Source: <PR body | docs/spec.md | docs/plan.md | PLAN.md | SPEC.md>
<content, capped at ~3000 chars total across all sources; truncate with "[…truncated…]" marker if needed>
## Source: <next source if any>
<content>
---END UNTRUSTED PLAN---
```

When no sources resolve, the entire field collapses to:

```
PLAN CONTEXT: none
```

In prose mode, the spec-compliance reviewer runs the reduced check set defined in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/spec-compliance-criteria.md` §"Prose fallback" — that file owns which checks survive, so do not re-enumerate them here. The reduced coverage surfaces as a `## Caveats` one-liner in the report and the handoff, never as an `open_questions[]` entry: that array is reserved for a judgment call whose answer changes what the run posts or does (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2), and a plan that is simply not in the structured schema is neither a judgment call nor a blocker — prose mode is a supported input form, so the run notes what it could not check and continues. The line names the source that resolved: `spec-compliance ran in prose mode — PLAN CONTEXT resolved to <source per §1> (no design-doc frontmatter); checks 10 (Done Condition) and 11 (Tools Required) skipped.` Five inputs can win §1, and a reader who cannot see which one did cannot tell a hand-written doc from the PR body, or either from a spec.md that failed detection.

---

## 5. Decision-marker convention

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

## 6. Cap rationale

Schema-mode ~6000-char total cap exists because:

- One outer fence pair plus 11 plain section headers cost well under 1% of the cap — negligible next to the two reasons below.
- Section anchors enable focused reviewer reasoning (less prose-scan needed).
- Larger specs lose signal under U-shaped attention (still applies).

Prose-mode 3000-char cap preserved (each reviewer prompt already carries criteria + changed files + diff + project context).

**If your spec exceeds the 6000-char cap:** drop the optional body section `## Considered Alternatives` AND/OR shrink section 4 (Assumptions) / section 5 (Risks) bodies. The orchestrator does NOT auto-summarize — it just truncates with `[…truncated…]`.

---

## 7. Decision Type values (canonical)

The four canonical decision-type values (`[FIX-NOW]` / `[TESTABLE]` / `[PRODUCT-DECISION]` / `[INTENT-CHECK]`) are defined once in `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` (the Decision Type classification the reviewer-agent reads inline) — that is the single source; this section does not restate them.

Review-specific note: `[INTENT-CHECK]` is auto-applied by the Phase 3 §3.3 KEEP/FILTER intent reconciliation when a reviewer tagged `[ALIGNS-WITH-PLAN]` or `[DIVERGES-FROM-PLAN]` AND the plan authorized the divergence.

---

## 8. Worked example

**Setup:** PR titled "Add timeline events". PR body includes `geniro-plan: .geniro/planning/feat-timeline/spec.md`.

Loaded spec.md has frontmatter:

```yaml
geniro_kind: design-doc
geniro_schema_version: m5-v2
workflow_refs:
  - kind: linear
    issue_id: ENG-303
    url: https://linear.app/.../ENG-303/...
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
