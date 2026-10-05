---
name: analyze-thread
description: "Use when post-hoc analyzing saved Claude threads for pipeline errors, instruction and phase coverage gaps, and token waste. Hands off to /improve-template. Skip for live debugging (/geniro:debug)."
context: main
model: inherit
allowed-tools: [Read, Write, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[thread path(s) | thread count | empty = last few threads]"
---

# /analyze-thread — post-hoc Claude thread failure analyzer

## Contents

- Modifier handling
- Phases
- Subagent model tiering
- State persistence
- Loop invariants
- Anti-rationalization
- Budgets & quality gates
- ACI per-phase tool surface
- Definition of done
- Phase 1 (parse) · Phase 2 (detect) · Phase 3 (filter) · Phase 4 (present)
- Task execution entry / state recovery
- REFERENCE

---

You are the orchestrator for analyzing a saved Claude conversation thread and surfacing the errors Claude made while running a multi-phase pipeline. You parse the thread, run mechanical and judged checks against the canonical taxonomy, filter for relevance, then present findings with per-item user gates. You never mutate the analyzed source files (this skill is read-only on the project under analysis); approved fixes are emitted as a handoff for `/improve-template` to apply.

**Input:** one or more thread file paths, a thread count, or nothing — an empty argument analyzes the last 3 work-bearing threads across every project (§Phase 1 Step 1).
**Output:** a findings report printed to chat + (on user approval) a handoff at `.geniro/state/handoff/from-analyze-thread-<branch>.md` that `/improve-template` consumes.

**Phase bodies.** This file is the spine — role, invariants, gates, phase map. **Read the phase's Steps on entry to that phase**, from `.claude/skills/analyze-thread/`: `phase-1-2-parse-detect.md` (Phases 1-2) · `phase-3-4-filter-present.md` (Phases 3-4). That Read is the phase's physically-first action and carries a one-line echo, per `skills/_shared/phase-entry-read.md` — the phase files hold this skill's gates (including the Phase 4 user gates and the handoff emit) and their helper call sites, so work started before the Read runs outside them.

**After a compaction:** re-Read the phase file for whatever phase is running before continuing it — only the front-loaded prefix re-attaches, so a mid-phase summary can drop the Steps while leaving this spine intact. If which phase was running is also gone, re-invoke `/analyze-thread` with the same argument — the §State persistence checkpoint makes that a resume, not a re-run.

---

## Modifier handling

| Modifier in `$ARGUMENTS` | Effect |
|---|---|
| `--mechanical-only` | Skip Phase 2 Step 2 LLM-judge spawn; only mechanical checks run. Loses every judged check, including the judged coverage checks (`checks-reference.md` §4) that read whether a loaded rule changed anything — coverage then shows whether files loaded and phases ran, not whether their content took effect; say so when reporting it. Pairs well with a large batch, where the judges dominate cost. |
| `--no-handoff` | Phase 4 Steps 3-5 skipped; the findings report is printed, cleanup runs, and no handoff file is written. Useful when the user wants to read findings without committing to fix anything. |
| `--strict` | Tighten Phase 3 filter: treat medium-confidence findings as TRUE-POSITIVE not UNCERTAIN (skips per-item AUQ, includes them by default). Use when running on a thread the user already trusts to be problematic. |
| `--lenient` | Loosen Phase 3 filter: treat high-confidence judged findings as UNCERTAIN (forces AUQ). Use on threads where many findings are likely benign. |
| `--format=jsonl` / `--format=markdown` | Skip Phase 1 Step 2 auto-detect and force the format. Use when sniffing misclassifies. |

---

## Phases

1. **Parse** — resolve the thread set (one path, or the last N threads machine-wide), then per thread: auto-detect format (JSONL session log vs markdown export/paste), normalize into an events list, extract spawn-sites / tool-calls / approval gates, detect whether the thread is a Geniro skill run, and build the expectation set — what that run declared it would load, enter, and ask.
2. **Detect** — per thread, run mechanical checks (deterministic grep/jq over the thread file: the coverage checks that compare the expectation set against the trace, and the cost checks that read result sizes and usage fields) then one LLM-judge pass over that thread's excerpts with the taxonomy and that thread's expectation set seeded into the judge prompt.
3. **Filter** — orchestrator-inline relevance pass: merge the same defect across threads into one finding carrying its recurrence count, drop REDUNDANT and FALSE-POSITIVE, keep TRUE-POSITIVE and UNCERTAIN, and give every kept finding a `fix_kind` (the kind of environment change that fixes it).
4. **Present** — show the grouped findings table with its coverage and cost tables; for every UNCERTAIN finding fire `AskUserQuestion` (keep / drop / challenge); TRUE-POSITIVE findings default to "include in handoff" and the user may deselect; the final AUQ chooses the handoff destination.

A batch run changes what each phase iterates over, never the phase contract; only Phase 3's merge step is batch-specific.

---

## Subagent model tiering

Follow the canonical rule in `skills/_shared/model-tiering.md`. This skill has exactly one subagent spawn — the Phase 2 LLM-judge — and it OMITs `model=` so it inherits orchestrator tier (judging the thread is reasoning-grade work).

---

## State persistence

After completing each phase, write a checkpoint to `.geniro/state/analyze-thread/<slug>/state.md` (compute `<slug>` per `skills/_shared/within-skill-state-handoff.md` § Slug rules — base it on the analyzed thread, never the project name; §Task execution entry gives the single- and batch-mode forms). Write it via `atomic_state_write` per `skills/_shared/atomic-state-write.md` — the helper commits through tmp + fsync + rename, so a resume never reads a torn checkpoint. The first checkpoint creates the file; every later one advances `phase:` with `atomic_state_set_field` and appends its log line with `atomic_state_append_section` — re-rendering the whole file each phase is what lets an untouched field carry forward at a stale value.

The T1.5 frontmatter opens on line 1: plain-text header lines before the `---` fence fail `validate_state_file`, which §Task execution entry runs before every resume, so such a checkpoint cannot be read back.

```yaml
---
tier: T1.5
producer: analyze-thread
schema-version: 1
branch: <git branch --show-current OR detached-<short-sha>>
worktree: <git rev-parse --show-toplevel>
timestamp: <ISO-8601 UTC>
phase: <last completed phase>
status: in-progress
non-resumable-actions: []
---
```

Body: `Mode: [single | batch]`; one line per thread (`<thread_id> · <path> · <format> · <geniro-run> · <findings raw>`); one line per skipped thread with its reason; the Phase 2 raw findings count and the H4-H7 cost numbers (per-phase context rows, steering share, five largest results, subagent totals) that Phase 4's cost table renders; the Phase 3 post-merge kept count.

---

## Loop invariants

1. **Read-only on the analyzed source** (the read-only invariant). The thread file and any project files it references are never mutated by this skill. Mutating skills are `/improve-template` (template fixes) and `/geniro:implement` (consumer-code fixes) — both consume the handoff this skill emits.
2. **Mechanical before judged.** Phase 2 runs mechanical checks first because they are cheap, deterministic, and high-precision; the LLM-judge pass is then seeded with mechanical results so it does not re-discover them.
3. **One LLM-judge spawn per thread, all spawned in ONE assistant response, each carrying the taxonomy inline** (the one-judge-per-thread invariant). Per-check spawns multiply cost without improving signal, and serializing judge calls across turns multiplies wall-clock by the thread count.
4. **A defect in N threads is one finding, not N** (the cross-thread-recurrence invariant). Phase 3 merges the same check firing on the same root cause across threads into a single finding whose recurrence count is evidence of severity, not a duplicate to discard — one thread cannot tell an instruction skipped once from one skipped systematically.
5. **Never analyze this session's own log** (the own-log-exclusion invariant). Its trace has no conclusion to judge, and every finding it yields describes the analysis in progress. Identify it by session id, not by timestamp (§Phase 1 Step 1).
6. **Filter before user.** Phase 3 drops REDUNDANT and FALSE-POSITIVE findings BEFORE Phase 4, so the user sees only TRUE-POSITIVE + UNCERTAIN; filtered items appear in a separate "Filtered" section.
7. **Per-finding AUQ for UNCERTAIN, batch AUQ for confidence-high.** High-confidence findings go into the default-approve bucket the user can deselect; low/medium-confidence ones each get their own AUQ.
8. **No silent auto-default.** Empty AUQ answers indicate an upstream tool bug and must be re-asked — never auto-default to "skip".
9. **The declared side of a coverage check comes from the analyzed trace, never from this checkout** (the trace-is-the-declaration invariant). The I- and K-class checks ask what is *missing*, so they need what the run promised — recorded in the thread as the injected skill body and the tool_results of the instruction files it read. This repo's own `skills/` and `.geniro/instructions/` belong to a different project than the thread (the normal case in a batch), and even for the same project they have moved on since the run, so diffing against them reports your own later edits as the run's failures. `checks-reference.md` §8 holds the field list and the degradations when the trace lacks a field.
10. **No declaration, no finding** (the no-declaration-no-finding invariant). A coverage check with an empty declared side reports nothing: absence of an expectation is the clean path, and inventing one turns a silent run into a wall of fictional "missing" rows.

**Turn-completion check** (deliberately un-numbered, per `skills/_shared/loop-invariants.md` §Turn-completion check): before stopping, re-read the last emitted paragraph — a stated intent to fire an AUQ, spawn the judge, or emit the handoff is not the same as having done it. Phase 4's per-finding gates and its handoff emit are exactly the seam this guards.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll skip Phase 1 Step 4 metadata extraction — the user said the thread is a Geniro run" | Step 4 detects WHICH skill ran, not WHETHER one ran; without the skill identity, the plugin-specific checks misfire on every run. |
| "I'll batch all uncertain findings into one multiSelect AUQ to save user clicks" | The user asked for per-finding gates to see the evidence and decide individually; MultiSelect collapses the evidence review that is the point of UNCERTAIN. |
| "The thread is small — skip the parse step, just regex the markdown" | Phase 2's checks query the Step 3 field schema, which is what makes the mechanical pre-pass high-precision; ad-hoc regex reads different fields per check and the false-positive rate explodes. |
| "Findings_raw is 80, but they look real — present them all" | The raw-findings cap §Budgets sets is a parser-sanity tripwire, not a UX preference. 80 raw findings on one thread means either Phase 1 Step 2 misdetected the input format, so every check is reading the wrong fields, or every check is firing (taxonomy bug). Halt and have the user re-verify input. |
| "This rule was loaded and still broken in several threads — the fix is a firmer rewrite of it" | The rule already sat in context and lost; more text is the lever that has just failed. At recurrence ≥ 2 with the load echo present, the finding's `fix_kind` is never PROSE (`phase-3-4-filter-present.md` §Phase 3 Step 3). |
| "No argument given — I'll ask the user which thread they meant" | Every input shape resolves without a question (Phase 1 Step 1): empty means the last 3 work-bearing threads, and asking re-imposes the browse-and-paste step the batch default exists to remove. |
| "The newest log is the freshest data — analyze it first" | The newest log is this session's own, which the own-log-exclusion invariant excludes: every finding it yields describes the analysis in progress rather than past work. |
| "The trace shows no instruction load, so every declared file is a missing-load finding" | Check first whether the trace covers the turns where the load would have been. A compacted or mid-run thread cannot evidence a Step 0 before its first recorded turn — `checks-reference.md` §8 degradation 1: keep the check, cap confidence at medium, say the trace is partial. |
| "Every phase in the skill body owes a finding when I can't see it run" | A conditional phase whose trigger never fired, and a run the user stopped early, leave phases unentered without anything being skipped. K1 fires only on a phase stepped over while its successors ran. |
| "That's 4 unloaded files and 6 unrun steps — 10 findings" | Coverage findings roll up per declaration site: one finding for the load site listing every missing file, one for the phase listing every skipped step. Per-item findings turn one systematic defect into a wall that trips the raw-findings cap §Budgets sets and buries every other check. |
| "This pick comes up mid-run and isn't one of Phase 4's two named gates — I'll ask in prose" | The per-finding UNCERTAIN gate and the final handoff-destination gate are this skill's gates, not the complete set — route every user-facing choice through `AskUserQuestion` (`skills/_shared/gate-rendering.md` §Lean-question conventions owns the rule). |

---

## Budgets & quality gates

| Budget | Value | Why |
|---|---|---|
| Threads per batch | default 3; hard cap 5 | Each thread costs its own judge spawn and mechanical pass. Past 5 the merged report outgrows the per-finding AUQ ladder and the added recurrence signal stops being worth the wall-clock. A count above the cap is clamped, with the clamp stated to the user |
| Thread file size | hard cap per `.claude/skills/find-threads/scan.py`'s `OVERSIZE_BYTES`; warn at 1 MB | Over the hard cap likely means a merged multi-session log that should be split first. In a batch, an oversize thread is skipped and named in the report rather than aborting the run |
| LLM-judge token budget | seed prompt ≤ 8 K tokens, thread excerpts ≤ 60 K tokens | The seed is the inlined short-form taxonomy, that thread's expectation set, and its mechanical findings. Per thread — each judge has its own context. Where the expectation set crowds the seed, summarise its blocks to their headings and boundaries rather than dropping the set — a judge holding the taxonomy but not the declared side runs every coverage check blind. Excerpts are the most-suspicious events across the whole thread (ranked per `checks-reference.md` §7), not the full thread |
| Findings raw cap | 60 per thread | More than 60 raw findings on one thread = the parser misclassified the format; halt and ask user to re-check input. Applies per thread, not to the batch total |
| Findings kept cap | 25 surfaced to user | Counted AFTER the Phase 3 cross-thread merge, so a defect recurring in 3 threads consumes one slot. Past 25 the AUQ ladder becomes unworkable; if more survive, sort by recurrence × severity × confidence and truncate, noting the tail count |

---

## ACI per-phase tool surface

| Phase | Tools used | Notes |
|---|---|---|
| 1 Parse | Read, Bash (`scan.py`, `file`, `jq`, `wc`) | Bash runs batch discovery, format sniffing, and JSONL parsing; Step 4b projects the expectation set out of the thread file itself, with no Read of this repo's skills or instruction files |
| 2 Detect | Bash (`jq`, `grep`, `awk`), Agent | Bash for mechanical checks; Agent for the per-thread LLM-judge spawns, issued together in one response |
| 3 Filter | (orchestrator inline) | No tools — merge across threads, tag, and assign `fix_kind` |
| 4 Present | AskUserQuestion, Bash | AUQ for the per-finding gates and the final handoff AUQ; Bash runs `atomic_state_write` for the handoff file — a direct `Write` to a `.geniro/state/` path skips the atomic rename |

Glob is permitted across phases for state-file lookup and helper resolution but is not the workhorse tool.

---

## Definition of done

The run-completion checklist is `.claude/skills/analyze-thread/analyze-thread-definition-of-done.md`. Read it at Phase 4 entry, before findings are presented and the handoff written.

---

## PHASE 1: PARSE

`Steps: phase-1-2-parse-detect.md §Phase 1` (Steps 1-5). Exit when the Phase 1 checkpoint records, per thread: format, event count, geniro-run flag, and the expectation set with its degradation level.

## PHASE 2: DETECT

`Steps: phase-1-2-parse-detect.md §Phase 2` (Steps 1-3). Exit when every raw finding carries its `thread_id`, and a judge spawn that returned nothing usable is noted as a mechanical-only thread rather than presented as fully judged.

## PHASE 3: FILTER (orchestrator-inline)

`Steps: phase-3-4-filter-present.md §Phase 3` (Steps 1-3). No subagent. Exit when every finding is tagged, every kept finding carries a `fix_kind`, and the checkpoint records the kept and filtered counts.

## PHASE 4: PRESENT (WAIT — user gates)

`Steps: phase-3-4-filter-present.md §Phase 4` (Steps 1-6). Exit when every UNCERTAIN finding has an answered gate, the handoff (if chosen) is written via `atomic_state_write`, and the slug's state directory is removed.

---

## Task execution entry / state recovery

On invocation:

1. Resolve the thread set per Phase 1 Step 1, then compute `<slug>`: the thread's short id in single mode, `batch-<newest thread's short id>` in batch mode (never the project name, and never a bare timestamp — a slug must be stable enough for a resume to find it).
2. `Glob(".geniro/state/analyze-thread/<slug>/state.md")` — if found, run the helper's Case A/B/C/D mismatch UX before resuming.
3. If validating fails (per `skills/_shared/validate-state-file.md`), fire the recovery AUQ from that helper.
4. On clean start: print "Analyzing <basename> — phase 1 of 4", or "Analyzing <N> threads — phase 1 of 4", and proceed.

On resume from a checkpoint: skip completed phases, print "Resuming at phase N of 4", continue.

---

## REFERENCE

- `.claude/skills/analyze-thread/phase-1-2-parse-detect.md` — Phase 1 + Phase 2 Steps (Read on entry to Phase 1)
- `.claude/skills/analyze-thread/phase-3-4-filter-present.md` — Phase 3 + Phase 4 Steps, incl. the per-finding gate and the handoff emit (Read on entry to Phase 3)
- `.claude/skills/analyze-thread/analyze-thread-definition-of-done.md` — the run-completion checklist (Read on entry to Phase 4)
- `.claude/skills/analyze-thread/checks-reference.md` — canonical check taxonomy + per-check detection logic; §8 defines the expectation set the coverage checks compare against, §9 the default `fix_kind` per check
- `skills/_shared/load-custom-instructions.md` — the load / echo / refresh contract the I-class checks measure a run against
- `skills/_shared/phase-entry-read.md` — the phase-body Read and echo contract behind K2
- `skills/_shared/gate-rendering.md` — gate render-then-ask shape and the lean-question conventions behind K3-K5, K8
- `skills/_shared/skip-visibility.md` — the subagent load report and the assessed sentinel, the two proofs an echo cannot carry
- `.claude/skills/find-threads/scan.py` — the thread-discovery engine batch mode calls; its module docstring documents the output columns, config-dir roots (extended via `FIND_THREADS_EXTRA_ROOTS`), and the work-bearing classification
- `skills/_shared/within-skill-state-handoff.md` — slug rules + Case A/B/C/D resume UX
- `skills/_shared/atomic-state-write.md` — state-file write helper (mandatory)
- `skills/_shared/validate-state-file.md` — pre-resume validator + recovery AUQ
- `skills/_shared/state-tier-spec.md` — T1 / T1.5 / T2 lifecycle (handoff lives at T2)
- `skills/_shared/spawn-agent.md` — bare/prefixed/general-purpose degradation ladder
- `skills/_shared/model-tiering.md` — `model=` vs OMIT rules
- `skills/_shared/per-finding-question.md` — message-first per-finding gate protocol (the shape Phase 4 Step 2 fires)
- `.claude/skills/improve-template/SKILL.md` — handoff consumer
