---
name: audit-plugin
description: "Use when auditing the Geniro plugin repo as a whole — skills, agents, hooks, lib helpers, rules, and docs — for cross-file consistency, stale references, authoring-rule compliance, logic and shell correctness, over-complication, magic numbers, safety/coverage gaps, and wiring completeness (declarations the plugin makes but never consumes: instruction blocks with no execution site, load sites that cannot resolve, phases and gates promised but never built, unfilled template slots, enforcement claimed with no hook behind it). Runs a deterministic pre-pass, then parallel dimension reviewers, re-verifies every finding against the cited lines, and writes a tiered report to the local-only design/scratch/. Skip for fixing one known issue (/improve-template) or reviewing a pending code diff (/geniro:review, or /code-review)."
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

1. **Phase 0 — Scope & inventory.** Parse `$ARGUMENTS`, build the file inventory, load the rubric (the three `.claude/rules/*.md` files + `dimensions-reference.md`).
2. **Phase 1 — Mechanical pre-pass.** Run the D1 deterministic battery (tests, lint, shellcheck, wiring greps). Output: machine findings + candidate lists that seed the reviewers.
3. **Phase 2 — Parallel dimension reviewers.** Spawn one reviewer per selected dimension (D5 splits into markdown + shell) in ONE response, within the §Budgets spawn cap.
4. **Phase 3 — Merge, verify, filter.** Dedupe, count convergence, re-read every cited line, drop unverifiable and do-not-flag items, assign tiers.
5. **Phase 4 — Report.** Write `design/scratch/plugin-audit-<YYYY-MM-DD>.md` (health summary → tier tables → per-dimension verdicts → highest-value fix) and summarize in chat.
6. **Phase 5 — Action gate.** AskUserQuestion: fix now / pick / report only. Approved fixes go through implementation subagents, then the mechanical battery re-runs to verify. Cleanup + commit offer.

## Loop invariants

1. **No unverified finding ships.** Every reviewer finding is admitted only after you Read the cited `file:line` and confirm the quoted evidence exists there — reviewers hallucinate locations, and one fabricated `path:line` poisons trust in the whole report.
2. **Report before fix.** Fixes happen only after the Phase 5 gate — an audit that silently edits while scanning destroys the baseline the findings cite.
3. **Parallel spawns in one response.** All Phase 2 `Agent(...)` calls go in the same assistant turn; sequential turns serialize the batch's wall-time.
4. **Do-not-flag list is binding.** The reference file's endorsed-patterns list overrides any reviewer's instinct — re-flagging endorsed patterns is the audit's own false-positive failure mode.
5. **Caps are guidelines** per `dimensions-reference.md` §Do-not-flag list.
6. **Every run sweeps for subtraction.** D6 spawns on every audit — full, path-scoped, single-dimension, and `--quick` — and its verdict names what was examined and what was rejected even when it yields no findings. A repo accretes through rounds that never looked; an unreported sweep is indistinguishable from a skipped one. The result is never mandated: zero findings is valid, a manufactured deletion is not (`dimensions-reference.md` §D6).
7. **Every approved finding has an owner.** Before spawning Phase 5 fix agents, assert that the union of their finding lists equals the approved set, and echo any finding with no owner. A finding silently assigned to nobody is work the user approved and never received — and it surfaces, if at all, only because an agent happens to notice it sitting in one of its files.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The reviewer quoted the line — no need to re-read it." | Invariant #1: admission requires YOUR Read of the cited location. |
| "I'll fix this obvious typo while scanning." | Invariant #2: edits before the action gate change the baseline other reviewers and Phase 3 verification cite. Queue it as a finding. |
| "I'll spawn reviewers one at a time to manage context." | Reviewer output is capped (§Budgets); the orchestrator only holds tables, not the reviewers' reading. Sequential spawns multiply wall-time by the batch size. |
| "This caps-MUST is a violation." | Caps inside anti-rationalization right-hand cells with reasoning are explicitly endorsed. Check the do-not-flag list before flagging. |
| "This SKILL.md is 5,200 words — finding: trim 200 words." | Invariant #5: the valid finding is advisory + a MOVE proposal, never a cut. |
| "Two files state the same threshold and agree, so it's fine." | Agreement today is drift tomorrow — multi-homed constants are the D7 finding even when values match. Fix: one home, others cite it. |
| "Tests pass, so hooks/lib are correct." | Passing ≠ covered: hard-block guards have historically shipped untested. D8's coverage map is independent of the suite's exit code. |
| "A magic number needs a named constant." | These are markdown instructions and small shell scripts, so a named constant is the wrong fix. But which fix is right depends on whether the number has one home: single-homed and self-explaining → add an inline WHY and KEEP it; restated, counting repo contents, or ordinalling a list → REMOVE it (D7's two dispositions). |
| "D6 found nothing this round, so there's nothing to report." | A silent no-op is indistinguishable from a skipped dimension. The sweep is mandatory even when its result is empty: name what you examined and what you rejected. Zero findings is a valid result; an unreported sweep is not. |
| "The same finding from two reviewers — I'll report both rows." | Convergence is a signal, not two findings. Collapse to one row with `convergence: 2` — duplicate rows inflate counts and erode the report's signal. |
| "Skill X mentions /geniro:learnings — stale ref, flag it." | Deleted-skill names inside the documented replacement mapping (README.md "Skills deleted", MIGRATION.md) are documentation OF the deletion. Adjudicate candidates; don't bulk-flag grep hits. |
| "The user said audit everything — I'll include design/ and evals/." | Out of default scope: design/ holds historical reports (auditing them re-litigates closed findings) and evals/ has its own harness. Include only when `$ARGUMENTS` names them. |
| "Phase 5 fixes failed re-verification — I'll run another fix round." | Budget: 1 round. A second silent round compounds unreviewed changes on unreviewed changes. Surface what failed and let the user decide. |
| "There are 80 findings — I'll show tier counts and link the report." | A count hides the exact edits the user is authorizing. Phase 4 renders every finding before the gate — the visible set must equal the approvable set. |
| "This instruction reads fine — leave it." | Reading fine is not the bar. A rule can be live and still cost more than it buys: a fixed threshold where a criterion would let the model read the situation, an example that narrows the solution space, a guardrail written for a weaker model. D6 hunts those, not only redundancy. |

## Budgets

| Budget | Value |
|---|---|
| Reviewer spawns per batch | one spawn per selected dimension (D5 splits into markdown + shell) + shard splits, hard cap 12 spawns; shards count against the cap; scoped runs spawn only the relevant subset |
| Shards per dimension | ≤2, both in the same batch; split threshold per `dimensions-reference.md` §Reviewer spawn template |
| Findings per reviewer | ranked by impact; cap per `dimensions-reference.md` §Finding output contract |
| Fix rounds at Phase 5 | 1 (failed re-verification escalates to the user, not a second silent round) |
| Reviewer re-spawn on malformed output | 1 retry, then proceed with what parsed |

## Subagent tiering

All reviewers and fix agents are `subagent_type="general-purpose"`. Reviewers OMIT `model=` — they inherit the orchestrator's tier, so the user's session-level model choice governs audit depth. They stay general-purpose with the rubric pasted — deliberately not `reviewer-agent`, whose output contract (confidence + decision-type classification) feeds /geniro:review's calibration machinery, not this audit's finding table. Phase 5 fix agents pin `model="sonnet"`: an execution spawn per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` category 4, since each one receives findings the user already approved and a file allowlist it may not extend. Phase 3's T0/T1 cold-verify uses the `finding-verifier-agent` ladder (OMIT `model=`), and the Phase 1 suite run goes through the `test-runner-agent` ladder — isolation there buys output containment, not judgment. The rest of the battery and of Phase 3 is orchestrator-inline: deterministic commands and targeted re-reads don't justify a spawn.

---

## PHASE 0 — Scope & inventory

1. **Parse `$ARGUMENTS`:**
   - Empty → full audit (all dimensions, full inventory).
   - `--quick` → Phase 1 battery only; skip Phases 2-3; Phases 4-5 still run on the machine findings (the action gate and cleanup apply regardless of depth). Invariant #6 still binds: run the D6 sweep orchestrator-inline over the run's scope and report it, even with no reviewer spawned.
   - A path (`skills/review`, `hooks/`, `lib/`) → restrict every dimension's scope to files under it; spawn only dimensions whose scope intersects — plus D6, which spawns on every run (invariant #6) scoped to the same path.
   - A dimension name (`consistency`, `staleness`, `rules`, `logic`, `shell`, `simplicity`, `numbers`, `safety`, `wiring`) → spawn that reviewer, plus the Phase 1 battery (which always runs) and D6 (invariant #6) unless `simplicity` already names it.
2. **Load the rubric:** Read `.claude/rules/skill-authoring.md`, `skill-prose.md`, `skill-structure.md`, and `.claude/skills/audit-plugin/dimensions-reference.md` in full — Phase 2 pastes its sections into every reviewer prompt verbatim. Also read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/audit-pipeline.md` — the shared reviewer schema pasted into every prompt, and the Phase 5 fix-round discipline. If prior dated audit reports exist (`design/scratch/plugin-audit-2*.md` — date-named reports only, not companions like `plugin-audit-PROGRESS.md`; the whole `design/scratch/` area is gitignored, so this only finds reports from prior runs ON THIS MACHINE), read the most recent one's health summary and T0-T2 tier tables — patterns it endorses extend the do-not-flag list, and those rows enter the Phase 3 merge tagged "still open?".
3. **Build the inventory and write the state checkpoint** per `dimensions-reference.md` §Run setup — the scope enumeration and the checkpoint's frontmatter contract live there. Checkpoint after every phase.

## PHASE 1 — Mechanical pre-pass (orchestrator-inline)

Run the full D1 battery from `dimensions-reference.md` §D1 — tests, authoring lint, shellcheck, deleted-skill grep, hooks.json wiring, frontmatter fields, activation reachability, file-size caps, TOC presence, orphan-candidate grep, declaration inventory. Preflight external tools: a missing tool records its check as "skipped: tool unavailable" — a tool-absence exit is an environment gap, not a code defect, and must never become a finding. Run the test-suites check through a `test-runner-agent` spawn (ladder per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`): it returns a structured pass/fail summary with failure snippets, so a red run's raw stdout never reaches your context — the summary is that check's captured output. For every other command: capture output verbatim. Non-zero exits and lint FAILs become machine findings (pre-verified — they skip Phase 3 re-reads); the deleted-skill and orphan greps produce CANDIDATE lists, not findings.

Sort the results into:
- **Machine findings** — deterministic failures with tier per the D1 table.
- **Candidate lists** — pasted into the reviewer prompt of the dimension each one feeds (D3, D6, D7, D8, D9 per the D1 table). A dimension with an enumerable surface and no seed under-performs: the reviewer spends its budget rediscovering what a grep already knew.
- **Context notes** — battery summary pasted into every reviewer prompt ("tests green, lint warns on X, shellcheck advisory on Y") so reviewers don't re-derive it.

If `--quick`: jump to Phase 4 with machine findings only.

## PHASE 2 — Parallel dimension reviewers

Spawn the selected reviewers in ONE response. Each prompt is self-contained — reviewers must not need to discover their own rubric. Spawn template, the per-dimension notes, and the sharding rule: `dimensions-reference.md` §Reviewer spawn template — you are already reading that file to paste each reviewer's rubric sections, so it costs no extra load here.

Collect all outputs. If a reviewer returns prose instead of the table, re-spawn once with "return ONLY the table"; on second failure, salvage what parses and note the gap in the report. Persist each reviewer's table to `.geniro/state/audit-plugin/<slug>/findings-<reviewer>.md` (via `atomic_state_write`), where `<reviewer>` is the spawn's unique label — the dimension id, its split halves (`D5a`/`D5b`), or its shards (`D4-shardA`/`D4-shardB`) — so no two spawns share a filename and overwrite each other. Record the paths in the checkpoint — this is what makes resume after compaction possible without re-spawning, and what the Phase 5 cleanup deletes.

## PHASE 3 — Merge, verify, filter

1. **Merge** all reviewer tables + machine findings, plus the prior report's T0-T2 rows tagged "still open?" in Phase 0 — carried so a re-detection miss can't silently close a safety or correctness finding, and bounded to those tiers because lower ones resurface on their own if they persist. A carried row cites a location but no evidence quote, so step 2 verifies it by re-reading that location for the issue itself; gone means it was fixed since. Dedupe by (file, issue topic); record `convergence: N` when ≥2 reviewers independently flagged the same location — convergence strengthens, duplicates collapse to one row.
2. **Verify** every non-machine finding: Read the cited `file:line` ±5 lines; the quoted evidence must appear there and the issue description must match what the code/prose actually says. Quote absent or claim mischaracterizes the source → drop with a one-line note in the report's "Filtered" section.
3. **Filter**: drop do-not-flag matches; drop T5 findings with no convergence and weak evidence (cosmetic noise floor); collapse repeating patterns (e.g., 14 restatement sites) into ONE finding listing all locations.
4. **Calibrate tiers** — reviewers over-rate their own dimension; re-check each T0/T1 against the tier table definitions (T0 requires an actual bypass/loss path, T1 an actual behavior delta).
5. **Cold-verify the critical tiers.** Every finding still T0 or T1 after calibration gets one independent verdict from a `finding-verifier-agent` spawn (ladder per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`, OMIT `model=`); same-file findings cluster into one spawn. Input contract, cluster shape, and anti-sycophancy guards per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2 / §4 / §6, treating the audit finding as the finding. Refuted → move to Filtered with the verdict reason; clarified → amend the row; skip the step when no T0/T1 survives. Step 2 catches fabricated citations; this step catches real quotes carrying wrong conclusions — the tiers that drive the "fix safety + correctness now" recommendation are the ones a false positive costs most.
6. Checkpoint: counts per tier, filtered count, verifier verdicts.

## PHASE 4 — Report

Write `design/scratch/plugin-audit-<YYYY-MM-DD>.md` via Write (`design/scratch/` is a gitignored local-only working area — not a `.geniro/` state path, so the state-helper hook does not apply) with this structure, mirroring the established audit-report format:

1. **Header** — date, scope, reviewer topology (which dimensions ran, sharding).
2. **Health summary** — what's strong and must NOT be over-corrected (feeds the next run's do-not-flag list).
3. **Tier tables T0→T5** — columns: `# | file:line | issue | fix | effort`; convergence noted inline.
4. **Per-dimension verdicts** — the reviewers' 2-3-sentence verdicts, edited for consistency.
5. **Filtered** — dropped findings with one-line reasons (transparency; keeps future runs from re-litigating).
6. **Subtraction sweep** (invariant #6) — always present, even when empty: what D6 examined, and every candidate it considered and rejected with the reason.
7. **Single highest-value fix** — one paragraph naming it and why.

On `--quick` runs, omit section 4 and the convergence notes — no reviewers ran, so neither exists; state "mechanical pre-pass only" in the header instead. Section 6 still appears, carrying the orchestrator-inline sweep.

In chat, render **every** finding before the action gate — the user approves individual fixes, so each one has to be visible, low and cosmetic included. Lead with the highest-value fix, then the full tier tables T0→T5 (same `# | file:line | issue | fix` rows as the report, convergence inline), then the report path. When the table set is very long, send the report file itself (so every row is scannable) AND render the decision-critical tiers (T0/T1/T2) inline. The set the user is about to approve and the set they can see must be the same set.

## PHASE 5 — Action gate

Use AskUserQuestion: "The audit found N findings (N₀ safety, N₁ correctness, ...). How should I proceed?" with options: "Fix safety + correctness now (T0-T1) (Recommended)" / "Fix everything — every tier" / "Let me pick findings" / "Report only — I'll handle fixes separately".

T0-T1 carries the `(Recommended)` marker because it is the smallest change set that closes every bypass and behavior defect, so it is the one a reviewer can still read end-to-end. "Fix everything" is a first-class option, not a fallback — say what it costs (it fans out across more agents and touches far more files, and the whole set lands in one fix round) and let the user choose.

- **Fix path:** group approved findings into **strictly disjoint file scopes** — two agents editing one file overwrite each other, and a shared file is the one place a fix round loses work silently. Name each agent's scope as an allowlist and name the files other agents hold, so a finding that spans a boundary gets reported back rather than reached for. **Then run invariant #7's ownership check before spawning:** every approved finding appears in exactly one agent's list, every file the findings touch falls inside exactly one allowlist, and any finding or file with no owner is echoed and assigned. Paths that belong to no skill directory — `CLAUDE.md`, `cursor/agents/`, `tests/authoring/skill-size-baseline.txt` — fall through allowlists built per-skill, so name them explicitly or keep them for yourself.
  Spawn one agent per group in ONE response, with the finding rows and the constraint set from the repo rules (edit-in-place, no scope creep, caps are guidelines); the report file is the finding source of truth, so pass its path rather than re-inlining rows. Max 1 fix round — surviving failures go back to the user. Then run the round out per `dimensions-reference.md` §Fix-round execution, which carries what reliably goes wrong and the integration order.
- **Pick path:** present findings per tier with multi-select AUQs (≤4 options per call; chain calls past the cap), then run the fix path on the selection.
- **Report only:** proceed to cleanup.

**Cleanup & commit:** delete the current slug's directory contents — `.geniro/state/audit-plugin/<slug>/state.md` and `findings-*.md` — per the helper §Cleanup contract (never glob sibling slug directories; they belong to parallel pipelines on other branches). Offer via AskUserQuestion: "Commit the audit report (and fixes, if any)?" — "Commit and push (Recommended)" / "Commit only" / "Skip". Stage only the report + files changed by approved fixes (never `git add -A`); follow the repo's commit style; never `--no-verify` / `--amend`.

## State recovery

On skill start: compute `<slug>`, Glob `.geniro/state/audit-plugin/<slug>/state.md`. If present: first source `${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh` and run `validate_state_file` on it — on failure fire the recovery AskUserQuestion from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md` instead of consuming a corrupt file. On pass, run the helper §Consumer contract (Case A/B/C/D mismatch handling), then resume from the next incomplete phase — reviewers whose `findings-<reviewer>.md` exists don't need re-spawning; missing ones do.

## Definition of done

- [ ] Phase 1 battery ran; output captured in checkpoint
- [ ] Selected reviewers spawned in one response; outputs collected
- [ ] Every admitted finding re-verified by orchestrator Read (machine findings exempt); every kept T0/T1 carries a cold verifier verdict
- [ ] Subtraction sweep ran and is reported — what was examined and what was rejected — whether or not it yielded findings (invariant #6)
- [ ] Report written to `design/scratch/plugin-audit-<date>.md` with health summary, tier tables, verdicts, filtered list, subtraction sweep
- [ ] Every finding rendered to chat (all tiers, low included) before the gate — no tier collapsed to a bare count
- [ ] Every approved finding assigned to exactly one fix agent, and every touched file to exactly one allowlist; unowned ones echoed (invariant #7)
- [ ] Action gate fired; fixes (if approved) applied, battery re-run green, findings re-checked, and every `§` citation into a changed file re-resolved
- [ ] State cleaned up; commit offered

## REFERENCE

- `.claude/skills/audit-plugin/dimensions-reference.md` — dimension checklists, severity tiers, output contract, do-not-flag list
- `.claude/rules/skill-authoring.md` / `skill-prose.md` / `skill-structure.md` — the D4 rubric source
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` — slug rules, producer/consumer/cleanup contracts
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/audit-pipeline.md` — shared reviewer finding schema + fix-round discipline
- `tests/run-all.sh` + `tests/authoring/lint-skills.sh` — the D1 battery core
- `scripts/dump-md.sh [path ...]` — full-content markdown dump (filename header + complete body per tracked file); reviewers survey their markdown scope with it instead of grep
