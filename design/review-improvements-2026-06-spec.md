# Spec — /geniro:review improvements (2026-06)

Status: **implemented 2026-06-05** (pending commit; ① TDD-additive, ② report_status decision-gate, ③ `--deep` mode all landed, plus an 8-fix adversarial-review pass). Author-facing design doc (lives in `design/`, never ships to consumers). Grounded against the live skill; every change is anchored by **content** (`§N` / section title), not line numbers, so anchors don't decay.

Source: a dynamic-workflow research pass (26 agents, mapped current behavior → designed from 2 angles → adversarially fact-checked) + a user decision walk on 2026-06-05. Companion memory: `project_review_improvements_2026_06.md`.

---

## Locked decisions

| # | Topic | Decision |
|---|---|---|
| 1 | TDD chooser default | **No `(Recommended)` highlight** on either Standard or TDD — TDD is no longer "less safe", just costlier. |
| 2 | TDD test cap | **Keep the 10-test cap + a `## Caveats` note** naming uncovered findings (they still post, just without a failing-test line). |
| 3 | Decision-gate intent | **Ordering** — decisions must be resolved before the handoff is offered; NOT "no file until I decide". Solved by a draft→final lifecycle. |
| 4 | Finalize step | **Silent** (auto-flip after decisions; no extra confirm click). |
| 5 | Ask-first mode (#3) | **DROPPED.** Over-engineering for a read-only Reporter. |
| 6 | Deep recall | **3× passes** per dimension (union + dedup). |
| 7 | Deep precision | **3-vote majority** verification per finding (parse-fail = abstain). |
| 8 | Deep scope | **Everything** — 3× on all mandatory dims + 3-vote on all survivors (CRITICAL/HIGH/MEDIUM). |
| 9 | Deep implementation | **Internal Workflow tool**, with mandatory mitigations (below). |
| 10 | Deep activation | **`--deep` flag (opt-in) + a "Deep" option in the start mode chooser.** Composes with Standard/TDD. |

Build order: **① TDD-additive → ② decision-gate → ③ deep mode**, each landing as its own reviewable change.

---

## Item ① — TDD becomes purely additive

**Problem.** Today TDD mode *reduces* the review: `§7.4 Step 3.5 — TDD-mode post-set filter` narrows the PR-posted set to `[CONFIRMED-BY-TEST]` + a few decision-types, and `tdd-mode-reference.md` documents the case where this "empties the post set entirely." That contradicts the mental model (TDD should *add* test evidence, never subtract findings).

**Target behavior.** TDD = full Standard review (ALL findings kept and posted) **plus**: author F→P tests for every test-confirmable finding, append a `**Failing test:** \`<path>\`` line to confirmed findings, and offer to push the authored tests to the reviewed branch. Nothing is filtered out for being un-testable.

**Changes (file → section → change):**

1. `skills/review/phase-6-handoff-reference.md` → `§7.4 Step 3.5 — TDD-mode post-set filter` → **rewrite to a no-op that preserves the `§7.4`/`Step 3.5` anchor** (do not delete-and-renumber: `phase-4-3-test-gate-reference.md` §2.1 and the `§7.0` guard both cross-reference it; renumbering decays those). The posted set becomes mode-independent — all kept findings post in both modes. Keep the `**Failing test:**` body-line append for `[CONFIRMED-BY-TEST]` findings (it is additive, independent of the filter).
2. `skills/review/tdd-mode-reference.md` → opening paragraph + the "what TDD flips" table row for the PR-comment set + both empty-post-set edge cases + the now-stale anti-rationalization row → strip every "filter / only post / empties the post set" sense; reframe TDD as additive. Grep this file for residual reductive prose before commit — it is the single source of truth for mode semantics.
3. `skills/review/phase-1-triage-reference.md` → `§11 Mode AUQ` → rewrite the TDD option text to additive framing and **remove the `(Recommended)` suffix from the Standard option** (decision 1). New option text (plain-English): "TDD review — posts all findings, and additionally auto-authors failing tests for the testable ones and offers to push them." Standard option text: "Standard review — posts all kept findings." Neither carries `(Recommended)`.
4. `skills/_shared/reporter-boundary.md` → push-prohibition section + anti-rationalization → split the blanket "no `git push`" into (a) "no push of fixes / production-source" and (b) an explicit **authored-test-push carve-out**, triple-scoped: only files listed in the handoff `## Authored Tests`, only tests authored by `adversarial-tester-agent`, only on the explicit "Commit + push" Action-gate pick. **Add one scoping sentence: this carve-out applies to `/geniro:review` only** — the shared file binds four reporter skills, but only `/geniro:review` has a failing-tests gate; `/debug`, `/refactor`, `/investigate` must not read it as a general push license. Add one anti-rationalization row: "tests are ready, push the fix alongside them" → fixes never ship from a reporter; route to `/geniro:implement`. *(This is the highest-stakes edit — re-review `reporter-boundary.md` fresh after editing.)*
5. `skills/review/phase-4-3-test-gate-reference.md` → test-author overflow handling → when the eligible set exceeds the 10-test agent cap, surface a `## Caveats` note naming the untested findings (decision 2). Also: the `§2.1` sentence "both phases evaluate the rule fresh … cannot diverge" goes partially stale once the Phase-6 filter is a no-op (only the test-eligibility phase still evaluates the runtime-class rule) — reword it so it no longer implies a Phase-6 consumer of the rule.
6. `skills/review/SKILL.md` → `description` frontmatter + the `§4.1`/`§4.2` asides claiming `--tdd` "tightens" verification + the Definition-of-Done checklist → correct the stale "tightens Phase 4.2" claim (verification runs identically in every mode); drop the post-set-filter checklist line; in the user-facing `description`, replace the internal token `F→P` with "failing-test authoring".

**Edge cases:** no test-confirmable findings → TDD ≡ Standard (test-gate skips, nothing to add). Authored test flips green on independent re-run → finding stays posted (no `[CONFIRMED-BY-TEST]` tag, no failing-test line) — already handled by the demote-don't-delete logic; TDD no longer empties anything.

---

## Item ② — resolve decisions before the report is finalized + before the handoff

**Problem.** The report MD is written in Phase 5 (persist); the open-decision gate (`§3 Step 0`) fires in Phase 6 *after* persist. So the report exists in "final" form before the user has decided. The open-decision gate already precedes the Action gate (which offers the handoff), so the *handoff ordering* is fine — the gap is that the persisted report isn't marked as provisional during the decision window.

**Target behavior.** Add a whole-report lifecycle field `report_status: draft | final`. The crash-recovery write still lands first (marked `draft`). A silent finalize step flips it to `final` only after every decision gate clears. The Action gate's handoff option and the public-post guard refuse to fire against a `draft`. The file stays on disk during the decision window (as `draft`) so a mid-gate compaction still recovers the dearly-bought findings.

**Changes (file → section → change):**

1. `skills/_shared/state-tier-spec.md` → the `/geniro:review` producer-specific fields list (T2 handoff) → add `report_status: draft | final`. **State the back-compat rule once, here:** a missing `report_status` reads as `final` (mirrors the existing `step0_status: missing → resolved` precedent), so legacy handoffs aren't retro-blocked. No schema-version bump (validator passes producer extensions through). Other sites *reference* this rule, never restate it.
2. `skills/review/phase-6-handoff-reference.md`:
   - `§2.6 Handoff file template` → add `report_status: draft` to the frontmatter block, anchored right after the `status:` line. Update the `§9` Contents/TOC to list the new finalize section.
   - **New finalize sub-step** between `§3 Step 0` (open-decision gate) and `§4 Action gate`: after the last decision gate clears, re-verify all `open_questions[]` are `{resolved, wontfix}` and all PRODUCT-DECISION findings are `step0_status: {resolved, wontfix}`, then flip `report_status: draft → final` via `atomic_state_write`. It is a re-verify-plus-one-field-flip — it does NOT re-bake decisions (those already persist per-finding in `§3 step 3`). State this plainly so a future "simplification" pass doesn't strip it.
   - `§4 Action gate` → add a precondition: the handoff-routing option (`/geniro:implement findings`) is only offered when `report_status: final`. (Belt-and-suspenders; finalize runs just before this gate, so in practice it is always final here — the precondition documents the contract.)
   - `§7.0 Unresolved-ambiguity guard` → add **Invariant C — `report_status: final`** to the existing fail-closed invariant set (A: no `unresolved` open_questions; B: no `pending` PRODUCT-DECISION; C: report is final). Abort the Post drill if the report is still `draft`. Same defense-in-depth rationale as A/B: a producer write or orchestrator drift could leave it draft. Keep A/B/C all three — they guard different boundaries (offer vs public post).
3. `skills/review/SKILL.md` → `Phase 5.1` write note + the Phase 6 gate-chain summary + the state-machine re-entry note + anti-rationalization → one-line cross-references to the reference file only (SKILL.md is over its size target; detail lives in `§2.6`/finalize section). The new anti-rationalization ("report's already written, offer the handoff before resolving decisions") folds into the **finalize-section prose** in the reference file, not the SKILL.md table (verified at its 15-row cap). Keep the storage field names (`report_status`, `step0_status`) out of any narrated user-facing string — describe what happens ("the report is still provisional until you decide"), mark the state-machine note author-facing-only.
4. `/geniro:implement` consumer (handoff Step 12 reader) → promote "a `draft` handoff is not-yet-actionable" from advisory to an explicit numbered check, so producer + consumer ship in lockstep (schema-propagation rule). Confirm the consumer's open-question gate already exists before relying on it for safety.

---

## Item ③ — `--deep` quality mode (internal Workflow tool)

**Goal.** Raise recall (find more) and precision (validate more reliably) — explicitly NOT speed (multi-pass fan-out cannot reduce wall-clock under the `min(16, cores-2)` concurrency cap; it is a thoroughness lever). Opt-in, because it costs ~5× tokens.

**Target behavior when `deep-mode: true`:**
- **Recall (Phase 2):** every dimension (all mandatory + triggered conditional + custom) runs **3× in parallel**; findings union + dedup *within each dimension* before they reach Phase 3.
- **Precision (Phase 4.2):** every §4.1 survivor gets **3 independent verifiers**; **2/3 majority** decides `confirmed`/`refuted`; a verifier whose raw output won't parse **abstains** (does not count as a refute); if all three abstain or the workflow errors, **fail-safe to the current single-pass verifier verdict**.
- Standard/TDD posting + gating semantics are otherwise unchanged. Deep composes with TDD (`--deep --tdd`).

**Implementation — internal Workflow tool (decision 9), with mandatory mitigations:**
- The deep fan-out (Phase 2 3× reviewers, Phase 4.2 3× verifiers) runs inside `Workflow(...)` scripts so the ~30 reviewer outputs + 3×-per-survivor verifier outputs aggregate **in-script** and never flood the orchestrator's context. Only the deduped per-dimension findings (Phase 2) and the per-finding majority verdicts (Phase 4.2) return.
- **Raw JSON, not schema.** Workflow `agent()` calls in this fan-out return raw JSON text that the script parses defensively — NOT `agent({schema})` (the StructuredOutput tool-call drops ~⅔ of the time on long/converged agents). A parse failure = that voter abstains.
- **Re-assert the Reporter contract inside every workflow step.** Each agent prompt restates: read-only, no fixes, no push, no state writes (the orchestrator owns all `atomic_state_write`). The workflow parallelizes the fan-out, never the contract.
- **Hard fail-safe.** If a workflow run errors, returns unparseable aggregate, or is skipped, deep mode degrades to the existing single-pass Phase 2 / Phase 4.2 path — current behavior is the floor, never weaker.
- **`${...}` interpolation guard.** Assemble all path constants OUTSIDE workflow template literals (a bare `${CLAUDE_PLUGIN_ROOT}` in a backtick string crashes the script); reference plugin files by repo-relative path inside prompts, or build the path in a plain string before the literal.
- **Spawn hygiene.** Every reviewer/verifier spawn OMITs `model=` (inherit orchestrator tier) and applies the `spawn-agent.md` registration ladder. **Open implementation question:** the ladder's prefixed→bare→general-purpose retry is awkward inside a single `agent({agentType})` call — resolve by either (a) passing the session-resolved rung as `agentType`, or (b) spawning `general-purpose` with the `reviewer-agent` body inlined (most runtime-robust). If agent registration fails in the workflow runtime → fail-safe to the non-workflow path.

**Convergence correctness (load-bearing).** `convergence_count` (Phase 4.1 signal #1, Phase 5.3 ≥3 pitfall emit) counts **distinct dimensions**, not repeated passes. Dedup the 3× passes of one dimension into a single per-dim finding BEFORE computing cross-dim convergence — otherwise 3 passes of `bugs` finding the same issue would false-inflate convergence to 3. Spec this in the Phase 3 dedup step so deep mode can't game its own gate.

**Changes (file → section → change):**

1. `skills/review/SKILL.md`:
   - `argument-hint` + `description` → add `--deep` (with plain-English description: "deeper multi-pass review — runs each check 3× and verifies findings with a 3-agent vote; higher quality, higher cost").
   - `Phase 1` overview + Exit criterion frontmatter list → parse `--deep` (semantic, like `--tdd`); persist `deep-mode: <true|false>` to frontmatter.
   - State Machine / `Phase 2` (`§2.1`–`§2.3`) → when `deep-mode: true`, the spawn step calls the deep-review `Workflow(...)` instead of the single Agent batch; document the in-script 3× + union/dedup and the contract re-assertion. The `spawn_dims_declared[]` / `§4.0` verification gate still applies to the *set of dimensions* (3× is a multiplier on each declared dim, not a new dim).
   - Anti-rationalization → fold the "deep workflow wrapper relaxes the Reporter boundary" guard into the existing `reporter-boundary` row (the row already covers `Workflow(...)`/ultracode — extend it to name deep mode), not a new table row (15-row cap).
2. `skills/review/phase-4-verification-reference.md` → `§4 Spawn batch shape` + `§5 aggregation` → when `deep-mode: true`, spawn 3 verifiers per survivor and aggregate by 2/3 majority (parse-fail = abstain; all-abstain → single-pass fail-safe). Vote aggregation logic is single-sourced HERE (not in SKILL.md). Persist the vote outcome into the **existing** `Validation` / `Verification-evidence` fields (no schema bump) — record the majority verdict + the abstain count in `Verification-evidence`.
3. `skills/review/phase-1-triage-reference.md` → `§11 Mode AUQ` → add a third option "Deep review (3× passes + 3-vote verification)" to the chooser (the chooser already asks Standard vs TDD; a third option keeps it under the 4-option cap). Deep is a separate axis from Standard/TDD — clarify it composes (a Deep pick still runs as Standard-posting unless TDD also chosen). **Implementation note:** because deep is orthogonal to the Standard/TDD posting axis, model it as a **boolean `deep-mode`**, not a third value of the `mode` enum — the chooser surfaces it as an option but it sets the boolean. Persist to `approvals[]` under a dedicated category `deep_mode_choice` so the session-restore hook re-applies it independently of `tdd_mode_choice`.
4. `skills/_shared/state-tier-spec.md` + `skills/review/phase-6-handoff-reference.md §2.6` → add `deep-mode: <true|false>` to the `/geniro:review` producer fields + the handoff frontmatter template (schema-lockstep; missing reads as `false`).
5. `CLAUDE.md` → the `/geniro:review` row → add the `--deep` clause to the skill summary.
6. **New reference file** `skills/review/deep-mode-reference.md` (≤600 lines, TOC) → the full deep-mode contract: the two Workflow scripts (Phase 2 fan-out, Phase 4.2 vote), the mitigations, the convergence-dedup rule, the fail-safe ladder, edge cases. SKILL.md keeps a 2-3 line summary + pointer (SKILL.md is over target; detail goes to the reference).

---

## Cross-cutting requirements

- **Schema-lockstep.** `report_status` and `deep-mode` are new producer fields → update `state-tier-spec.md` + the handoff template + any consumer that reads the handoff (`/geniro:implement` Step 12) in the same change. Back-compat default for each: missing → the safe value (`final` / `false`).
- **Pre-POST scrub (`§7.6`).** The new field names (`report_status`, `deep-mode`) and the deep-workflow's internal handles must never leak into a PR comment. The existing scrub-before-POST already strips orchestrator-composed internal tokens — confirm the new tokens are covered by the scrub's MUST-NOT set.
- **Plain-English user strings.** Every new AUQ option / narration uses plain English — no `report_status` / `deep-mode` / `F→P` / `Phase 4.2` in any string the user sees. Step titles get audited first (highest leak vector).
- **Tests.** Add/extend `tests/` coverage: `block-dangerous-git` carve-out for the authored-test push (item ①); a state-file fixture with `report_status: draft` blocking the Post drill (item ②); a deep-mode fail-safe fixture (workflow-error → single-pass fallback, item ③). Run `bash tests/run-all.sh` + ShellCheck before commit.
- **Authoring lints.** Re-run `tests/authoring/lint-skills.sh` (non-Latin / dangling refs / unknown subagent_type) after each item.

## Out of scope

- **Ask-first mode (#3)** — dropped per decision 5.
- **Loop-until-dry recall** — not chosen (3× bounded passes instead). The Workflow tool makes it a future option if desired.
- **5-vote / different-lens verification** — not chosen (plain 3-vote).
- **Always-on deep** — not chosen (opt-in only).

## Acceptance criteria

- [ ] ① TDD posts the SAME finding set as Standard (no filter); authors tests additively; pushes tests only via the explicit "Commit + push" pick scoped to `/geniro:review`; chooser has no `(Recommended)`.
- [ ] ② A `draft` report blocks both the handoff-routing option and the Post drill; finalize flips to `final` silently after decisions; legacy handoffs (missing field) still actionable.
- [ ] ③ `--deep` (and the chooser option) runs 3× passes + 3-vote; convergence counts distinct dims not passes; any workflow failure falls back to single-pass; composes with TDD.
- [ ] No internal token leaks to PR comments; all new user strings plain-English.
- [ ] `tests/run-all.sh` + `lint-skills.sh` green; a fresh `/geniro:review` pass over the diff before merge.

## Open risks

1. **Reporter-boundary widening (item ①)** — the test-push carve-out is the highest-stakes edit; the cross-skill scoping sentence + anti-rationalization row + a fresh review pass are the mitigations.
2. **Workflow-tool inside a Reporter (item ③)** — contract-evaporation + schema-drop + `${...}` crash are real; mitigations are speced above and must all land, plus the registration-ladder open question resolved at implementation.
3. **Convergence inflation (item ③)** — dedup-within-dim before cross-dim convergence, or deep mode games its own Phase 4.1 gate.
