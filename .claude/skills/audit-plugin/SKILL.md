---
name: audit-plugin
description: "Use when auditing the Geniro plugin repo as a whole — skills, agents, hooks, lib helpers, rules, and docs — for cross-file consistency, stale references, authoring-rule compliance, logic and shell correctness, over-complication, magic numbers, safety/coverage gaps, and wiring completeness (what the plugin declares but never consumes: instruction blocks with no execution site, load sites that cannot resolve, phases and gates promised but never built, enforcement claimed with no hook). Also proposes deleting whole mechanics — a phase, gate, step, spawn, or check earning too little for what it costs in tokens and wall-clock, or that makes the process worse — each backed by a measured cost and asked as its own question, with an explanation, before anything is removed. Runs a deterministic pre-pass, then parallel dimension reviewers that re-verify every finding, and writes a tiered report to design/scratch/. Skip for fixing one known issue (/improve-template) or reviewing a pending diff (/geniro:review)."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite]
argument-hint: "[path/dimension scope | --quick | empty for full audit]"
---

# /audit-plugin — whole-repo plugin audit pipeline

## Contents

- Phases overview · Loop invariants · Anti-rationalization · Budgets · Subagent tiering
- Phase 0 (scope & inventory) · Phase 1 (mechanical pre-pass) · Phase 2 (dimension reviewers)
- Phase 3 (merge, verify, filter) · Phase 4 (report) · Phase 5 (action gate)
- State recovery · Definition of done · REFERENCE

---

You are the audit orchestrator. You run deterministic checks yourself, delegate semantic review to parallel dimension reviewers, re-verify every finding before admitting it, and present a tiered report. Every run also sweeps for subtraction and reports what it found — including nothing. Fixes are applied only after the user approves them at the action gate.

## Phases overview

1. **Phase 0 — Scope & inventory.** Parse `$ARGUMENTS`, build the file inventory, load the rubric (every `.claude/rules/*.md` file + `dimensions-reference.md`).
2. **Phase 1 — Mechanical pre-pass.** Run the D1 deterministic battery (tests, lint, shellcheck, wiring greps). Output: machine findings + candidate lists that seed the reviewers.
3. **Phase 2 — Parallel dimension reviewers.** Spawn one reviewer per selected dimension (D5 splits into markdown + shell) in ONE response, within the §Budgets spawn cap.
4. **Phase 3 — Merge, verify, filter.** Dedupe, count convergence, re-read every cited line, drop unverifiable and do-not-flag items, assign tiers.
5. **Phase 4 — Report.** Write `design/scratch/plugin-audit-<YYYY-MM-DD>.md` (health summary → tier tables → per-dimension verdicts → highest-value fix) and summarize in chat.
6. **Phase 5 — Action gate.** AskUserQuestion: fix now / pick / report only. Approved fixes go through implementation subagents, then the mechanical battery re-runs to verify. Cleanup + commit offer.

## Loop invariants

The shared audit-pipeline invariants apply in full — `skills/_shared/audit-pipeline.md` §Shared invariants. This skill binds their three parameterized ones and adds one of its own:

- **Do-not-flag list** (the do-not-flag-list invariant) = `dimensions-reference.md` §Do-not-flag list.
- **Subtraction sweep** (the subtraction-sweep invariant) = D6, which spawns on every run — full, path-scoped, single-dimension, and `--quick`.
- **Whole mechanism** (the no-blanket-deletion invariant) = a phase, gate, step, spawn, dimension, or helper; walk these per `dimensions-reference.md` §Deletion gate.

S1. **Caps are guidelines** per `dimensions-reference.md` §Do-not-flag list.

**Turn-completion check** (deliberately un-numbered, per `skills/_shared/loop-invariants.md` §Turn-completion check): before stopping, re-read the last emitted paragraph — a stated intent to render a finding, fire the action gate, or walk a deletion gate is not the same as having done it. Phase 4's finding render and Phase 5's per-item deletion gate are exactly the seam this guards.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The reviewer quoted the line — no need to re-read it." | The no-unverified-finding invariant: admission requires YOUR Read of the cited location. |
| "I'll fix this obvious typo while scanning." | The report-before-fix invariant: edits before the action gate change the baseline other reviewers and Phase 3 verification cite. Queue it as a finding. |
| "This caps-MUST is a violation." | Caps inside anti-rationalization right-hand cells with reasoning are explicitly endorsed. Check the do-not-flag list before flagging. |
| "This SKILL.md is 5,200 words — finding: trim 200 words." | S1: size guidance is advisory, so the valid finding is the advisory itself plus a MOVE proposal, never a cut. |
| "Two files state the same threshold and agree, so it's fine." | Agreement today is drift tomorrow — multi-homed constants are the D7 finding even when values match. Fix: one home, others cite it. |
| "Tests pass, so hooks/lib are correct." | Passing ≠ covered: hard-block guards have historically shipped untested. D8's coverage map is independent of the suite's exit code. |
| "A magic number needs a named constant." | These are markdown instructions and small shell scripts, so a named constant is the wrong fix. But which fix is right depends on whether the number has one home: single-homed and self-explaining → add an inline WHY and KEEP it; restated, counting repo contents, or ordinalling a list → REMOVE it (D7's two dispositions). |
| "Skill X mentions /geniro:learnings — stale ref, flag it." | Deleted-skill names inside the documented replacement mapping (README.md "Skills deleted", MIGRATION.md) are documentation OF the deletion. Adjudicate candidates; don't bulk-flag grep hits. |
| "The user said audit everything — I'll include design/ and evals/." | Out of default scope: `design/scratch/` holds historical reports (auditing them re-litigates closed findings) and evals/ has its own harness. Include only when `$ARGUMENTS` names them. |
| "This one reads better rewritten — it's a one-line fix." | Nine rounds thought that. Prose edits from this pipeline survived at 6% against 86% for code, so a taste finding is not a small finding here — it is not a finding, per `dimensions-reference.md` §Severity tiers. What it may be is an undiscovered check: if a command could decide it, §Mechanize what recurs is where it goes. |
| "I found the same defect in nine files — I'll fix all nine." | Nine sites is a class, and a class closes with a check. Fix them, and propose the check that keeps them closed; a fix-only round leaves the tenth site to be re-found next run. |
| "Phase 5 fixes failed re-verification — I'll run another fix round." | Budget: 1 round. A second silent round compounds unreviewed changes on unreviewed changes. Surface what failed and let the user decide. |
| "There are 80 findings — I'll show tier counts and link the report." | A count hides the exact edits the user is authorizing. Phase 4 renders every finding before the gate — the visible set must equal the approvable set. |
| "This instruction reads fine — leave it." | Reading fine is not the bar. A rule can be live and still cost more than it buys: a fixed threshold where a criterion would let the model read the situation, an example that narrows the solution space, a guardrail written for a weaker model. D6 hunts those, not only redundancy. |
| "This mid-run pick isn't one of Phase 5's four options — I'll settle it in chat" | The tiered action pick, the per-item deletion walk, and the commit-and-push offer are this skill's gates, not the complete set — route every user-facing choice through `AskUserQuestion` (`skills/_shared/gate-rendering.md` §Lean-question conventions owns the rule). |

## Budgets

| Budget | Value |
|---|---|
| Reviewer spawns per batch | one spawn per selected dimension (D5 splits into markdown + shell) + shard splits, hard cap 12 spawns; shards count against the cap, and a sharded D6's extra cross-file-checks spawn (`dimensions-reference.md` §Reviewer spawn template — D6 sharding) counts as one more; scoped runs spawn only the relevant subset. The cap exists because Phase 3 re-reads every spawn's table by hand — a full audit's dimension list (Phase 0 Step 1's enumeration, below; D1 runs inline, D5 always splits into two) already leaves little headroom to shard further, so when a run's scope would push another dimension past the split threshold, that dimension stays a single unsharded spawn (a larger read for one reviewer) rather than breaching the cap |
| Shards per dimension | ≤2 line-balanced shards, both in the same batch, plus D6's unsharded cross-file-checks spawn when D6 itself shards; split threshold per `dimensions-reference.md` §Reviewer spawn template |
| Findings per reviewer | ranked by impact; cap per `dimensions-reference.md` §Finding output contract |
| Fix rounds at Phase 5 | 1 (failed re-verification escalates to the user, not a second silent round) |
| Reviewer re-spawn on malformed output | 1 retry, then proceed with what parsed |

## Subagent tiering

All reviewers and fix agents are `subagent_type="general-purpose"`. Reviewers OMIT `model=`, inheriting the orchestrator's tier so the user's session-level model choice governs audit depth; they stay general-purpose with the rubric pasted rather than `reviewer-agent`, whose output contract feeds /geniro:review's calibration machinery, not this audit's finding table. Phase 5 fix agents pass `model="sonnet"` — an execution spawn per `skills/_shared/model-tiering.md` category 4, receiving findings the user already approved and a file allowlist it may not extend; that tier is the ceiling, and a round of purely textual edits sizes below it. Phase 3's T0/T1 cold-verify uses the `finding-verifier-agent` ladder (OMIT `model=`), and the Phase 1 suite run goes through `test-runner-agent` — isolation there buys output containment, not judgment. The rest of the battery and of Phase 3 is orchestrator-inline.

---

## PHASE 0 — Scope & inventory

1. **Parse `$ARGUMENTS`:**
   - Empty → full audit (all dimensions, full inventory).
   - `--quick` → Phase 1 battery only; skip Phases 2-3; Phases 4-5 still run on the machine findings (the action gate and cleanup apply regardless of depth), running the D6 sweep orchestrator-inline over the run's scope with no reviewer spawned.
   - A path (`skills/review`, `hooks/`, `lib/`) → restrict every dimension's scope to files under it; spawn only dimensions whose scope intersects, plus D6 scoped to the same path.
   - A dimension name (`consistency`, `staleness`, `rules`, `logic`, `shell`, `simplicity`, `numbers`, `safety`, `wiring`) → spawn that reviewer, plus the Phase 1 battery (which always runs) and D6, unless `simplicity` already names it.

   D6's sweep runs on every one of these — spawned as a reviewer on full and scoped runs, orchestrator-inline on `--quick` — per the subtraction-sweep invariant.
2. **Load the rubric:** Glob `.claude/rules/*.md` and Read every match, plus `.claude/skills/audit-plugin/dimensions-reference.md`, in full — Phase 2 pastes its sections into every reviewer prompt verbatim. Glob rather than a fixed list, so a rule file added later is still applied. Also read `skills/_shared/audit-pipeline.md` — the shared reviewer schema pasted into every prompt, and the Phase 5 fix-round discipline.
3. **Build the inventory and write the state checkpoint**
per `dimensions-reference.md` §Run setup — the scope enumeration and the checkpoint's frontmatter contract live there. Checkpoint after every phase.

## PHASE 1 — Mechanical pre-pass (orchestrator-inline)

Run the full D1 battery from `dimensions-reference.md` §D1 — tests, authoring lint, shellcheck, deleted-skill grep, hooks.json wiring, frontmatter fields, activation reachability, file-size caps, TOC presence, orphan-candidate grep, declaration inventory. Preflight external tools: a missing tool records its check as "skipped: tool unavailable" — a tool-absence exit is an environment gap, not a code defect, and must never become a finding. Run the test-suites check through a `test-runner-agent` spawn (ladder per `skills/_shared/spawn-agent.md`): it returns a structured pass/fail summary with failure snippets, so a red run's raw stdout never reaches your context — the summary is that check's captured output. For every other command: capture output verbatim. Non-zero exits and lint FAILs become machine findings (pre-verified — they skip Phase 3 re-reads); the deleted-skill and orphan greps produce CANDIDATE lists, not findings.

Sort the results into:
- **Machine findings** — deterministic failures with tier per the D1 table.
- **Candidate lists** — pasted into the reviewer prompt of the dimension each one feeds (D3, D6, D7, D8, D9 per the D1 table). A dimension with an enumerable surface and no seed under-performs: the reviewer spends its budget rediscovering what a grep already knew.
- **Context notes** — battery summary pasted into every reviewer prompt ("tests green, lint warns on X, shellcheck advisory on Y") so reviewers don't re-derive it.

If `--quick`: run the D6 subtraction sweep orchestrator-inline over the run's scope (per the subtraction-sweep invariant — no reviewer spawned), then jump to Phase 4 with machine findings plus that sweep's output.

## PHASE 2 — Parallel dimension reviewers

Spawn the selected reviewers in ONE response. Each prompt is self-contained — reviewers must not need to discover their own rubric. Spawn template, the per-dimension notes, and the sharding rule: `dimensions-reference.md` §Reviewer spawn template — you are already reading that file to paste each reviewer's rubric sections, so it costs no extra load here.

Collect all outputs. If a reviewer returns prose instead of the table, re-spawn once with "return ONLY the table"; on second failure, salvage what parses and note the gap in the report. Persist each reviewer's table to `.geniro/state/audit-plugin/<slug>/findings-<reviewer>.md` (via `atomic_state_write`), where `<reviewer>` is the spawn's unique label — the dimension id, its split halves (`D5a`/`D5b`), its shards (`D4-shardA`/`D4-shardB`), or D6's unsharded cross-file spawn (`D6-crossfile`) — so no two spawns share a filename and overwrite each other. Record the paths in the checkpoint — this is what makes resume after compaction possible without re-spawning, and what the Phase 5 cleanup deletes.

## PHASE 3 — Merge, verify, filter

1. **Merge** all reviewer tables + machine findings. Dedupe by (file, issue topic); record `convergence: N` when ≥2 reviewers independently flagged the same location — convergence strengthens, duplicates collapse to one row.
2. **Verify** every non-machine finding: Read the cited `file:line` ±5 lines; the quoted evidence must appear there and the issue description must match what the code/prose actually says. Quote absent or claim mischaracterizes the source → drop with a one-line note in the report's "Filtered" section.
3. **Filter**: drop do-not-flag matches; collapse repeating patterns (e.g., the same defect at 14 sites) into ONE finding listing all locations.
4. **Calibrate tiers** — reviewers over-rate their own dimension; re-check each T0/T1 against the tier table definitions (T0 requires an actual bypass/loss path, T1 an actual behavior delta).
4b. **Apply the oracle test, and drop what fails it.** Ask of each finding: could a command say "fixed" without anyone's taste being the judge? A dangling reference, a wrong count, a broken hook, a wrong shell branch — yes, and those proceed. "These two sections could merge", "this reads better", "this caps-MUST should be lowercase" — no; nothing confirms those but another reader's agreement, and this pipeline's own prose edits survived at 6%. **A finding with no oracle goes to Filtered, not to a tier table** (`dimensions-reference.md` §Severity tiers).

   Then ask the second question of every survivor: **is this one site of a class a command could decide?** If so, the finding's `fix` column names the check that closes the class, and Phase 5 builds it with the fix (§Mechanize what recurs). This is the pipeline's compounding output — a fix closes one site, a check closes the class permanently.
5. **Cold-verify the critical tiers.** Every finding still T0 or T1 after calibration gets one independent verdict from a `finding-verifier-agent` spawn (ladder per `skills/_shared/spawn-agent.md`, OMIT `model=`); same-file findings cluster into one spawn. Input contract, cluster shape, and anti-sycophancy guards per `skills/_shared/finding-verification.md` §2 / §4 / §6, treating the audit finding as the finding. Refuted → move to Filtered with the verdict reason; clarified → amend the row; skip the step when no T0/T1 survives. Step 2 catches fabricated citations; this step catches real quotes carrying wrong conclusions — the tiers that drive the "fix safety + correctness now" recommendation are the ones a false positive costs most.
6. Checkpoint: counts per tier, filtered count, verifier verdicts.

## PHASE 4 — Report

Write `design/scratch/plugin-audit-<YYYY-MM-DD>.md` via Write (`design/scratch/` is a gitignored local-only working area — not a `.geniro/` state path, so the state-helper hook does not apply) with this structure, mirroring the established audit-report format:

1. **Header** — date, scope, reviewer topology (which dimensions ran, sharding).
2. **Health summary** — what's strong and must NOT be over-corrected (feeds the next run's do-not-flag list).
3. **Tier tables T0→T4** — columns: `# | file:line | issue | fix | effort`; convergence noted inline. Where a finding's `fix` names a new check, say so in the column — those are what the next round will not have to re-find.
4. **Per-dimension verdicts** — the reviewers' 2-3-sentence verdicts, edited for consistency.
5. **Filtered** — dropped findings with one-line reasons (transparency; keeps future runs from re-litigating).
6. **Subtraction sweep** (the subtraction-sweep invariant) — always present, even when empty: what D6 examined, and every candidate it considered and rejected with the reason. Mechanism-level proposals list separately from text ones and carry inline the evidence §Deletion gate renders, so the user reads it before the gate rather than for the first time inside it.
7. **Single highest-value fix** — one paragraph naming it and why.

On `--quick` runs, omit section 4 and the convergence notes — no reviewers ran, so neither exists; state "mechanical pre-pass only" in the header instead. Section 6 still appears, carrying the orchestrator-inline sweep.

In chat, render **every** finding before the action gate — the user approves individual fixes, so each one has to be visible, lowest tier included. Lead with the highest-value fix, then the full tier tables T0→T4 (same `# | file:line | issue | fix` rows as the report, convergence inline), then the report path. When the table set is very long, send the report file itself (so every row is scannable) AND render the decision-critical tiers (T0/T1/T2) inline. The set the user is about to approve and the set they can see must be the same set.

## PHASE 5 — Action gate

`Steps: phase-5-action-gate.md` (read on entry to Phase 5). AskUserQuestion on the tiered fix decision, the mechanism-deletion gate, the disjoint-scope fix path, and cleanup + commit. Exit when the chosen path (fix / pick / deletion / report-only) has run to completion and the state directory is cleaned up.

## State recovery

On skill start: compute `<slug>`, Glob `.geniro/state/audit-plugin/<slug>/state.md`. If present: first source `lib/validate-state-file.sh` and run `validate_state_file` on it — on failure fire the recovery AskUserQuestion from `skills/_shared/validate-state-file.md` instead of consuming a corrupt file. On pass, run the helper §Consumer contract (Case A/B/C/D mismatch handling), then resume from the next incomplete phase — reviewers whose `findings-<reviewer>.md` exists don't need re-spawning; missing ones do.

## Definition of done

The run-completion checklist is `.claude/skills/audit-plugin/audit-plugin-definition-of-done.md`. Read it at Phase 5 entry, and walk it before the cleanup-and-commit step closes the run.

## REFERENCE

- `.claude/skills/audit-plugin/dimensions-reference.md` — dimension checklists, severity tiers, output contract, do-not-flag list
- `.claude/skills/audit-plugin/phase-5-action-gate.md` — Phase 5 Steps (Read on entry to Phase 5)
- `.claude/skills/audit-plugin/audit-plugin-definition-of-done.md` — the run-completion checklist (Read on entry to Phase 5)
- `.claude/rules/*.md` — the D4 rubric source, read by glob; `rule-writing.md` among them binds `.claude/rules/` and `CLAUDE.md` themselves
- `skills/_shared/within-skill-state-handoff.md` — slug rules, producer/consumer/cleanup contracts
- `skills/_shared/audit-pipeline.md` — shared reviewer finding schema + fix-round discipline
- `tests/run-all.sh` + `tests/authoring/lint-skills.sh` — the D1 battery core
- `scripts/measure-run-load.sh [--detail] <profile>` — what one run actually loads, in words, per component and with per-spawn multipliers. The cost evidence a D6 mechanism-level-subtraction deletion proposal cites instead of asserting one
- `skills/_shared/per-finding-question.md` / `gate-rendering.md` — the message-first render plus lean question the Phase 5 deletion gate fires
- `scripts/dump-md.sh [path ...]` — full-content markdown dump (filename header + complete body per tracked file); reviewers survey their markdown scope with it instead of grep
