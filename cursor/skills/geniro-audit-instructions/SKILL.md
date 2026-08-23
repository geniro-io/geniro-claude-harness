---
name: geniro-audit-instructions
description: "Use when auditing the current repo's AI-assistant instruction files — CLAUDE.md, AGENTS.md, Cursor rules, Copilot instructions, and every other agent-facing surface — for accuracy against the codebase, cross-tool consistency, bloat, structure, and coverage gaps: 'audit our AI instructions', 'is CLAUDE.md stale', 'are the cursor rules consistent with CLAUDE.md', 'clean up AGENTS.md'. Runs a deterministic pre-pass, then parallel dimension reviewers, re-verifies every finding against the cited lines, renders a tiered report, and applies approved fixes only after an action gate. Skip for generating a fresh CLAUDE.md (/geniro:setup), for creating or validating a single .geniro/instructions/ entry (/geniro:instructions), and for mining session history into new rules (/geniro:reflect)."
context: main
---
<!-- Generated from skills/audit-instructions/SKILL.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->


# Audit instructions — repo-wide AI-instruction audit

## Contents

- Phases overview · Loop invariants · Anti-rationalization · Budgets · ACI per-phase tool surface · Subagent tiering
- Phase 0 (scope & inventory) · Phase 1 (mechanical pre-pass) · Phase 2 (dimension reviewers)
- Phase 3 (merge, verify, filter) · Phase 4 (report) · Phase 5 (action gate)
- State recovery · Definition of done · REFERENCE

---

You are the audit orchestrator. The target is every AI-assistant instruction file in the current repo — the files steering Claude Code, Cursor, Copilot, and their peers on every run made here. You run deterministic checks yourself, delegate semantic review to parallel dimension reviewers, re-verify every finding before admitting it, and present a tiered report. Every run also sweeps the instruction set for subtraction and reports what it found — including nothing. Fixes are applied only after the user approves them at the action gate.

**Runtime portability.** `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code. When it is unset (another Agent-Skills runtime, e.g. Cursor), resolve every reference it appears in, working these in order: the env var of that name; the ancestor directory of this file containing `.claude-plugin/plugin.json`; a copy of the referenced file sitting beside this one (the Cursor build ships each skill's own phase and reference files there); a plugin checkout inside the workspace. Where a rung yields a root, substitute it for every `${CLAUDE_PLUGIN_ROOT}` occurrence and export it as `CLAUDE_PLUGIN_ROOT` in every Bash call. **Work the rungs with a command, not a judgment:** the run's first Bash call lists the directory this file was read from and each candidate root, and its output is echoed verbatim before anything else. Read the rungs against that output — a path it does not show did not resolve, and a file it does not show cannot be read, however confidently a later step would report otherwise. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` before deciding a step cannot run here: it substitutes mechanisms, not steps, and routes a host with no one to ask to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/non-interactive-host.md`. **When no rung resolves, the files are missing but the contract is not** — open your first message by naming what is unavailable, run every phase and gate this skill declares, never let the project's own rules stand in for its decision gates, and take no outward-facing action (ready-for-review PR, merge, force-push, protected-branch push, posted comment, tracker transition) without an explicit answer.

## Phases overview

1. **Phase 0 — Scope & inventory.** Parse `$ARGUMENTS`, discover the instruction surfaces present, load the rubric (`dimensions-reference.md`), read the prior audit report if one exists.
2. **Phase 1 — Mechanical pre-pass.** Run the deterministic battery (surface discovery, cited paths, frontmatter validity, legacy formats, candidate extraction). Output: machine findings + candidate lists seeding the reviewers.
3. **Phase 2 — Parallel dimension reviewers.** Spawn one reviewer per selected dimension in ONE response, within the §Budgets spawn cap.
4. **Phase 3 — Merge, verify, filter.** Dedupe, count convergence, re-read every cited line, drop unverifiable and do-not-flag items, assign tiers.
5. **Phase 4 — Report.** Write `.geniro/state/audit-instructions/report-<YYYY-MM-DD>.md` (health summary → tier tables → per-dimension verdicts → highest-value fix) and render every finding in chat.
6. **Phase 5 — Action gate.** AskQuestion: fix now / pick / report only. Approved fixes go to fix agents with disjoint file allowlists, then the mechanical battery re-runs to verify. Cleanup + commit offer.

**Phase bodies — Read on entry to that phase.** Phases 0-3 run from this file. The last two carry their Steps in siblings, and this table is where a resumed run finds them: only a skill's front-loaded prefix survives compaction, so a pointer that lives beside its own phase section is gone exactly when a resume needs it.

| Phase | Body file |
|---|---|
| 4 — Report | `${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/phase-4-report.md` |
| 5 — Action gate | `${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/phase-5-action-gate.md` |

## Loop invariants

The canonical agent-loop invariants in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` apply.

The shared audit-pipeline invariants apply in full — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/audit-pipeline.md` §Shared invariants. This skill binds their three parameterized ones and adds one of its own:

- **Do-not-flag list** (the do-not-flag-list invariant) = the endorsed-patterns list in `dimensions-reference.md`, extended by the prior report's endorsements.
- **Subtraction sweep** (the subtraction-sweep invariant) = the bloat dimension, which runs on every audit including `--quick`.
- **Whole mechanism** (the no-blanket-deletion invariant) = an entire instruction surface or section.

S1. **Secrets are cited, never quoted.** A credential found inside an instruction file is reported by location and shape, never by value — a finding that reproduces a secret re-leaks it onto a surface that outlives the fix.

**Turn-completion check** (deliberately un-numbered, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §Turn-completion check): before stopping, re-read the last emitted paragraph — a stated intent to render a finding or fire the action gate is not the same as having done it. Phase 4's finding render and Phase 5's action gate are exactly the seam this guards.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The reviewer quoted the line — no need to re-read it." | The no-unverified-finding invariant: admission requires YOUR Read of the cited location. |
| "I'll fix this obviously dead path while scanning." | The report-before-fix invariant: edits before the action gate change the baseline other reviewers and Phase 3 verification cite. Queue it as a finding. |
| "I'll spawn reviewers one at a time to manage context." | Reviewer output is capped (§Budgets); the orchestrator holds tables, not the reviewers' reading. Sequential spawns multiply wall-time. |
| "AGENTS.md is a copy of CLAUDE.md — flag the duplication." | Deliberate mirroring (symlink or generated copy) is the endorsed way to serve many tools from one source. Flag drift BETWEEN the copies, never the mirroring itself. |
| "CLAUDE.md is only 30 lines — that's a coverage gap." | Brevity is healthy. A coverage finding needs two pieces of evidence: the tool is actively used here, and a specific needed fact is documented nowhere. |
| "This skill description is keyword-stuffed — trim it." | Trigger keywords are the routing surface the tool selects skills by; trimming them degrades selection. Flag only genuine description-vs-body drift. |
| "Two files state the same test command and agree, so it's fine." | Agreement today is drift tomorrow. Hand-maintained duplicates are a finding even while values match — propose one home, or a symlink/generation mechanism. |
| "I found an API key — I'll quote it in the evidence column so the user can verify." | Invariant S1: the report would then contain the secret and outlive the fix. Cite `file:line` and the credential's shape; NEVER the value. |
| "This file tells agents to use `--no-verify`; maybe the team wants that." | An instruction directing agents around safety mechanisms is the highest-severity finding whether or not it is intentional. Surface it and let the user decide — never silently endorse it. |
| "The bloat sweep found nothing this round, so there's nothing to report." | A silent no-op is indistinguishable from a skipped sweep. Name what you examined and what you rejected; zero findings is a valid result, an unreported sweep is not. |
| "There are 40 findings — I'll show tier counts and link the report." | A count hides the exact edits the user is authorizing. Phase 4 renders every finding before the gate — the visible set must equal the approvable set. |
| "Phase 5 fixes failed re-verification — I'll run another fix round." | Budget: 1 round. A second silent round compounds unreviewed edits on files every future agent session reads. Surface what failed and let the user decide. |
| "This `.geniro/instructions/` file has a malformed section header — flag it." | Per-file structural lint of that layer is owned by `/geniro:instructions validate` — route the finding there. Every other dimension's findings in those files stay in scope here. |
| "This rule reads fine — leave it." | Reading fine is not the bar. A rule can be live and correct and still cost more than it buys — a guardrail written for a weaker model, a fixed prohibition where a criterion would serve. The bloat dimension hunts those, not only redundancy. |
| "This paragraph explains why the rule exists — that's useful context." | Useful to a human deciding whether to keep the rule; inert to the agent following it. `dimensions-reference.md` §D4's case-for-the-rule check splits the two: the reason inside a rule an agent would rationalize around stays, the case built for a reviewer — sources, evidence grading, refutations, how the rule arrived — goes. |

## Budgets

No hard kill caps — the quality-first doctrine in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` §"Budgets — quality-first (canonical)" applies. The limits below are per-step gates, not abort triggers.

| Budget | Value |
|---|---|
| Reviewer spawns per batch | dimension reviewers (accuracy, consistency, bloat, structure, coverage) + shard splits, hard cap 8 spawns; shards count against the cap. The cap exists because Phase 3 re-reads every spawn's table by hand — the full-audit dimension list already leaves headroom for at most a few shards, so when sharding every dimension would exceed it, shard the dimensions with the largest candidate lists first rather than breaching the cap; scoped runs spawn only the relevant subset |
| Shards per dimension | ≤2, both in the same batch; split threshold per `dimensions-reference.md` §Reviewer spawn template |
| Findings per reviewer | ranked by impact; cap per `dimensions-reference.md` §Finding output contract |
| Fix rounds at Phase 5 | 1 (failed re-verification escalates to the user, not a second silent round) |
| Reviewer re-spawn on malformed output | 1 retry, then proceed with what parsed |

## ACI per-phase tool surface

The report-before-fix invariant ("Report before fix") is a prose rule; this table is its tool-level enforcement. `Edit`/`Write` on any repo file (state-file writes go through `atomic_state_write` in Bash, never the `Write` tool) are forbidden in every phase before the action gate, and open only inside an approved fix agent's disjoint allowlist after it fires.

| Phase | Allowed | Forbidden |
|---|---|---|
| `scope-inventory` (0) | `Read`, `Glob`, `Grep`, `Bash` (read-only + `atomic_state_write` for the state checkpoint) | `Edit`, `Write`, mutating `Bash`, `Agent` |
| `mechanical-pre-pass` (1) | `Read`, `Glob`, `Grep`, `Bash` (read-only battery) | `Edit`, `Write`, mutating `Bash`, `Agent` |
| `dimension-reviewers` (2) | `Agent` (reviewer spawns), `Bash` (`atomic_state_write` for `findings-<reviewer>.md` persistence) | `Edit`, `Write`, mutating `Bash` outside the state helper |
| `merge-verify-filter` (3) | `Read`, `Bash` (read-only re-reads), `Agent` (`finding-verifier-agent` spawns) | `Edit`, `Write`, mutating `Bash` |
| `report` (4) | `Read`, `Bash` (`atomic_state_write` for the dated report) | `Edit`, `Write`, mutating `Bash` outside the state helper, `Agent` |
| `action-gate` (5) | `AskQuestion`, `Agent` (fix agents, spawned only after the gate approves), `Bash` (cleanup + commit offer) | `Edit`/`Write` before the gate fires, or outside an approved fix agent's disjoint allowlist |

External sends are not part of `/geniro:audit-instructions` ACI.

## Subagent tiering

All reviewers and fix agents are `subagent_type="general-purpose"`. Reviewers OMIT `model=`, inheriting the orchestrator's tier so the user's session-level model choice governs audit depth; they stay general-purpose with the rubric pasted rather than `reviewer-agent`, whose output contract feeds /geniro:review's calibration machinery, not this skill's finding table. Phase 5 fix agents pass `model="sonnet"` — an execution spawn per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` category 4, receiving findings the user already approved and a file allowlist it may not extend. That tier is the ceiling; a round of purely textual instruction-file edits takes a cheaper one, the same tier across the batch (same file, §Sizing a non-judgment spawn). Phase 3's T0/T1 cold-verify uses the `finding-verifier-agent` ladder (OMIT `model=`). The Phase 1 battery and the rest of Phase 3 are orchestrator-inline.

---

## PHASE 0 — Scope & inventory

1. **Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: audit-instructions`, `LOAD_TIER: rules-only`, `MODE: initial-load`. From the loaded `global.md` `## Rules`, extract the search-governing subset (a code index to query before plain-text search, a required lookup tool, an off-limits directory) into `$PROJECT_SEARCH_POLICY` for the Phase 2 spawn template — `none declared` when `global.md` declares nothing about searching.
2. **Parse `$ARGUMENTS`:**
   - Empty → full audit (all dimensions, every surface found).
   - `--quick` → Phase 1 battery only; skip Phases 2-3; Phases 4-5 still run on the machine findings. The subtraction-sweep invariant still binds: sweep for bloat orchestrator-inline over the run's scope and report it.
   - A path (`docs/`, `.cursor/rules`) → restrict every dimension's scope to instruction files under it; the bloat sweep (the subtraction-sweep invariant) runs scoped to the same path.
   - A tool keyword (`claude`, `cursor`, `copilot`, `agents`, `windsurf`, `cline`, `gemini`, `aider`, `junie`, `zed`, `amazonq`, `geniro`) → restrict to that tool's surfaces per the reference §Surface inventory row.
   - A dimension name (`accuracy`, `consistency`, `bloat`, `structure`, `coverage`) → spawn that reviewer, plus the Phase 1 battery (which always runs) and the bloat sweep (the subtraction-sweep invariant) unless `bloat` already names it.
3. **Load the rubric:** Read `${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/dimensions-reference.md` in full — Phase 2 pastes its sections into every reviewer prompt verbatim. Also read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/audit-pipeline.md` — the shared reviewer schema pasted into every prompt, and the Phase 5 fix-round discipline.
4. **Read the prior report, if any:** Glob `.geniro/state/audit-instructions/report-*.md`; read the most recent one's health summary and T0-T2 tier tables. Patterns its health summary endorses extend the do-not-flag list for this run, and its T0-T2 rows enter the Phase 3 merge tagged "still open?". `.geniro/state/` is gitignored, so this finds reports from prior runs on this machine only — a teammate's audit leaves no trace here, and finding nothing means "no local prior report", never "never audited".
5. **Build the inventory and write the state checkpoint** per the reference §Run setup — enumerate the §Surface inventory globs, record what exists (with word counts and per-tool activity signals), and checkpoint after every phase.

## PHASE 1 — Mechanical pre-pass (orchestrator-inline)

Run the full battery from the reference §D1 — surface discovery, cited-path existence, command extraction, frontmatter validity, activation reachability, legacy-format detection, word counts, same-rule grep, secret scan. For each check: capture output; deterministic failures become machine findings (pre-verified — they skip Phase 3 re-reads); the extraction checks produce CANDIDATE lists, not findings.

Sort the results into:
- **Machine findings** — deterministic failures with tier per the D1 table.
- **Candidate lists** — pasted into the reviewer prompt of the dimension each one feeds (accuracy, consistency, coverage per the D1 table). A dimension with an enumerable surface and no seed spends its budget rediscovering what a grep already knew.
- **Context notes** — battery summary pasted into every reviewer prompt (which surfaces exist, word counts, legacy formats found) so reviewers don't re-derive it.

If `--quick`: run the inline bloat sweep, then jump to Phase 4 with the machine findings.

## PHASE 2 — Parallel dimension reviewers

**Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: audit-instructions`, `LOAD_TIER: rules-only`, `MODE: refresh`. Compaction since the previous load may have silently dropped the rules — re-Read all files and echo per the helper's contract. Re-derive `$PROJECT_SEARCH_POLICY` from the refreshed `global.md` before composing the reviewer batch's `PROJECT SEARCH POLICY:` slots below — a dropped policy would silently strip the search-governing rules from every reviewer prompt.

Spawn the selected reviewers in ONE response. Each prompt is self-contained — reviewers must not need to discover their own rubric. The spawn template, per-dimension paste notes, and the sharding rule are in the reference §Reviewer spawn template — you already have that file open from Phase 0.

Collect all outputs. If a reviewer returns prose instead of the table, re-spawn once with "return only the table"; on second failure, salvage what parses and note the gap in the report. Persist each reviewer's table to `.geniro/state/audit-instructions/<slug>/findings-<reviewer>.md` via `atomic_state_write` (source `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh`), where `<reviewer>` is the spawn's unique label (`D2`...`D6`, `D4-shardA`/`D4-shardB`) so no two spawns share a filename. Record the paths in the checkpoint — this is what makes resume after compaction possible without re-spawning, and what the Phase 5 cleanup deletes.

## PHASE 3 — Merge, verify, filter

1. **Merge** all reviewer tables + machine findings, plus the prior report's T0-T2 rows tagged "still open?" — carried so a re-detection miss can't silently close a safety or correctness finding; lower tiers resurface on their own. A carried row has no evidence quote, so step 2 re-reads its location for the issue itself — gone means fixed since. Dedupe by (file, issue topic); record `convergence: N` when ≥2 reviewers independently flagged the same location — convergence strengthens, duplicates collapse to one row.
2. **Verify** every non-machine finding: Read the cited `file:line` ±5 lines; the quoted evidence must appear there and the issue description must match what the file actually says. For a secret-exposure finding, confirm the credential shape exists at the location without copying the value anywhere. Quote absent or claim mischaracterizes the source → drop with a one-line note in the report's "Filtered" section.
3. **Filter**: drop do-not-flag matches; drop any finding whose subject is heading case, tone, or phrasing that merely reads better — there is no cosmetic tier to hold it, per `dimensions-reference.md` §Severity tiers; collapse repeating patterns (e.g., the same stale command cited in six files) into ONE finding listing all locations.
4. **Calibrate tiers** — reviewers over-rate their own dimension; re-check each T0/T1 against the reference §Severity tiers definitions (T0 requires an actual secret or unsafe directive, T1 an instruction an agent would actually follow into the wrong behavior). Weight by grounding: accuracy, reachability, and staleness findings rest on documented runtime mechanics; bloat and structure findings rest on vendor guidance with mixed measured evidence — when contested, calibrate the latter down, not up.
5. **Cold-verify the critical tiers.** Every finding still T0 or T1 after calibration gets one independent verdict from a `finding-verifier-agent` spawn (ladder per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`, OMIT `model=`); same-file findings cluster into one spawn. Input contract, cluster shape, and anti-sycophancy guards per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2 / §4 / §6, treating the audit finding as the finding. For a secret-exposure finding the verifier reads the cited file itself and reports shape only — invariant S1 binds its verdict text too. Refuted → move to Filtered with the verdict reason; clarified → amend the row; skip the step when no T0/T1 survives. Step 2 catches fabricated citations; this step catches real quotes carrying wrong conclusions, on the two tiers a false positive costs most.
6. Checkpoint: counts per tier, filtered count, verifier verdicts.

## PHASE 4 — Report

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/phase-4-report.md` as this phase's first action, then echo per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`** — the report structure (written to `.geniro/state/audit-instructions/report-<YYYY-MM-DD>.md`, outside the slug dir so it survives cleanup and seeds the next run) and the render-every-finding-to-chat contract that is the Phase 5 decision context. Read it again on any resumption of the phase, including after a compaction. Phase complete when the dated report exists and every kept finding is rendered in chat.

## PHASE 5 — Action gate

**On entry, Read `${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/phase-5-action-gate.md` as this phase's first action, then echo per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`** — the gate question and options, the §Deletion gate walk for whole-surface removals (the no-blanket-deletion invariant), the disjoint-allowlist fix path with the finding-ownership invariant's ownership check, the pick path, re-verification, and cleanup + commit offer. Read it again on any resumption of the phase, including after a compaction. Phase complete when the gate has fired, every deletion proposal has had its own gate, approved fixes (if any) are applied and re-verified, the slug dir is cleaned up, and a commit was offered.

## State recovery

On skill start: compute `<slug>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` §Slug rules, Glob `.geniro/state/audit-instructions/<slug>/state.md`. If present: source `${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh` and run `validate_state_file` on it — on failure fire the recovery AskQuestion from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md` instead of consuming a corrupt file. On pass, run the helper §Consumer contract (Case A/B/C/D mismatch handling), then resume from the next incomplete phase — reviewers whose `findings-<reviewer>.md` exists don't need re-spawning; missing ones do.

## Definition of done

- [ ] Phase 1 battery ran; output captured in checkpoint
- [ ] Selected reviewers spawned in one response; outputs collected
- [ ] Every admitted finding re-verified by orchestrator Read (machine findings exempt); every kept T0/T1 carries a cold verifier verdict
- [ ] No secret value reproduced in the report, the chat render, or any state file (invariant S1)
- [ ] Subtraction sweep ran and is reported — what was examined and what was rejected — whether or not it yielded findings (the subtraction-sweep invariant)
- [ ] Report written to `.geniro/state/audit-instructions/report-<date>.md` with health summary, tier tables, verdicts, filtered list, subtraction sweep
- [ ] Every finding rendered to chat (all tiers, low included) before the gate — no tier collapsed to a bare count
- [ ] Every approved finding assigned to exactly one fix agent, and every touched file to exactly one allowlist; unowned ones echoed (the finding-ownership invariant)
- [ ] Every whole-surface deletion proposal put to its own gate with its explanation rendered, none carried by a blanket approval, and the ones kept recorded as considered-and-kept (the no-blanket-deletion invariant)
- [ ] Action gate fired; fixes (if approved) applied, battery re-run clean, findings re-checked
- [ ] Slug-scoped state cleaned up; commit offered for the fixed files only

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/dimensions-reference.md` — surface inventory, dimension rubrics, severity tiers, output contract, do-not-flag list, spawn template, fix-round execution
- `${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/phase-4-report.md` / `phase-5-action-gate.md` — the Phase 4 and Phase 5 steps, read on phase entry
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/audit-pipeline.md` — shared reviewer finding schema + fix-round discipline
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` — slug rules, producer/consumer/cleanup contracts
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` — state-write helper API and exit codes
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md` — resume validation and the recovery question
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` — reviewer inherit rule and the fix-agent execution pin
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` / `per-finding-question.md` — render-then-ask contract for the action gate and the per-proposal deletion gate
