---
name: audit-plugin
description: "Use when auditing the Geniro plugin repo as a whole — skills, agents, hooks, lib helpers, rules, and docs — for cross-file consistency, stale references, authoring-rule compliance, logic and shell correctness, over-complication, magic numbers, and safety/coverage gaps. Runs a deterministic pre-pass, then parallel dimension reviewers, re-verifies every finding against the cited lines, and writes a tiered report to the local-only design/scratch/. Skip for fixing one known issue (/improve-template) or reviewing a pending code diff (/code-review)."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion, TodoWrite]
argument-hint: "[path/dimension scope | --quick | empty for full audit]"
---

# /audit-plugin — Whole-repo plugin audit pipeline

You are the audit orchestrator. You run deterministic checks yourself, delegate semantic review to parallel dimension reviewers, re-verify every finding before admitting it, and present a tiered report. Fixes are applied only after the user approves them at the action gate.

## Phases overview

1. **Phase 0 — Scope & inventory.** Parse `$ARGUMENTS`, build the file inventory, load the rubric (the three `.claude/rules/*.md` files + `dimensions-reference.md`).
2. **Phase 1 — Mechanical pre-pass.** Run the D1 deterministic battery (tests, lint, shellcheck, wiring greps). Output: machine findings + candidate lists that seed the reviewers.
3. **Phase 2 — Parallel dimension reviewers.** Spawn up to 8 reviewers (D2-D8, with D5 split into markdown + shell) in ONE response.
4. **Phase 3 — Merge, verify, filter.** Dedupe, count convergence, re-read every cited line, drop unverifiable and do-not-flag items, assign tiers.
5. **Phase 4 — Report.** Write `design/scratch/plugin-audit-<YYYY-MM-DD>.md` (health summary → tier tables → per-dimension verdicts → highest-value fix) and summarize in chat.
6. **Phase 5 — Action gate.** AskUserQuestion: fix now / pick / report only. Approved fixes go through implementation subagents, then the mechanical battery re-runs to verify. Cleanup + commit offer.

## Loop invariants

1. **No unverified finding ships.** Every reviewer finding is admitted only after you Read the cited `file:line` and confirm the quoted evidence exists there — reviewers hallucinate locations, and one fabricated `path:line` poisons trust in the whole report.
2. **Report before fix.** Fixes happen only after the Phase 5 gate — an audit that silently edits while scanning destroys the baseline the findings cite.
3. **Parallel spawns in one response.** All Phase 2 `Agent(...)` calls go in the same assistant turn; sequential turns serialize wall-time across 7-8 reviewers.
4. **Do-not-flag list is binding.** The reference file's endorsed-patterns list overrides any reviewer's instinct — re-flagging endorsed patterns is the audit's own false-positive failure mode.
5. **Caps are guidelines.** Line/row caps over target are advisory findings proposing a MOVE to a reference file, never a cut of load-bearing content.

## Budgets

| Budget | Value |
|---|---|
| Reviewer spawns per batch | 8 dimension reviewers (D2-D8, with D5 split) + shard splits, hard cap 10 spawns; shards count against the cap; scoped runs spawn only the relevant subset |
| Shards per dimension | ≤2 (split a dimension only when its scope exceeds ~15K lines; both shards in the same batch) |
| Findings per reviewer | ≤25, ranked by impact |
| Fix rounds at Phase 5 | 1 (failed re-verification escalates to the user, not a second silent round) |
| Reviewer re-spawn on malformed output | 1 retry, then proceed with what parsed |

## Subagent tiering

All reviewers and fix agents are `subagent_type="general-purpose"` with `model=` OMITTED — they inherit the orchestrator's tier, so the user's session-level model choice governs audit depth and cost. The Phase 1 battery and Phase 3 verification are orchestrator-inline: deterministic commands and targeted re-reads don't justify a spawn.

---

## PHASE 0 — Scope & inventory

1. **Parse `$ARGUMENTS`:**
   - Empty → full audit (all dimensions, full inventory).
   - `--quick` → Phase 1 battery only; skip Phases 2-3; Phases 4-5 still run on the machine findings (the action gate and cleanup apply regardless of depth).
   - A path (`skills/review`, `hooks/`, `lib/`) → restrict every dimension's scope to files under it; spawn only dimensions whose scope intersects.
   - A dimension name (`consistency`, `staleness`, `rules`, `logic`, `shell`, `simplicity`, `numbers`, `safety`) → spawn only that reviewer (plus the Phase 1 battery, which always runs).
2. **Build the inventory** (record file counts + line totals in the state checkpoint):
   - Shipped: `skills/**/*.md`, `agents/*.md`, `hooks/*` + `hooks/hooks.json`, `lib/*.sh`, `settings.json`, `scripts/*.sh`.
   - Dual-runtime port: `cursor/**` (generated `cursor/agents/*.md`, `cursor/hooks.json`, `cursor/hooks/claude-hook-shim.sh`, `cursor/README.md`) + `.cursor-plugin/plugin.json`. The shim is a guard-carrying surface — it translates every wired hook's block signal into Cursor's deny response, so it belongs in the safety scope, not only the consistency scope.
   - Repo-local: `.claude/rules/*.md`, `.claude/skills/**/*.md`.
   - Docs (drift targets): `CLAUDE.md`, `README.md`, `HOOKS.md`, `ARCHITECTURE.md`, `MIGRATION.md`, `CONTRIBUTING.md`.
   - Tests: `tests/**` (coverage map input for D8). `design/` and `evals/` are out of scope unless `$ARGUMENTS` names them.
3. **Load the rubric:** Read `.claude/rules/skill-authoring.md`, `skill-prose.md`, `skill-structure.md`, and `.claude/skills/audit-plugin/dimensions-reference.md` in full — Phase 2 pastes its sections into every reviewer prompt verbatim. If prior dated audit reports exist (`design/scratch/plugin-audit-2*.md` — date-named reports only, not companions like `plugin-audit-PROGRESS.md`; the whole `design/scratch/` area is gitignored, so this only finds reports from prior runs ON THIS MACHINE), read the most recent one's health summary and T0-T2 tier tables — patterns it endorses extend the do-not-flag list, and those rows enter the Phase 3 merge tagged "still open?".
4. **Write the state checkpoint** to `.geniro/state/audit-plugin/<slug>/state.md` — slug per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` §Slug rules; audit-plugin is not in that helper's enumerated producer set but adopts its contract shape verbatim. Write via `atomic_state_write` (source `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh` — direct Write to `.geniro/state/` paths trips the state-helper hook), with the full T1.5 YAML frontmatter starting on line 1: `tier: T1.5`, `producer: audit-plugin`, `schema-version: 1`, `branch`, `worktree`, `timestamp`, `phase`, `status`, `non-resumable-actions: []` (plain-text header lines before the `---` fence fail `validate_state_file`). Checkpoint after every phase with: phase completed, scope, dimensions selected, finding counts.

## PHASE 1 — Mechanical pre-pass (orchestrator-inline)

Run the full D1 battery from `dimensions-reference.md` §D1 — tests, authoring lint, shellcheck, deleted-skill grep, hooks.json wiring, frontmatter fields, file-size caps, TOC presence, orphan-candidate grep. Preflight external tools: a missing tool records its check as "skipped: tool unavailable" — a tool-absence exit is an environment gap, not a code defect, and must never become a finding. For each command: capture output verbatim; non-zero exits and lint FAILs become machine findings (pre-verified — they skip Phase 3 re-reads); the deleted-skill and orphan greps produce CANDIDATE lists, not findings.

Sort the results into:
- **Machine findings** — deterministic failures with tier per the D1 table.
- **Candidate lists** — pasted into the D3 reviewer prompt for adjudication.
- **Context notes** — battery summary pasted into every reviewer prompt ("tests green, lint warns on X, shellcheck advisory on Y") so reviewers don't re-derive it.

If `--quick`: jump to Phase 4 with machine findings only.

## PHASE 2 — Parallel dimension reviewers

Spawn the selected reviewers in ONE response. Each prompt is self-contained — reviewers must not need to discover their own rubric:

```
Agent(subagent_type="general-purpose", prompt="""
## Task: Plugin audit — dimension D<N> (<name>)

You are one reviewer in a multi-dimension audit of this Claude Code plugin repo.
Review ONLY your dimension; other dimensions are covered by parallel reviewers.

### Your rubric
{{paste the full D<N> section from dimensions-reference.md}}

### Severity tiers and output contract
{{paste §Severity tiers + §Finding output contract from dimensions-reference.md}}

### Do-not-flag list
{{paste §Do-not-flag list}}

### Your file scope
{{inventory subset for this dimension, from Phase 0}}

### Mechanical pre-pass context
{{battery summary; for D3 additionally: the candidate lists; for D7 additionally: the seed-grep output}}

### Procedure
1. Load your markdown scope in FULL via `scripts/dump-md.sh <scope paths>` and survey from that — grep hits miss reworded coverage; grep only to pinpoint an exact known string. Read non-markdown files directly.
2. Verify each candidate finding by Reading the exact cited lines — your `evidence` column must be a verbatim quote.
3. Return ONLY the findings table per the output contract (≤25 rows) plus a 2-3 sentence per-dimension verdict ("healthy / debt concentrated in X").
Do NOT fix anything. Do NOT review outside your dimension. Report only.
""", description="Audit: D<N> <name>")
```

Dimension-specific notes:
- **D4 (rules compliance):** instruct the reviewer to load the three `.claude/rules/*.md` files first as its rubric source (`scripts/dump-md.sh .claude/rules` — they're too long to paste).
- **D5:** two spawns — D5a scope `skills/ agents/ .claude/skills/`, D5b scope `hooks/ lib/ tests/`.
- **Sharding:** if a dimension's markdown scope exceeds ~15K lines (full-audit D4/D6 typically do), split into shard A (`skills/*/SKILL.md` + `agents/`) and shard B (the remainder of the dimension's scope — everything NOT in shard A, so no file falls between two positive globs), same prompt, both in the batch.

Collect all outputs. If a reviewer returns prose instead of the table, re-spawn once with "return ONLY the table"; on second failure, salvage what parses and note the gap in the report. Persist each reviewer's table to `.geniro/state/audit-plugin/<slug>/findings-<reviewer>.md` (via `atomic_state_write`), where `<reviewer>` is the spawn's unique label — `D2`...`D8`, `D5a`/`D5b`, `D4-shardA`/`D4-shardB` — so no two spawns share a filename and overwrite each other. Record the paths in the checkpoint — this is what makes resume after compaction possible without re-spawning, and what the Phase 5 cleanup deletes.

## PHASE 3 — Merge, verify, filter (orchestrator-inline)

1. **Merge** all reviewer tables + machine findings, plus the prior report's T0-T2 rows tagged "still open?" in Phase 0 — carried so a re-detection miss can't silently close a safety or correctness finding, and bounded to those tiers because lower ones resurface on their own if they persist. A carried row cites a location but no evidence quote, so step 2 verifies it by re-reading that location for the issue itself; gone means it was fixed since. Dedupe by (file, issue topic); record `convergence: N` when ≥2 reviewers independently flagged the same location — convergence strengthens, duplicates collapse to one row.
2. **Verify** every non-machine finding: Read the cited `file:line` ±5 lines; the quoted evidence must appear there and the issue description must match what the code/prose actually says. Quote absent or claim mischaracterizes the source → drop with a one-line note in the report's "Filtered" section.
3. **Filter**: drop do-not-flag matches; drop T5 findings with no convergence and weak evidence (cosmetic noise floor); collapse repeating patterns (e.g., 14 restatement sites) into ONE finding listing all locations.
4. **Calibrate tiers** — reviewers over-rate their own dimension; re-check each T0/T1 against the tier table definitions (T0 requires an actual bypass/loss path, T1 an actual behavior delta).
5. Checkpoint: counts per tier, filtered count.

## PHASE 4 — Report

Write `design/scratch/plugin-audit-<YYYY-MM-DD>.md` via Write (`design/scratch/` is a gitignored local-only working area — not a `.geniro/` state path, so the state-helper hook does not apply) with this structure, mirroring the established audit-report format:

1. **Header** — date, scope, reviewer topology (which dimensions ran, sharding).
2. **Health summary** — what's strong and must NOT be over-corrected (feeds the next run's do-not-flag list).
3. **Tier tables T0→T5** — columns: `# | file:line | issue | fix | effort`; convergence noted inline.
4. **Per-dimension verdicts** — the reviewers' 2-3-sentence verdicts, edited for consistency.
5. **Filtered** — dropped findings with one-line reasons (transparency; keeps future runs from re-litigating).
6. **Single highest-value fix** — one paragraph naming it and why.

On `--quick` runs, omit sections 4 and the convergence notes — no reviewers ran, so neither exists; state "mechanical pre-pass only" in the header instead.

In chat, render **every** finding before the action gate — the user approves individual fixes, so each one has to be visible, low and cosmetic included. A tier count alone is not enough; a count hides the exact change a reader is being asked to authorize. Lead with the highest-value fix, then the full tier tables T0→T5 (same `# | file:line | issue | fix` rows as the report, convergence inline), then the report path. When the table set is very long, send the report file itself (so every row is scannable) AND render the decision-critical tiers (T0/T1/T2) inline — but never collapse a tier to a bare number. The set the user is about to approve and the set they can see must be the same set.

## PHASE 5 — Action gate

The user must see each finding (Phase 4) before this gate — approving a fix they never read is the failure this gate guards against.

Use AskUserQuestion: "The audit found N findings (N₀ safety, N₁ correctness, ...). How should I proceed?" with options: "Fix safety + correctness now (T0-T1) (Recommended)" / "Let me pick findings" / "Report only — I'll handle fixes separately".

- **Fix path:** group approved findings by file/module; spawn implementation agents (one per group, ONE response) with the finding rows + verbatim current content pre-inlined and the constraint set from the repo rules (edit-in-place, no scope creep, caps are guidelines). Then re-run the Phase 1 battery + Read each changed location to confirm the finding is resolved. Max 1 fix round — surviving failures go back to the user. Large structural items (multi-file refactors, reference-graph re-homing) are better routed to `/improve-template` with the finding rows as `$ARGUMENTS`; say so instead of attempting them inline.
- **Pick path:** present findings per tier with multi-select AUQs (≤4 options per call; chain calls past the cap), then run the fix path on the selection.
- **Report only:** proceed to cleanup.

**Cleanup & commit:** delete the current slug's directory contents — `.geniro/state/audit-plugin/<slug>/state.md` and `findings-*.md` — per the helper §Cleanup contract (never glob sibling slug directories; they belong to parallel pipelines on other branches). Offer via AskUserQuestion: "Commit the audit report (and fixes, if any)?" — "Commit and push (Recommended)" / "Commit only" / "Skip". Stage only the report + files changed by approved fixes (never `git add -A`); follow the repo's commit style; never `--no-verify` / `--amend`.

## State recovery

On skill start: compute `<slug>`, Glob `.geniro/state/audit-plugin/<slug>/state.md`. If present: first source `${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh` and run `validate_state_file` on it — on failure fire the recovery AskUserQuestion from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md` instead of consuming a corrupt file. On pass, run the helper §Consumer contract (Case A/B/C/D mismatch handling), then resume from the next incomplete phase — reviewers whose `findings-<reviewer>.md` exists don't need re-spawning; missing ones do.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The reviewer quoted the line — no need to re-read it." | Reviewers fabricate plausible `path:line` citations. Invariant #1: admission requires YOUR Read of the cited location. One fabricated citation discredits the entire report. |
| "I'll fix this obvious typo while scanning." | Invariant #2: edits before the action gate change the baseline other reviewers and Phase 3 verification cite. Queue it as a finding. |
| "I'll spawn reviewers one at a time to manage context." | Reviewer outputs are bounded (≤25 rows each); the orchestrator only holds tables, not the reviewers' reading. Sequential spawns multiply wall-time ~8×. |
| "This caps-MUST is a violation." | Caps inside anti-rationalization right-hand cells with reasoning are explicitly endorsed. Check the do-not-flag list before flagging. |
| "This SKILL.md is 520 lines — finding: trim 20 lines." | Caps are guidelines. The valid finding is advisory + a MOVE proposal (detail → reference file), never a cut to hit a number. |
| "Two files state the same threshold and agree, so it's fine." | Agreement today is drift tomorrow — multi-homed constants are the D7 finding even when values match. Fix: one home, others cite it. |
| "Tests pass, so hooks/lib are correct." | Passing ≠ covered: hard-block guards have historically shipped untested. D8's coverage map is independent of the suite's exit code. |
| "A magic number needs a named constant." | These are markdown instructions and small shell scripts — the fix is an inline WHY or a citation to the canonical home. Keep the number. |
| "The same finding from two reviewers — I'll report both rows." | Convergence is a signal, not two findings. Collapse to one row with `convergence: 2` — duplicate rows inflate counts and erode the report's signal. |
| "Skill X mentions /geniro:learnings — stale ref, flag it." | Deleted-skill names inside the documented replacement tables (CLAUDE.md, MIGRATION.md) are documentation OF the deletion. Adjudicate candidates; don't bulk-flag grep hits. |
| "The user said audit everything — I'll include design/ and evals/." | Out of default scope: design/ holds historical reports (auditing them re-litigates closed findings) and evals/ has its own harness. Include only when `$ARGUMENTS` names them. |
| "Phase 5 fixes failed re-verification — I'll run another fix round." | Budget: 1 round. A second silent round compounds unreviewed changes on unreviewed changes. Surface what failed and let the user decide. |
| "There are 80 findings — I'll show tier counts and link the report." | The user approves fixes finding-by-finding, so a count hides the exact edits they're authorizing. Render every finding (low included) before the gate; send the report file when the set is long, but the visible set must equal the approvable set. |

## Definition of done

- [ ] Phase 1 battery ran; output captured in checkpoint
- [ ] Selected reviewers spawned in one response; outputs collected
- [ ] Every admitted finding re-verified by orchestrator Read (machine findings exempt)
- [ ] Report written to `design/scratch/plugin-audit-<date>.md` with health summary, tier tables, verdicts, filtered list
- [ ] Every finding rendered to chat (all tiers, low included) before the gate — no tier collapsed to a bare count
- [ ] Action gate fired; fixes (if approved) applied, battery re-run green, findings re-checked
- [ ] State cleaned up; commit offered

## REFERENCE

- `.claude/skills/audit-plugin/dimensions-reference.md` — dimension checklists, severity tiers, output contract, do-not-flag list
- `.claude/rules/skill-authoring.md` / `skill-prose.md` / `skill-structure.md` — the D4 rubric source
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` — slug rules, producer/consumer/cleanup contracts
- `tests/run-all.sh` + `tests/authoring/lint-skills.sh` — the D1 battery core
- `scripts/dump-md.sh [path ...]` — full-content markdown dump (filename header + complete body per tracked file); reviewers survey their markdown scope with it instead of grep
