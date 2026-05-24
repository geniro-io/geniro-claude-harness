# Plan Context Reference (M6)

How `/geniro:review` ingests и threads plan/spec intent through reviewers, the relevance filter, и the spec-compliance dimension. Schema-aware loader that parses М5's 10-section `spec.md` format when present, falling back к prose detection when no M5 frontmatter is found.

---

## 1. Accepted Input Forms

The orchestrator collects PLAN CONTEXT from up to four sources, в this **priority order**:

1. **`--plan <path>` flag** (`$ARGUMENTS`) — explicit path к а spec.md / plan.md / design-doc file. Highest priority. Example: `review HEAD~5..HEAD --plan .geniro/planning/feat-auth/spec.md`.
2. **PR body M5-reference** — когда in PR mode, scan the PR body для а `geniro-plan: <path>` line (а convention emitted by `/plan` Phase 9 hand-off message). If found, treat as а pointer к the on-disk spec.md.
3. **Auto-discovered M5 spec.md** — walk `.geniro/planning/*/spec.md`. First match wins (most-recently-modified preferred).
4. **Auto-discovered project files** — `docs/spec.md`, `docs/plan.md`, `PLAN.md`, `SPEC.md`. Skipped silently if absent.
5. **PR body as opaque prose** — когда PR mode but no `geniro-plan:` reference found, fall back к `gh pr view <ref> --json body` content treated as prose.
6. **None** — no PR body, no `--plan`, no project files. PLAN CONTEXT renders as the literal string `none` в every reviewer prompt.

**Concatenation rule (M6 refinement):** when ≥1 source resolves к а structured M5 spec.md (frontmatter detected — see §2), that source's structured-section blob is the canonical PLAN CONTEXT. Other sources (if any) are dropped — section-tagged structured blob и prose blob do not mix cleanly. When NO source has M5 frontmatter, the prose concat behavior runs: non-empty sources concatenated с source-delimiter, capped at ~3000 chars total.

---

## 2. Detection — М5 schema vs prose

Read the first 20 lines of the candidate file. If frontmatter contains:

```yaml
geniro_kind: design-doc
geniro_schema_version: m5-v1
```

→ switch к **structured-section parser** (§3).

If frontmatter absent, OR `geniro_kind` is anything other than `design-doc`, OR `geniro_schema_version` is missing → fall back к **prose mode** (§4).

---

## 3. Structured-section parser (М5 mode)

When М5 frontmatter detected, parse the 10 named sections per М5 §17.2. Section header format is rigid (`## 1. Objective` через `## 11. Done Condition` — 10 sections numbered 1-11, since §3 is split into 3a/3b would be N/A; the spec template emits 11 numeric headers за 10 logical sections per the M5 spec-template).

Sections expected:

| # | Header text | Body purpose |
|---|---|---|
| 1 | Objective | One-sentence goal statement (P-M5-4 check #1 `single_objective`) |
| 2 | Scope — Included | Bullet list of files/modules/surfaces touched |
| 3 | Scope — Excluded | Bullet list of explicitly-out-of-scope items |
| 4 | Assumptions | Conditional preconditions |
| 5 | Risks | Risks + mitigations |
| 6 | Steps | Numbered execution steps |
| 7 | Tools Required | CLI binaries / libraries / MCP connectors needed |
| 8 | Approval Points | Where mid-execution AUQ fires |
| 9 | Validation | Test types / manual verification |
| 10 | Rollback-Recovery | How к undo |
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
PLAN CONTEXT (M5 schema mode):
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

**Cap:** structured mode honors а ~6000-char total cap (2× the prose mode's 3000 char cap, since the section-tagged format adds delimiter overhead и the reviewer benefits от section anchors). Truncation policy: if total exceeds cap, drop bodies of sections 4 (Assumptions) и 5 (Risks) first (less critical для diff-completeness checks); keep section 1, 2, 3, 6, 9, 11 always.

### Why structured wins

Spec-compliance reviewer can cite specific sections («section 2 names `src/api/auth/*` но diff touches no auth file») instead of grepping prose. Findings carry section anchors в evidence — auditable, не fuzzy.

---

## 4. Prose mode (fallback)

When no М5 frontmatter is detected, treat PLAN CONTEXT as opaque prose:

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

In prose mode, spec-compliance reviewer runs checks 1-9 only (skips checks #10 Done Condition + #11 Tools Required — see `spec-compliance-criteria.md` prose fallback). Surface а one-line note в `## Open Questions`: «PLAN CONTEXT lacks M5 schema — falling back к prose checks; Done Condition + Tools Required не verified».

---

## 5. Decision-Marker Convention

Project plans commonly label decisions с markers like `D-XX:` or `[D09]`. Reviewers should treat any line beginning с such а marker as an authoritative intent statement. This applies в both М5 mode (markers may appear в any section body) и prose mode.

**Example marker line в а plan:**

```
D-09: existing timeline entries are NOT backfilled.
```

When а reviewer encounters а finding like "missing backfill for old timeline rows," it must:

- Tag the finding `[ALIGNS-WITH-PLAN-D-09]` (preserve the decision ID в the tag для traceability)
- NOT report it as а bug

When а reviewer encounters а finding that contradicts а marker (e.g., the plan says "use COALESCE" но the code uses raw NULL), it must:

- Tag the finding `[DIVERGES-FROM-PLAN-D-XX]`
- The Phase 4 judge Step 0 reconciliation will then verify и either keep as а bug или auto-demote к `[INTENT-CHECK]`.

---

## 6. Cap Rationale

М5-mode ~6000-char total cap exists because:

- Section-tagged format adds delimiter overhead (~10% of total).
- Section anchors enable focused reviewer reasoning (less prose-scan needed).
- Larger M5 specs lose signal под U-shaped attention (still applies).

Prose-mode 3000-char cap preserved (each reviewer prompt already carries criteria + changed files + diff + project context).

**If your М5 spec exceeds the 6000-char cap:** drop frontmatter `## Considered Alternatives` (optional М5 section) AND/OR shrink section 4 (Assumptions) / section 5 (Risks) bodies. The orchestrator does NOT auto-summarize — it just truncates с `[…truncated…]`.

---

## 7. Decision Type values (canonical)

The four canonical decision-type values, shared с `agents/reviewer-agent.md`:

- `[FIX-NOW]` — Mechanical correction, obvious target, low risk (e.g., test title vs assertion mismatch, typo, broken cross-reference).
- `[TESTABLE]` — Defense-in-depth or edge case worth а test before action (e.g., empty-string guard, boundary case).
- `[PRODUCT-DECISION]` — Multiple valid resolution paths; needs human triage (e.g., snapshot vs live-fetch trade-off, COALESCE vs CHECK vs catch+log).
- `[INTENT-CHECK]` — Looks like а divergence от explicit plan; verify against spec before treating as bug. Auto-applied by Phase 4 Step 0 when а reviewer tagged `[ALIGNS-WITH-PLAN]` или `[DIVERGES-FROM-PLAN]` AND the plan authorized the divergence.

---

## 8. Worked Example (М5 mode)

**Setup:** PR titled "Add timeline events". PR body includes `geniro-plan: .geniro/planning/feat-timeline/spec.md`.

Loaded spec.md has frontmatter:

```yaml
geniro_kind: design-doc
geniro_schema_version: m5-v1
budget:
  max_files_to_edit: 5
  max_lines_changed: 300
forbidden_actions: ["do NOT backfill existing timeline rows"]
lifecycle: approved
```

Section 1 (Objective): «Add а timeline-events table с insert path.»
Section 2 (Scope — Included): «`migrations/2026-04-add-timeline.sql`, `src/timeline/events.ts`, `tests/timeline.test.ts`»
Section 11 (Done Condition): «all 5 acceptance tests green AND telemetry shows ≥1 successful event insert»

Three reviewer findings come back:

1. **Bugs reviewer:** "Missing backfill для existing rows в `migrations/2026-04-add-timeline.sql`. Old data won't appear в the timeline UI."
2. **Architecture reviewer:** "Timestamp column lacks `WITH TIME ZONE` в `schema/events.sql:14`. Recommend `TIMESTAMPTZ` для portability."
3. **Spec-compliance reviewer (Check #10):** "Done Condition (section 11) names «telemetry shows ≥1 successful event insert» но diff carries no metric emission. Add `metrics.increment('timeline.event.insert')` at the writer."

**Reviewer self-tagging (Phase 2):**

- Finding 1 — reviewer sees `forbidden_actions: ["do NOT backfill"]` в frontmatter, tags `[ALIGNS-WITH-PLAN]` (intentional, not а bug). Routed к `[INTENT-CHECK]` decision-type, not bug severity.
- Finding 2 — no plan reference. Untagged, regular review path.
- Finding 3 — spec-compliance finding с section 11 anchor, severity HIGH (per spec-compliance-criteria.md §11 Severity Tagging).

**Phase 4 Step 0 reconciliation (judge):**

- Finding 1 — already `[ALIGNS-WITH-PLAN]`, exits the bug pipeline; appears в the report как `[INTENT-CHECK]` с the frontmatter citation (`forbidden_actions[0]`), not в CRITICAL/HIGH.
- Finding 2 — no plan tag, normal severity scoring → `[TESTABLE]` или regular bug-severity per rubric.
- Finding 3 — spec-compliance dimension; severity HIGH preserved.

**Net result:** the report calls out one `[INTENT-CHECK]` item (frontmatter-authorized backfill skip), one regular bug, и one HIGH spec-compliance finding с section-11 citation. Zero false bug reports against the explicit plan.
