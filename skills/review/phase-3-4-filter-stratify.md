# /geniro:review — Phase 3 & Phase 4

Phase bodies for `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md`. Read on entry to Phase 3.

**Tool surface (Phases 3-4).** Phase 3 is orchestrator-inline reading and judgment, with no spawn. Phase 4.2 spawns `finding-verifier-agent`, preceded where a claim rests on behavior outside the repo by web search / fetch for `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2.5's external-evidence pre-run. Read-only shell; `atomic_state_write` for state.md, which also materializes a still-pending brief (`phase-2-spawns.md` §2.3.2). Questions: Phase 4's declared-vs-actual gate. Nothing is written outside the run's scratch directory, and no production source is edited. The Phases 2-4 surface in full: `phase-2-spawns.md`.

## Contents

- Phase 3 — Filter & aggregate
  - 3.1 Orchestrator-side dedup + convergence
  - 3.2 Mechanical+LLM dedup
  - 3.3 KEEP/FILTER judgment
- Phase 4 — Stratification & verification
  - 4.0 Post-spawn verification gate (declared vs actual)
  - 4.1 Multi-signal admission gate
  - 4.2 Per-finding empirical-reproduction verification

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

After dedup, the orchestrator synthesizes per finding: weighs convention-alignment, over-engineering, and pattern-frequency evidence against severity and judges KEEP / FILTER. CRITICAL findings are always KEEP — a `safety_override=true` CRITICAL is never filtered on convention evidence, and (per §4.2's post-verification steering step) no CRITICAL is ever filtered on a user steering instruction either; the floor is unconditional at CRITICAL severity. Pass only KEEP findings to Phase 4. FILTERED appear in the report's `## Filtered` section with reason annotation.

**Intent reconciliation** runs here as part of the per-finding judgment: a finding a reviewer tagged `[ALIGNS-WITH-PLAN]` (or `[DIVERGES-FROM-PLAN]` where the plan authorized the divergence) is demoted to decision-type `[INTENT-CHECK]` rather than kept as a bug. `[PRE-EXISTING]` convention/build findings are demoted the same way. Cite the plan frontmatter or section that authorizes the divergence on the demoted finding so the user can re-elevate.

---

## Phase 4 — Stratification & verification

State.md `phase: stratify`.

### 4.0 Post-spawn verification gate (declared vs actual)

Before stratification fires, run two declared-vs-actual checks.

**4.0a Mechanical pre-pass declaration check.** Assert state.md frontmatter `mechanical_prepass_attempted` (§1.5.7) exists and carries an outcome for each of `lint`, `schema`, `secret` in `{findings, clean, error}` — `clean` is a pass, not a gap: a green lint or type-check produces no finding and no `## Errors` entry by design, and reading that absence as a miss would fire this gate on every healthy diff. Corroborate the two outcomes that leave a trace: `findings` against the finding list, `error` against its `## Errors mechanical-prepass-<id>` entry. A missing `mechanical_prepass_attempted` declaration means the pre-pass was skipped wholesale (a TS-dominated diff that ran no lint and no `tsc` is the documented live miss); a check absent from the map means it was never reached; an uncorroborated outcome means the record and the run disagree. Each is a contract miss: append `## Errors mechanical-prepass-incomplete: declared=<...> missing-outcome=<...>` and surface it in the Phase 6 report `## Caveats`; this is advisory (the pre-pass is fail-open by design and LLM reviewers still ran), so do NOT block — record the gap so the user knows the cheap-deterministic layer was thin this run.

**4.0b Spawn-batch completeness check.** Verify the Phase 2 parallel batch actually delivered every dimension declared in §2.2, with exactly one spawn per dimension:

```
declared = state.md frontmatter spawn_dims_declared
actual   = set of dimensions whose reviewer-agent emitted a structured result in Phase 3
fired    = the `fired=` count on the `## Tool log` "[Phase 2 spawn batch fired]" entry (§2.3.2)

missing = declared − actual
```

A missing `[Phase 2 spawn batch fired]` entry is drift, not a pass: §2.3.2 records it precisely so this check survives a compaction-resume into `phase: stratify`. Treat it like an absent declaration — append `## Errors phase-2-spawn-batch-record-missing` and fall back to `fired = |actual|`, which can only detect under-fire.

`fired` must equal `spawn_dims_count`, in both Standard and Batched payload shape. `fired` above the declared count means per-file-batch multiplication (forbidden by §2.3.2); below it means dropped dimensions. Each mismatch direction routes through its matching branch below.

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

Always-WAIT on both gates per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions — silently skipping missing reviewers (or silently absorbing extra ones) hides a gap the user never consented to.

When `missing` is empty and `fired == spawn_dims_count`, proceed directly to §4.1.

### 4.1 Multi-signal admission gate

CRITICAL and HIGH admit on severity alone; MEDIUM additionally needs a properly-formatted Evidence Block. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §5 at Phase 4 entry, echoed per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — unread, the admission gate has no source for its own rule, and admitted findings carry no record of which signals cleared them — §5 ONLY, located via the file's Contents block, not the whole file: §§1-4 and §6 are the reviewer-side rubric every Phase 2 spawn already consumed, and nothing orchestrator-side binds on them — and apply its gate as written. That file is the canonical home of the three admission signals, the MEDIUM-requires-an-Evidence-Block constraint, and the Path-B verification split. Admission asks how bad the finding is and whether it cites re-readable code — never how confident the reviewer was or how many dimensions agreed, both of which are reported but gate nothing (rationale: same file §4).

**Path A — severity-gated.** Survivors admit to Phase 5 stratify into `## Findings`, and to the Phase 4.2 verifier.

- CRITICAL and HIGH admit on severity alone — no citation check at admission; the Phase 4.2 verifier is what reads their code, under the high-stakes refutation guard of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §5.
- The Evidence-Block signal's "properly formatted" is a mechanical check at §4.1 entry against each finding's `Evidence:` field (false on missing): an Evidence-Block fence OR a file:line pattern + ≥2 quoted lines per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` — OR, for a sentinel-`File` finding (`File: SPEC-COMPLIANCE` / `File: PR-METADATA`, path-less by design), a verbatim quoted plan/PR fragment in `Evidence:` (a fenced quote or ≥2 quoted lines) standing in for the code citation these dimensions structurally lack. The orchestrator does NOT re-read the cited file — the Phase 4.2 verifier handles that for every §4.1 survivor.
- A sentinel-`File` MEDIUM therefore satisfies the MEDIUM Evidence-Block constraint through that quoted-fragment form, and reaches the Phase 4.2 path-less verifier rather than being deferred.

**Path B — decision-type orthogonal** (`Decision Type == PRODUCT-DECISION`, any severity). Every Path-B finding lands in `## Findings` with its `File: path:lines` anchor — so the open-decision gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3) fires and, on a Post, it inline-comments to its line — carrying `step0_status: pending`. Per the §5 verification split, a LOW carries no `Validation`/verification fields (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` § Verification fields — presence rules); a MEDIUM-or-higher enters Phase 4.2 and verifies against that anchor like any other survivor.

**DEFER** — a finding clearing neither path is written to `## Deferred — sub-threshold` per the deferred-entry schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §2.6. Deferred entries are excluded from PR comments and the fix list BY DEFAULT, with two user-elected exits — the Post drill (review-handoff.md §7) and the include-deferred gate (review-handoff.md §4.6) — and they never populate `open_questions[]`. (A LOW `PRODUCT-DECISION` is kept via Path B, never deferred.) A pass that defers nothing still writes the section, carrying the sentinel `none — the Phase 4 filter ran and deferred nothing`, because the §4.6 gate reads a bare section as a filter result that never arrived rather than as a clean one (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The assessed sentinel).

The admission gate is unchanged for repeat findings — an unchanged repeat is still ADMITTED; its `repeat-of-prior-round` marker feeds presentation only, never admission (full contract: `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-5-6-emit-handoff.md` §5.0).

### 4.2 Per-finding empirical-reproduction verification

Every kept CRITICAL / HIGH / MEDIUM finding from Phase 4.1 — each Path-A survivor, plus any Path-B `PRODUCT-DECISION` at those severities — is verified, and every one whose claim needs code re-read cold gets a fresh `finding-verifier-agent` spawn. The single exception is the §1 carve-out in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md`: a survivor decidable purely by comparing two artifacts this orchestrator already holds in full (a PR body against the changed-file list, say) is settled inline, carrying the same `Validation:` / `Verification-evidence:` fields — a cheaper route to a verdict, never a skipped verdict; when the side a finding falls on is not obvious it spawns. Survivors that share code share one spawn under the cluster rule in that file's §4 (a survivor sharing code with no other, and every sentinel-`File` finding, spawns singly), all clusters fired as a parallel batch in a single assistant turn, with one independent verdict per finding. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` at Phase 4.2 entry, echoed per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — unread, this step has no source for the cluster rule, the per-verifier input contract, the §4.5 disposition rule, or the §6 anti-sycophancy guard, and a run improvises all four — and apply its contract as written. Every finding kept at these severities is verified regardless of `risk-tier`. A LOW `PRODUCT-DECISION` admitted by Path B alone carries no Evidence Block to re-read: it skips this step and routes to the open-decision gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3). A CRITICAL or HIGH admitted on severity alone may arrive thinly cited — supplying the missing quote is this step's job; a Path-B MEDIUM+ may carry only its `File: path:lines` anchor, which the verifier reads the same way. The two sentinel-`File` dimensions (`SPEC-COMPLIANCE` / `PR-METADATA`) are path-less by design and verify against the diff instead of a code slice — see the path-less branch below.

The orchestrator gathers every survivor's evidence — cited slices, the change against the base, one hop of the call graph, sibling tests — into files at the caps defined in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2 (the canonical home for the evidence set and its sizes — not restated here so they cannot drift), groups the survivors, then composes one `finding-verifier-agent` spawn per cluster per that file's §2-§2.5 input contract (NOT the full reviewer bundle — isolation from the originating reviewer's framing prevents anchoring). All verifier spawns fire in ONE assistant response — `geniro:finding-verifier-agent`, ladder and model per `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-2-spawns.md` §2.4. In that SAME response — welded like the §2.3.1 spawn echo, never a separate turn — emit:

> Verifying <F> findings with <S> independent checks (findings that touch the same code share a check).

Then drain the batch in one turn and report once, when the last verifier is in — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4.

**Path-less sentinel findings (`File: SPEC-COMPLIANCE` / `File: PR-METADATA`).** No code `path:line`, so no code slice — the orchestrator composes the verifier spawn from the finding body (its `Evidence:` quotes the spec/PR fragment verbatim), the PR's changed-file list, and any real code `file:line` embedded in the Evidence; the verifier confirms/refutes against the diff and the cited fragment. Full contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2.

Each verifier emits the fields of `${CLAUDE_PLUGIN_ROOT}/agents/finding-verifier-agent.md` §Output schema: `validation`, `recommended_action`, `confidence`, `evidence`.

Aggregation:
- `refuted` findings move to `## Filtered`. Do NOT propagate to Phase 5 stratify or T2 handoff. At CRITICAL / HIGH the demotion is not final on one verdict: the high-stakes refutation guard (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §5 rule 1) fires a second independent verifier per refuted finding as one parallel batch, and only a second `refuted` demotes. Each refutation requires a literal quote from the cited file showing the defect is NOT present — paraphrased "looks fine" is insufficient (anti-sycophancy guard: same file §6).
- `clarified` findings keep severity but update `decision-type` to the verifier's `recommended_action`; verifier confidence and evidence append to the finding body.
- **Documented intent.** A verdict with `recommended_action: intent-check` whose `evidence` quotes a sentence from an intent source (PR body, commit message, or plan text) makes the finding decision-type INTENT-CHECK, whatever its `validation` value: `clarified`, or `confirmed` when the reviewer already tagged it INTENT-CHECK (`refuted` follows the rule above). At MEDIUM it also sets `post-disposition: off-pr`: the finding stays in `## Findings` and the report, with the quote as its recorded reason in `Verification-evidence`, and the Post drill withholds it from the PR (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff-post.md` §7.1). CRITICAL and HIGH keep posting as INTENT-CHECK — one verifier vote never drops either, the same asymmetry as the high-stakes refutation guard. LOW never reaches the verifier, so documented intent is not checked for it.
- `confirmed` findings retain decision-type; verifier confidence and evidence append.
- **Steering suppression.** A `confirmed` or `clarified` finding the reviewer noted as matching this round's "stop flagging" steering instruction (`steering-note:`, `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §7 step 5) moves to `## Filtered`, `reason:` set to the steering text verbatim, severity preserved so the user can re-elevate. This fires only here — after the finding has cleared §4.1 admission and this verifier pass — never earlier, so a steering note can never keep an unchecked finding from being validated. A CRITICAL is exempt: the §3.3 floor keeps it in `## Findings`, with the steering text recorded as a note on the finding instead of a filter reason.
- A verifier that fails to spawn or returns nothing parseable (after the registration ladder + one retry) → the finding takes `Validation: unverified` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4.5 — kept in the report (fail-open), excluded from the PR post set, surfaced under `## Caveats`.

A finding's `Validation` verdict from this step is final for this run — /geniro:review authors no confirming test of its own. Its existing `Decision Type` (`[TESTABLE]` / `[FIX-NOW]` / etc.) already travels into the handoff unchanged; `/geniro:implement` is what authors a confirming test, at the point it applies the fix.

---
