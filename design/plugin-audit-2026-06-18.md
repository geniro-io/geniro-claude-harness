# Plugin-wide audit — 2026-06-18

**Scope:** full repo (empty arguments). **Reviewer topology:** D1 mechanical battery (orchestrator-inline) → 8 parallel dimension reviewers — D2 (consistency), D3 (staleness), D4 (authoring rules), D5a (markdown logic) / D5b (shell logic), D6 (over-complication), D7 (magic numbers), D8 (safety & coverage). Each finding re-read at its cited `file:line` by the orchestrator before admission (invariant #1). 35 raw findings; after merge/verify/filter: **0 refuted, 1 recalibrated (D8-2 T1→T4), several folded into clusters.**

**This run is a focused re-audit** 4 days after the comprehensive `design/plugin-audit-2026-06-14.md` (73 findings confirmed). Six feature waves landed since: #40 (atomic-write routing + hook-doc fix), #41 (review checkbox handoff), #42 (config-weakening hook removal), #43 (related-task chain analysis + data-source fact-verification, m5-v3 schema), #39 (Fable-5 borrows), faece25 (restore staleness gate), 0326a55 (sonnet carve-outs). Value: confirm prior fixes held, find new drift from those waves, re-surface the deferred backlog.

## Health summary (what's strong — do NOT over-correct)

- **The d36edfc correctness fixes held.** D5b independently re-verified against concrete inputs: the quote/heredoc scrub in `block-dangerous-git.sh` (no longer false-blocks a command that merely names a guarded pattern in a string), the new `push-delete` matcher (blocks `git push --delete` / colon-refspec while allowing `git push -u`, `--dry-run`, `HEAD:refs/heads/main`), and the `update-semantic.sh` INT/TERM trap + mtime stale-lock reclaim (C3). **Zero T0 findings; D5b clean.**
- **m5-v3 schema lockstep is clean.** All six reader gates (`plan-context.md`, `review/phase-1-triage-reference.md`, `review/SKILL.md`, `spec-compliance-criteria.md`, `debug/SKILL.md`, `refactor/SKILL.md`) accept `m5-v1`/`m5-v2`/`m5-v3`; validator check #14 fires correctly on m5-v3 and won't reject a valid spec. **No spec silently drops to prose-mode** — the #1 regression risk for PR #43 is verified absent.
- **The config-weakening removal (#42) is clean.** Zero live references remain outside MIGRATION.md (historical) and dated design reports; the hook guarded linter/formatter/tsconfig files, never `.geniro/safety.json`, and no other hook depended on it — no guard gap. Hook counts read a consistent 9 everywhere; README/HOOKS prose counts are correct.
- **PR #43's new user-facing surfaces pass the fresh-user test.** Each new `_shared/` helper carries an explicit plain-English echo section with verbatim examples; m5-v3 jargon stays confined to author-facing schema docs and YAML blocks.
- **Mechanical hygiene clean:** tests 29/0 (was 30 — config-weakening suite removed with #42, expected), shellcheck `-S error` clean, no non-Latin script, no dangling refs, no orphan helpers (the two new `_shared/` files are wired), all frontmatter complete, descriptions ≤1024.

The defect mass is small and concentrated: (1) one real new correctness bug in `/plan`'s chain-context ordering, (2) doc drift from the sonnet carve-out commit that shipped without a lockstep doc update, (3) the new PR #43 files diverging slightly from the canonical they cite, and (4) the still-open deferred backlog from 2026-06-14 (reference-graph inversions, anti-rat row count, DoD restatements, multi-homed constants, coverage gaps).

---

## Tier 0 — Safety

None.

## Tier 1 — Correctness

| # | file:line | issue | fix | effort |
|---|---|---|---|---|
| C1 | `skills/plan/plan-loop.md:194` ↔ `:249` | **The chain-context feature #43 just shipped is defeated for a top-to-bottom reader.** §1.2 research spawns (line 194) are documented to receive "the §1.4 'TASK CHAIN CONTEXT' block (when present)", but §1.4 — which fetches the tracker ref and assembles that block — is documented *after* §1.2, and its step 4 (line 249) says to "Hold the helper's assembled 'TASK CHAIN CONTEXT' block in context for the §1.2 research-agent prompts." A linear reader spawns the research agents at §1.2 before §1.4 produces the block, so "(when present)" reads as "not present yet → skip it." This is the project's own producer-before-consumer ordering rule (the chain-assembly producer is documented after the research-spawn consumer). The `/implement` side (SKILL.md Step 7) gets this right by priming then spawning within one step. Verified by reading both spans. | Move the tracker-fetch + chain-assembly (§1.4 steps 1-4) ahead of the §1.2 research spawns (renumber so chain assembly precedes the spawns), or add an explicit "assemble the chain block first, then spawn" instruction at the top of §1.2 so the block exists before the consuming spawn. | M |

## Tier 2 — Rule violations (structural)

| # | file:line | issue | fix | effort |
|---|---|---|---|---|
| R1 | `skills/review/SKILL.md` (Anti-rationalization) | **Anti-rationalization table has 16 data rows, over the ≤15 structure-rule guideline** (also the lint-skills.sh warning). Still open since 2026-06-14. | Audit for one dead-weight row or merge the two adjacent severity-vs-decision-type orthogonality rows back to 15. | S |
| R2 | `skills/implement/SKILL.md:287,703` · `skills/implement/implement-reference.md:235` · `skills/review/SKILL.md:120` · `skills/_shared/task-chain-context.md:115` · `skills/_shared/data-sources.md:73` | **Reference-graph inversions (×6), WORSENED by #43.** Skill bodies and now two `_shared/` helpers link UP into `/plan`'s own files (`spec-template.md` for the `workflow_refs[]`/`verify:` schema, `plan-reference.md` for the tracker-mutation rule) for runtime contracts — the structure rule keeps cross-skill coordination in `_shared/`. #43 added two new `_shared/`→`plan/spec-template.md` citations (the worsening). Still open since 2026-06-10. | Relocate the canonical `workflow_refs[]` schema + the `verify:`/read-only-screen + tracker-mutation rules into `_shared/` homes (e.g. a new `_shared/workflow-refs-schema.md`); have plan, implement, review, debug, refactor, and the two new helpers cite the `_shared/` home. | L |

## Tier 3 — Staleness & drift

| # | file:line | issue | convergence |
|---|---|---|---|
| D1 | `ARCHITECTURE.md:86,90-92` · `README.md:82` | **Model-tier carve-out doc drift — a live regression from commit 0326a55.** That commit pinned `test-runner-agent` + `knowledge-retrieval-agent` to `model: sonnet` and updated the agent frontmatter + `model-tiering.md`, but the lockstep doc update never reached ARCHITECTURE.md or README.md. ARCHITECTURE.md:86 still states "All plugin-defined subagents declare `model: inherit`" (now false), and both files name only "two carve-outs" (setup-verification + implement doc-patcher) — the real count is four. README:82's "all subagents run on Sonnet" absolute is contradicted by the two sonnet pins. Prior-audit D1, still open and now worse. | D2 (4 locations) + prior-run D1 |
| D2 | `HOOKS.md:29` | `require-evidence-on-completion.sh` appears in the summary table but has no `### require-evidence-on-completion.sh` detail section — the only registered hook missing one (prior D9 fixed `block-geniro-deletion` + `enforce-tdd-order` but not this). Verified: 9 `### *.sh` detail sections exist; this hook is absent. | D3 |
| D3 | `.claude/rules/skill-prose.md:241-262` | §"Migration audit — qualitative violations" is a one-time per-skill walk plan ("This audit is one-time") describing completed remediation, not a forever rule. Prior D10, still open. | D3 |
| D4 | `.claude/skills/analyze-thread/checks-reference.md:27` | A2 spawn-list check matches `subagent_type` ending in `-reviewer` OR `reviewer-agent`; no agent name ends in `-reviewer`, so that half of the matcher is dead. Repo-local tooling. Prior D11, still open. | D3 |

## Tier 4 — Maintainability

- **`task-chain-context.md` diverges from the `data-sources.md` canonical it cites (NEW, #43).** `task-chain-context.md:79` emits a "couldn't double-check" caveat for the no-declared-block case, but `data-sources.md:101` §6 says the no-block case needs no caveat (built-in sources — including the tracker fetch itself — always apply); and `:77`'s `unconfirmed` definition narrows the canonical `data-sources.md:89` §5 definition. Fix: align §4.5/§5 to the cited canonical (no caveat on simple absence; restate the `unconfirmed` condition verbatim). Convergent (D5a + D6).
- **Seam test never updated for m5-v3 (NEW, #43).** `tests/seam/plan-review-implement-contract.sh` pins the m5-v1/m5-v2 contract thoroughly (A1-A4, C1 drift guard) but has zero m5-v3 coverage — the C1 guard only asserts m5-v1+m5-v2 in `review/SKILL.md`. A future edit dropping m5-v3 from a reader gate would not fail the suite, despite the seam test existing precisely to pin this contract. Fix: add an m5-v3 PRESENT fixture to Part A and `m5-v3` to the C1 drift grep.
- **Duplicated mutating-verb list (NEW, #43).** The full screen verb-set is re-listed verbatim in `data-sources.md:77` and `instructions/SKILL.md:437` — the latter already cites `data-sources.md §read-only screening` at the end, so the inline copy is pure drift risk. Fix: drop the inline list at instructions:437, keep the cite.
- **Multi-homed numeric constants (deferred from 2026-06-14, confirmed still present).** Phase 4.1 gate numerics (convergence ≥2, confidence ≥60/≥80/≥70) dual-homed `review/SKILL.md:410-413` ↔ `severity-calibration.md:163-176` (D7-1); verifier-slice caps ±30/50/20 inlined at `review/SKILL.md:429` rather than deferring to `finding-verification.md §2` (D7-2); ~4000-char agent-output cap restated across plan/review/implement/debug with surface drift `~4000`/`≤4K`/`≤4000` (D7-3); 250-char description cap restated ×7 across actions/instructions/skill-template (D7-4); debug stall threshold `5` stated without an adjacent WHY for the value (D7-6). Fix: one declared home each, others cite.
- **DoD checklists re-render body steps instead of exit gates (deferred, confirmed still present, ~8 files):** `debug/SKILL.md:651-667` (D6-6), `spec-challenge.md:205-217` (D6-7), plus `refactor:544`, `investigate:404`, `onboard:412`, `actions:507`, `setup:598`, `within-skill-state-handoff.md:130`, `context-isolation-checklist.md:90` (D6-8). `review/SKILL.md:604` is the correct lean-exit-gate shape to copy. Sweep one file per commit; verify each box has a body-step home before trimming.
- **Cross-file prose duplication (deferred, confirmed):** loop-invariants 1-7 restated in full in `debug/SKILL.md:36-47` (refactor already uses the lean cite — D6-2); recurrence rule-capture offer near-verbatim `refactor:425-442` ↔ `debug:445-461` (extract to `_shared/` — D6-3); done-condition never-list restated `implement-reference.md:471` vs `done-condition-check.md:39-44` (D6-4); spec-challenge §1 body vs anti-rat row 1 (D6-5).
- **Test-coverage-map gaps (deferred, confirmed still uncovered):** `lib/branch-slug.sh` (slug derivation two hooks must reproduce exactly — D8-3); `hooks/backpressure.sh` `run_silent` (D8-4); `lib/score-formula.sh` (ranking math never numerically exercised — D8-5). Plus NEW: `archive-stale.sh` `show_coverage:false` opt-out path untested (D8-6).
- **`skills/_shared/model-tiering.md` (102 lines) lacks a TOC** — just over the 100-line threshold (machine finding M1). Add a Contents block.

## Tier 5 — Cosmetic

- **Caps in normal prose (yellow flag, reasoning adjacent):** `NEVER` at `data-sources.md:89` + `task-chain-context.md:117`, `ALL` at `spec-template.md:97` — reframe to lowercase imperative-with-reason on next touch (D4-8/9/10).
- **CLAUDE.md:122** describes the archive-stale coverage line as `verified: N/total (P%)` but the script emits `coverage: verified N/total (P%)`; semantics correct, literal format differs (D2-5).
- **Echo-at-zero boilerplate** repeated across `onboard:193`/`plan-loop:659`/`implement:648` — move the contract into `improvement-routing.md` if the §8 sweep touches these (D6-9).

## Advisory (not defects)

- **`skills/implement/SKILL.md` (708) + `skills/debug/SKILL.md` (701) over the 700 hard ceiling** — MOVE candidates (caps are guidelines, never a cut); implement grew 704→708 from the #43 Step 7 chain-priming edit. Propose moving detail to a sibling reference file, not trimming.
- **D8-2 recalibrated T1→T4 (surfaced here, worth doing):** the `data-sources.md §4` read-only screen is a mutating-verb substring scan with no clause for command-substitution `$(...)`, a wrapped/aliased mutating CLI (`mytool sync`), or a non-SELECT read that exfiltrates. It is advisory doctrine executed by the judgment-applying orchestrator (no hook, no live mutator), so it is not a T1 code bug — but given the feature's purpose (safely re-checking facts against possibly-production sources), hardening §4 to call out command-substitution + "non-SELECT-shaped CLI is mutating-by-default" (and the matching `/instructions validate` lint rule) is a worthwhile cheap safety improvement.

## Filtered (dropped / recalibrated / folded — transparency)

- **0 refuted** — every finding survived re-read.
- **D8-2 recalibrated** T1→T4 (advisory markdown doctrine, not a hook/live-mutator; the orchestrator that runs it applies judgment) — surfaced in Advisory above.
- **D2-2 folded into D1** (ARCHITECTURE.md:73 summary line is the same model-tier drift as :86).
- **D7-5** (gate-render 2000-record/0.4s stated in hook + HOOKS.md) — acceptable code↔doc mirror, low value; **D7-7** (14-day staleness default lacks a magnitude WHY) — borderline, the gate itself is well-explained. Both noted, not tabled.
- **Endorsed patterns not flagged** per the do-not-flag list: justified magic numbers with adjacent WHY, author-facing tier/layer codes in architecture docs, `backpressure.sh` + `geniro-statusline.js` absent from hooks.json (library + statusline-wired), deleted-skill names in the CLAUDE.md/MIGRATION replacement tables, line caps as guidelines.

## Single highest-value fix

**C1 — the `/plan` chain-context ordering bug.** PR #43 was built so Phase 1 research subagents are primed with the related-task chain (parent epic + siblings + milestones). But the step that assembles that block (§1.4) is documented *after* the step that consumes it (§1.2 research spawns), so a top-to-bottom reader spawns the agents before the block exists and the entire feature silently no-ops. It is the one finding this run where a recently-shipped capability does not actually fire as intended, and the fix is a localized reorder.
