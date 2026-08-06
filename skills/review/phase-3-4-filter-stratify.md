# /geniro:review — Phase 3 & Phase 4

Phase bodies for `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md`. Read on entry to Phase 3.

## Contents

- Phase 3 — Filter & aggregate
  - 3.1 Orchestrator-side dedup + convergence
  - 3.2 Mechanical+LLM dedup
  - 3.3 KEEP/FILTER judgment
- Phase 4 — Stratification & test gate
  - 4.0 Post-spawn verification gate (declared vs actual)
  - 4.1 Multi-signal threshold filter
  - 4.2 Per-finding empirical-reproduction verification
  - 4.3 Failing-to-passing test-confirmation gate

---

## Phase 3 — Filter & aggregate

State.md `phase: filter`.

### 3.1 Orchestrator-side dedup + convergence

The orchestrator reads all per-dimension findings (Phase 2 reviewer-agent outputs + Phase 1.5 mechanical findings) and performs dedup inline — no subagent spawn:

- **Dedup key:** `path:line + finding-title` (case-insensitive title match).
- **Convergence_count:** for each dedup'd finding, count how many reviewers + mechanical checks reported the same key. Persisted as a field on the finding (consumed by Phase 5.3 auto-emit threshold).
- **Drop hallucinations:** findings without a real file:line correspondence (orchestrator verifies file exists and line is within bounds via Read; if not, drop with a `## Caveats` line citing the dropped finding). **Exception — sentinel-`File` findings** (`File: SPEC-COMPLIANCE` / `File: PR-METADATA`) are path-less by design: they cite a plan/PR fragment in `Evidence:`, not a code `file:line`. Do NOT drop them here — they are verified in Phase 4.2 against the diff instead (§4.2 path-less branch).
- **Convention context:** orchestrator reads convention files when present — CONTRIBUTING.md, ADRs at `docs/adr/`, architecture docs. These inform KEEP/FILTER decisions.

### 3.2 Mechanical+LLM dedup

Mechanical findings (Phase 1.5) and LLM findings may overlap (e.g., lint says "unused import on line 42", bugs reviewer says "dead code on line 42"). Orchestrator-inline dedup identifies overlap by dedup key, preserves the mechanical finding (deterministic) + drops the LLM's redundant entry. Convergence_count for that finding gains +1 for the mechanical contribution.

### 3.3 KEEP/FILTER judgment

After dedup, the orchestrator synthesizes per finding: weighs convention-alignment, over-engineering, and pattern-frequency evidence against severity and judges KEEP / FILTER. CRITICAL findings with `safety_override=true` are always KEEP regardless of convention evidence. Pass only KEEP findings to Phase 4. FILTERED appear in the report's `## Filtered` section with reason annotation.

**Intent reconciliation** runs here as part of the per-finding judgment: a finding a reviewer tagged `[ALIGNS-WITH-PLAN]` (or `[DIVERGES-FROM-PLAN]` where the plan authorized the divergence) is demoted to decision-type `[INTENT-CHECK]` rather than kept as a bug. `[PRE-EXISTING]` convention/build findings are demoted the same way. Cite the plan frontmatter or section that authorizes the divergence on the demoted finding so the user can re-elevate.

No external agent to fail — dedup and judgment run in orchestrator's main context.

---

## Phase 4 — Stratification & test gate

State.md `phase: stratify`.

### 4.0 Post-spawn verification gate (declared vs actual)

Before stratification fires, run two declared-vs-actual checks.

**4.0a Mechanical pre-pass declaration check.** Assert state.md frontmatter `mechanical_prepass_attempted` (§1.5.7) exists and carries an outcome for each of `lint`, `schema`, `secret` in `{findings, clean, error}` — `clean` is a pass, not a gap: a green lint or type-check produces no finding and no `## Errors` entry by design, and reading that absence as a miss would fire this gate on every healthy diff. Corroborate the two outcomes that leave a trace: `findings` against the finding list, `error` against its `## Errors mechanical-prepass-<id>` entry. A missing `mechanical_prepass_attempted` declaration means the pre-pass was skipped wholesale (a TS-dominated diff that ran no lint and no `tsc` is the documented live miss); a check absent from the map means it was never reached; an uncorroborated outcome means the record and the run disagree. Each is a contract miss: append `## Errors mechanical-prepass-incomplete: declared=<...> missing-outcome=<...>` and surface it in the Phase 6 report `## Caveats`; this is advisory (the pre-pass is fail-open by design and LLM reviewers still ran), so do NOT block — record the gap so the user knows the cheap-deterministic layer was thin this run.

**4.0b Spawn-batch completeness check.** Verify the Phase 2 parallel batch actually delivered every dimension declared in §2.2, with exactly one spawn per dimension:

```
declared = state.md frontmatter spawn_dims_declared
actual   = set of dimensions whose reviewer-agent emitted a structured result in Phase 3
fired    = the `fired=` count on the `## Tool log` "[Phase 2 spawn batch]" entry (§2.3.2)

missing = declared − actual
```

On the standard single-pass path a missing `[Phase 2 spawn batch]` entry is drift, not a pass: §2.3.2 records it precisely so this check survives a compaction-resume into `phase: stratify`. Treat it like an absent declaration — append `## Errors phase-2-spawn-batch-record-missing` and fall back to `fired = |actual|`, which can only detect under-fire. In deep mode the entry is absent by design — §2.3.2's batch never fires — so skip this branch along with the `fired` comparison below; `missing` still computes.

`fired` must equal `spawn_dims_count` on the standard single-pass path, in both Standard and Batched payload shape; in deep mode the Workflow's 3 angle-passes per declared dimension are checked per `${CLAUDE_PLUGIN_ROOT}/skills/review/deep-mode-reference.md` §2, not by this count. `fired` above the declared count means per-file-batch multiplication (forbidden by §2.3.2); below it means dropped dimensions. Each mismatch direction routes through its matching branch below.

A `spawn_dims_declared` list that does not exist in frontmatter at this point is itself a contract miss, not a pass: §2.2 writes it BEFORE the parallel batch precisely so this gate has a baseline — if it appears only at persist time (written ~after the spawns), the gate it powers ran inert against a missing baseline. Treat an absent or first-seen-at-persist `spawn_dims_declared` as drift: append `## Errors phase-2-spawn-declaration-missing` and reconstruct `declared` from the §2.1 grid (and `spawn_dims_count` as its length) for THIS run before computing `missing`.

If `missing` is non-empty, or `fired < spawn_dims_count` (under-fire — dropped dimensions):

1. Append a `## Errors` body entry: `phase-2-spawn-incomplete: declared=<...> actual=<...> missing=<...> fired=<N>`.
2. Render the round summary to chat first — declared vs returned reviewers, with the missing set in plain-English dimension names — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering, then fire a lean `AskUserQuestion` with header `"Review incomplete"`:
   - A) `"Re-run the missing reviewers now"` — issue `Agent(...)` per missing dim; once results land, recompute `actual` and re-verify. (Recommended)
   - B) `"Skip the missing reviewers and continue"` — append to body `## Accepted Gaps`; continue to §4.1.
   - C) `"Abort review"` — terminal `phase: aborted`; `## Termination reason: spawn-batch-incomplete (<missing>)`.

If `fired > spawn_dims_count` and `missing` is empty (over-fire — every declared dimension returned, but extra reviewer spawns fired, e.g. per-file-batch multiplication):

1. Append a `## Errors` body entry: `phase-2-spawn-overfire: declared=<list> fired=<N>`.
2. Render fired-vs-declared to chat first — how many reviewer agents ran vs how many review dimensions were declared, in plain English — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering, then fire a lean `AskUserQuestion` with header `"Extra reviewers ran"`:
   - A) `"Continue — dedup findings across the extra spawns"` — treat the extra spawns' findings as additional §3.1 dedup inputs; continue to §4.1. (Recommended)
   - B) `"Abort review"` — terminal `phase: aborted`; `## Termination reason: spawn-overfire`.

Always-WAIT on both gates — an empty answer signals an upstream tool bug; fall back to plain text and re-ask rather than auto-defaulting, because silently skipping missing reviewers (or silently absorbing extra ones) hides a gap the user never consented to.

When `missing` is empty and `fired == spawn_dims_count`, proceed directly to §4.1.

### 4.1 Multi-signal threshold filter

`severity ≥ MEDIUM` is necessary but NOT sufficient. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §5 at Phase 4 entry, echoed per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — unread, the admission gate silently degrades to the very threshold this sentence calls insufficient, and admitted findings carry no record of which signals cleared them — §5 ONLY, located via the file's Contents block, not the whole file: §§1-4 and §6 are the reviewer-side rubric every Phase 2 spawn already consumed, and nothing orchestrator-side binds on them — and apply its gate as written. That file is the canonical home of the four admission signals, the MEDIUM-requires-signal-#2 constraint, the `risk-tier: high` relaxation of the confidence fallback, and the Path-B verification split, and it stays authoritative if any threshold changes. Convergence + evidence-grounding are documented as more reliable than LLM self-confidence (rationale: same file §4). The rest of this section is what is local to /geniro:review's Phase 4.

**Path A — severity-gated.** Survivors admit to Phase 5 stratify into `## Findings`, and to the Phase 4.2 verifier.

- Signal #1's `convergence_count` is the value set during §3.1 dedup.
- Signal #2's "properly formatted" is a mechanical check at §4.1 entry against each finding's `Evidence:` field (false on missing): an Evidence-Block fence OR a file:line pattern + ≥2 quoted lines per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` — OR, for a sentinel-`File` finding (`File: SPEC-COMPLIANCE` / `File: PR-METADATA`, path-less by design), a verbatim quoted plan/PR fragment in `Evidence:` (a fenced quote or ≥2 quoted lines) standing in for the code citation these dimensions structurally lack. The orchestrator does NOT re-read the cited file — the Phase 4.2 verifier handles that for every §4.1 survivor.
- A sentinel-`File` MEDIUM therefore satisfies the MEDIUM-requires-signal-#2 constraint through that quoted-fragment form, and reaches the Phase 4.2 path-less verifier rather than being deferred.

**Path B — decision-type orthogonal** (`Decision Type == PRODUCT-DECISION`, any severity). Every Path-B finding lands in `## Findings` with its `File: path:lines` anchor — so the open-decision gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3) fires and, on a Post, it inline-comments to its line — carrying `step0_status: pending`. Per the §5 verification split, a LOW carries no `Validation`/verification fields (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` § Verification fields — presence rules); a MEDIUM-or-higher enters Phase 4.2 and verifies against that anchor like any other survivor.

**DEFER** — a finding clearing neither path is written to `## Deferred — sub-threshold` per the deferred-entry schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §2.6. Deferred entries are excluded from PR comments and the fix list BY DEFAULT, with two user-elected exits — the Post drill (review-handoff.md §7) and the include-deferred gate (review-handoff.md §4.6) — and they never populate `open_questions[]`. (A LOW `PRODUCT-DECISION` is kept via Path B, never deferred.)

The admission gate is unchanged for repeat findings — an unchanged repeat is still ADMITTED; its `repeat-of-prior-round` marker feeds presentation only, never admission (full contract: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §7 Repeat-finding presentation).

### 4.2 Per-finding empirical-reproduction verification

Every kept CRITICAL / HIGH / MEDIUM finding from Phase 4.1 — each Path-A survivor, plus any Path-B `PRODUCT-DECISION` at those severities — is verified by a fresh `finding-verifier-agent` spawn — in standard mode, survivors citing the same file share one spawn at the cluster size defined in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4 (solo and sentinel-`File` findings spawn singly), all clusters fired as a parallel batch in a single assistant turn, with one independent verdict per finding. No tier-scaling, no severity-scaling — every finding kept at these severities is verified regardless of `risk-tier`. When `deep-mode: true`, each survivor gets a signal-gated verification — one verifier, escalating to a 3-vote majority only where the call is contested or high-stakes; escalation triggers, abstain rule, and quorum fail-safe are canonical at `${CLAUDE_PLUGIN_ROOT}/skills/review/deep-mode-reference.md` §3 (the per-verifier contract is unchanged — only the vote count differs). A LOW `PRODUCT-DECISION` admitted by §4.1 Path B alone carries no Evidence-Block to re-read and routes to the open-decision gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3) rather than defect-confirmation — so it skips this step; a Path-B admission at MEDIUM or higher is verified here like any other survivor (§4.1 Path B). The §4.1 multi-signal gate already constrains the Path-A survivor set to findings with Evidence-Block-grade citations (signal #2 mandatory for MEDIUM per §4.1; Loop Invariant #6 mandates Evidence at every kept severity), so every code-anchored survivor has a concrete file:line for the verifier to re-read; a Path-B MEDIUM+ may carry only its `File: path:lines` anchor, which the verifier reads the same way. The two sentinel-`File` dimensions (`SPEC-COMPLIANCE` / `PR-METADATA`) are path-less by design and verify against the diff instead of a code slice — see the path-less branch below.

For each cluster, the orchestrator reads the cited file once (each member's slice window) plus caller and test-dir grep context at the caps defined in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2 (the canonical home for the slice/grep sizes — not restated here so they cannot drift), then composes a `finding-verifier-agent` spawn carrying ONLY the cluster's finding bodies + shared slice + grep outputs (NOT the full reviewer bundle — isolation from the originating reviewer's framing prevents anchoring). All verifier spawns fire in ONE assistant response — `subagent_type="geniro:finding-verifier-agent"`, OMIT `model=`; registration failures follow the deferred-ladder rule in SKILL.md §Subagent model tiering. In that SAME response — welded like the §2.3.1 spawn echo, never a separate turn — emit:

> Verifying <F> findings with <S> independent checks (grouped by file).

**Path-less sentinel findings (`File: SPEC-COMPLIANCE` / `File: PR-METADATA`).** No code `path:line`, so no code slice — the orchestrator composes the verifier spawn from the finding body (its `Evidence:` quotes the spec/PR fragment verbatim), the PR's changed-file list, and any real code `file:line` embedded in the Evidence; the verifier confirms/refutes against the diff and the cited fragment. Full contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2.

Each verifier emits: `validation: confirmed | refuted | clarified`, `recommended_action: fix-now | testable | product-decision | intent-check | drop`, `confidence: 1-5`, `evidence: "<file:line quote>"`.

Aggregation:
- `refuted` findings move to `## Filtered`. Do NOT propagate to §4.3 F→P gate, Phase 5 stratify, or T2 handoff.
- `clarified` findings keep severity but update `decision-type` to the verifier's `recommended_action`; verifier confidence and evidence append to the finding body.
- `confirmed` findings retain decision-type; verifier confidence and evidence append.
- A verifier that fails to spawn or returns nothing parseable (after the registration ladder + one retry) → the finding takes `Validation: unverified` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4.5 — kept in the report (fail-open), excluded from the PR post set, surfaced under `## Caveats`.

A `refuted` verdict on a CRITICAL is high-impact (the finding drops out of the handoff entirely). The verifier contract requires a literal quote from the cited file showing the defect is NOT present (paraphrased "looks fine" is insufficient). See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §6 for the anti-sycophancy guard.

Full prompt template, isolated-context contract, anti-sycophancy guard, and worked examples: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md`.

### 4.3 Failing-to-passing test-confirmation gate

**Full contract:** `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-4-3-test-gate-reference.md`.

Summary:
- Filter findings by decision-type per the runtime-behavior classification rule.
- **Mandatory user-approval gate before any `adversarial-tester-agent` spawn.** Do not spawn without approval — the gate is the load-bearing safety property, since an unapproved spawn authors tests the user never asked for. Persist to `approvals[]` with category `test_gate_choice`.
- The gate fires whenever eligible findings exist — never bypassed, never deferred to end-of-run. When the eligible set is empty, Phase 4.3 is skipped entirely with no AUQ.
- Spawn ONE adversarial-tester-agent with eligible findings as hypothesis seeds. Orchestrator's independent re-run IS the gate; never trust the agent's red/green claim alone.
- Demote-don't-delete: green tests demote findings to `## Filtered` with `[CHALLENGED-BY-TEST]` tag; original severity preserved for re-elevation.
- Fail-open: agent failures surface "test-gate fail-open" under `## Caveats` + write `## Errors` entry.

---
