---
name: analyze-thread
description: "Use when post-hoc analyzing saved Claude conversation threads for pipeline errors — wrong subagent tier, missed parallel-spawn, schema-invalid tool args, premature completion, instruction drift, hallucinated tools. Takes one or more thread paths, or with no argument analyzes the last few work-bearing threads across every project; a multi-thread run merges their findings with a recurrence count. Auto-detects JSONL (Claude Code session log) or markdown (UI export / paste). 4-phase loop: Parse → Detect (mechanical + LLM-judge) → Filter → Present with per-finding AUQ. Emits a handoff to /improve-template for approved fixes. Skip for live debugging (/geniro:debug) or pending-diff code review (/geniro:review)."
context: main
model: inherit
allowed-tools: [Read, Write, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[thread path(s) | thread count | empty = last 3 threads]"
---

# /analyze-thread — Post-hoc Claude Thread Failure Analyzer

You are the orchestrator for analyzing a saved Claude conversation thread and surfacing the errors Claude made while running a multi-phase pipeline. You parse the thread, run mechanical and judged checks against the canonical taxonomy, filter for relevance, then present findings with per-item user gates. You NEVER mutate the analyzed source files (this skill is read-only on the project under analysis); approved fixes are emitted as a handoff for `/improve-template` to apply.

**Input:** one or more thread file paths, a thread count, or nothing — an empty argument analyzes the last 3 work-bearing threads across every project (§Phase 1 Step 1).
**Output:** a findings report printed to chat + (on user approval) a handoff at `.geniro/state/handoff/from-analyze-thread-<branch>.md` that `/improve-template` consumes.

**After a compaction:** only this file's first ~5,000 tokens survive the summary — the spine (through §Definition of Done) is re-attached, the phase sections below it are not. Re-invoke `/analyze-thread` with the same argument before continuing; the §State Persistence checkpoint makes that a resume at the last completed phase, not a re-run.

---

## Phases

1. **Parse** — resolve the thread set (one path, or the last N threads machine-wide), then per thread: auto-detect format (JSONL session log vs markdown export/paste), normalize into an events list, extract spawn-sites / tool-calls / approval gates, detect whether the thread is a Geniro skill run.
2. **Detect** — per thread, run mechanical checks (deterministic grep/jq over normalized events) then one LLM-judge pass over that thread's excerpts with the canonical taxonomy seeded into the judge prompt.
3. **Filter** — orchestrator-inline relevance pass: merge the same defect across threads into one finding carrying its recurrence count, then drop REDUNDANT and FALSE-POSITIVE; keep TRUE-POSITIVE and UNCERTAIN.
4. **Present** — show grouped findings table; for every UNCERTAIN finding fire `AskUserQuestion` (fix / skip / challenge); for TRUE-POSITIVE findings default to "include in handoff" but let the user deselect; final AUQ chooses handoff destination.

A batch run changes what each phase iterates over, never the phase contract: the same checks, filter tags, and gates apply per thread, and only Phase 3's merge step is batch-specific.

The canonical taxonomy and per-check detection logic live in `${CLAUDE_PLUGIN_ROOT}/.claude/skills/analyze-thread/checks-reference.md`. SKILL.md keeps the phase narrative; the reference holds the per-check spec.

---

## Subagent Model Tiering

Follow the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. This skill has exactly one subagent spawn — the Phase 2 LLM-judge — and it OMITs `model=` so it inherits orchestrator tier (judging the thread is reasoning-grade work).

The Phase 4 handoff target (`/improve-template`) is a sibling skill, not a subagent — no tier consideration applies here.

---

## State Persistence

After completing each phase, write a checkpoint to `.geniro/state/analyze-thread/state-<slug>.md` (compute `<slug>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules — base it on the analyzed thread, never the project name; §Task execution entry gives the single- and batch-mode forms):

```
Branch: <git branch --show-current OR detached-<short-sha>>
Worktree: <git rev-parse --show-toplevel>
Timestamp: <ISO-8601 UTC>
Phase [N] completed: [phase name]
Mode: [single | batch]
Threads: [one line per thread — <thread_id> · <path> · <format> · <geniro-run> · <findings raw>]
Skipped: [one line per skipped thread — <thread_id> · <reason>]
Findings raw: [batch total from Phase 2]
Findings kept: [count from Phase 3, post-merge]
```

Use `atomic_state_write` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` — direct Edit/Write to state paths trips the `enforce-state-helper` hook.

Capital `Branch:` / `Worktree:` / `Timestamp:` are mandatory per the helper § Producer contract.

On skill start: compute `<slug>`, then `Glob(".geniro/state/analyze-thread/state-<slug>.md")`. If present, run the helper § Consumer contract (Case A/B/C/D mismatch handling). After "proceed", read the file and resume from the next incomplete phase.

---

## Loop Invariants

1. **Read-only on the analyzed source.** The thread file and any project files it references are never mutated by this skill. Mutating skills are `/improve-template` (template fixes) and `/geniro:implement` (consumer-code fixes) — both consume the handoff this skill emits.
2. **Mechanical before judged.** Phase 2 runs mechanical checks first because they are cheap, deterministic, and high-precision; the LLM-judge pass is then seeded with mechanical results so it does not re-discover them.
3. **One LLM-judge spawn per thread, all spawned in ONE assistant response, each carrying the taxonomy inline.** A single judge sees one thread's excerpts plus that thread's seeded mechanical findings — splitting into per-check spawns multiplies cost without improving signal (MAST showed one o1 pass at 94% accuracy / κ=0.77). In a batch, issue every thread's judge call in the same assistant turn, NOT one per turn — separate turns serialize the run and multiply wall-clock by the thread count. **This is the single rule for how the taxonomy reaches the judge:** the judge is a spawned subagent that shares none of your context and cannot be assumed to resolve `${CLAUDE_PLUGIN_ROOT}` inside its own run, so the taxonomy travels as inlined text — `checks-reference.md` §4 (the `[J]` table) in full, plus one line per mechanical check ID already run — never as a bare path it may fail to open, which would leave it judging against nothing and say so nowhere. Inline the short form only: §§1-3 detection logic, §5, §6 and §7 are orchestrator-side and would blow the 8 K seed budget.
4. **A defect in N threads is one finding, not N.** Phase 3 merges the same check firing on the same root cause across threads into a single finding whose recurrence count is evidence of severity, not a duplicate to discard. Recurrence is the batch's whole point: one thread cannot distinguish an instruction the model happened to skip once from an instruction it skips systematically.
5. **Never analyze this session's own log.** Its trace has no conclusion to judge, and analyzing the run that is doing the analyzing yields findings about the analysis in progress. Identify it by session id, not by timestamp (§Phase 1 Step 1) — other sessions touch their logs while merely sitting open, so an age cutoff drops finished threads and still misses nothing this rule does not already catch.
6. **Filter before user.** Phase 3 drops REDUNDANT and FALSE-POSITIVE findings BEFORE the Phase 4 presentation. The user sees only TRUE-POSITIVE + UNCERTAIN. Filtered items appear in a separate "Filtered" section for transparency.
7. **Per-finding AUQ for UNCERTAIN, batch AUQ for confidence-high.** Mechanical-detected with high confidence go into the default-approve bucket the user can deselect; LLM-judged with low/medium confidence each get their own AUQ.
8. **No silent auto-default.** Empty AUQ answers indicate an upstream tool bug and must be re-asked — never auto-default to "skip".

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll skip Phase 1 Step 4 metadata extraction — the user said the thread is a Geniro run" | Phase 1 Step 4 detects WHICH skill ran, not WHETHER one ran. Plugin-specific checks reference skill-name-tagged anti-rationalization tables; without the skill identity, those checks misfire on every run. |
| "I'll batch all uncertain findings into one multiSelect AUQ to save user clicks" | Per-finding AUQ is what the user explicitly requested — they want to see evidence per finding and decide individually. MultiSelect collapses the evidence-review step, which is the point of UNCERTAIN. |
| "The thread is small — skip the parse step, just regex the markdown" | Phase 1's normalized events list is the substrate for Phase 2's mechanical checks. Skipping parse means every check turns into a bespoke regex and the false-positive rate explodes (memory: "mechanical pre-pass" is high-precision precisely because it operates on structured events). |
| "I'll spawn one judge per check instead of one judge for all judged checks" | MAST showed one o1 pass over the full thread + seeded taxonomy achieves 94% accuracy. Per-check spawns multiply token cost N times with no signal gain, and the judges can't cross-reference findings. |
| "The LLM-judge already produced findings — skip the mechanical pre-pass" | Mechanical checks are deterministic and catch what the judge will miss (schema validation, retry-loop window matching, identical-prompt over-spawn). The judge needs mechanical results as context to avoid re-discovering them. |
| "Findings_raw is 80, but they look real — present them all" | The 60-cap is a parser-sanity tripwire, not a UX preference. 80 raw findings on one thread means either the events list is malformed (Phase 1 bug) or every check is firing (taxonomy bug). Halt and have the user re-verify input. |
| "The user said 'analyze this thread', they obviously want fixes too — I'll edit the source files directly" | Read-only is invariant #1. This skill detects; `/improve-template` fixes. Cross-skill responsibility separation is documented in CLAUDE.md `## Skill routing` — collapsing it makes the analyzer a refactorer, breaking the user's mental model. |
| "I already know what's in `checks-reference.md` from training data — don't bother reading it" | The reference file is the source of truth; it can be edited by the user between runs. Loading it at Phase 2 entry ensures the detection logic matches the current taxonomy, not a stale snapshot. |
| "Empty AUQ answer = user wants to skip" | Per `feedback_canonical_rules.md` and the universal AUQ rule: empty answers indicate an upstream tool bug. Re-ask. Never auto-default. |
| "I'll give the judge the path to `checks-reference.md` instead of inlining it — saves the seed tokens" | Invariant #3 is the rule: short-form taxonomy inline. A spawned subagent shares none of your context and may not resolve `${CLAUDE_PLUGIN_ROOT}`; a path it cannot open produces a judge that reports findings against no taxonomy and never signals the degradation. Trim by leaving out the orchestrator-side sections, not by replacing the text with a path. |
| "No argument given — I'll ask the user which thread they meant" | Every input shape resolves without a question (Phase 1 Step 1): empty means the last 3 work-bearing threads. Asking re-imposes the browse-and-paste step the batch default exists to remove, and the user who typed no argument has already told you what they want. |
| "The newest log is the freshest data — analyze it first" | The newest log is this session's own (invariant #5): every finding it yields describes the analysis in progress rather than past work. Exclude it by session id. Do not generalize that into an age cutoff — idle open tabs touch their logs constantly, so a timestamp filter drops finished threads while adding nothing. |
| "Three threads flagged the same check — that's the same finding twice, drop the duplicates" | Within one thread, yes. Across threads it is the strongest signal the batch produces: a defect reproduced in independent runs is systematic, not incidental. Merge into one finding carrying its recurrence count (invariant #4); dropping the extra occurrences discards exactly the evidence that justifies the fix. |

---

## Budgets & Quality Gates

| Budget | Value | Why |
|---|---|---|
| Threads per batch | default 3; hard cap 5 | Each thread costs its own judge spawn and its own mechanical pass. Past 5 the merged report outgrows the per-finding AUQ ladder and the wall-clock stops being worth the added recurrence signal. A count above the cap is clamped, with the clamp stated to the user |
| Thread file size | hard cap 5 MB; warn at 1 MB | JSONL session logs can grow large; >5 MB likely a merged multi-session log that should be split first. In a batch, an oversize thread is skipped and named in the report rather than aborting the run |
| LLM-judge token budget | seed prompt ≤ 8 K tokens, thread excerpts ≤ 60 K tokens | The seed is the inlined short-form taxonomy plus that thread's mechanical findings (invariant #3). Per thread, and each judge has its own context, so a batch does not share this budget. Excerpts are sliced to the top-3 most-suspicious sections per check, not the full thread, to fit the 200 K context with headroom |
| Findings raw cap | 60 per thread | More than 60 raw findings on one thread = the parser misclassified the format; halt and ask user to re-check input. Applies per thread, not to the batch total |
| Findings kept cap | 25 surfaced to user | Counted AFTER the Phase 3 cross-thread merge, so a defect recurring in 3 threads consumes one slot. Past 25 the AUQ ladder becomes unworkable; if more survive, sort by recurrence × severity × confidence and truncate, noting the tail count |

---

## ACI per-phase tool surface

| Phase | Tools used | Notes |
|---|---|---|
| 1 Parse | Read, Bash (`scan.py`, `head`, `file`, `jq`, `wc`) | Bash runs the thread-discovery scan in batch mode, then format sniffing and JSONL parsing; Read for the thread file |
| 2 Detect | Bash (`jq`, `grep`, `awk`), Agent | Bash for mechanical checks; Agent for the per-thread LLM-judge spawns, issued together in one response |
| 3 Filter | (orchestrator inline) | No tools — orchestrator reads the Phase 2 output, merges across threads, and tags each finding |
| 4 Present | AskUserQuestion, Write | AUQ for the per-finding gates and the final handoff AUQ; Write for the T2 handoff file (via atomic-write helper) |

Glob is permitted across phases for state-file lookup and helper resolution but is not the workhorse tool.

---

## Definition of Done

- [ ] Phase 1 Step 1: thread set resolved from `$ARGUMENTS` with no question asked; batch mode excluded this session's own log by id and skipped oversize logs, naming the skips; count clamped to 5; resolved set echoed to the user
- [ ] Phase 1: per thread — format detected, events list normalized, geniro-run flag set, metadata extracted
- [ ] Phase 1 checkpoint written via `atomic_state_write`, recording the resolved set
- [ ] Phase 2 mechanical checks all run per thread (per `checks-reference.md` §§1-3 — Mechanical checks A/B/C-class)
- [ ] Phase 2 LLM-judge: one Agent call per thread, all issued in ONE assistant response, OMITted `model=`, short-form taxonomy inlined per invariant #3 alongside that thread's mechanical results and excerpts; any judge that returned nothing usable is noted as a mechanical-only thread
- [ ] Phase 2 checkpoint written; every finding carries its `thread_id`; per-thread findings_raw under the 60-cap
- [ ] Phase 3 Step 1: cross-thread merge applied; recurring defects collapsed to one finding with `threads: [...]`; recurrence raised confidence but never severity
- [ ] Phase 3 Step 2: each finding tagged TRUE-POSITIVE / UNCERTAIN / REDUNDANT / FALSE-POSITIVE
- [ ] Phase 3 checkpoint written; post-merge findings_kept under the 25-cap (or truncated with tail note)
- [ ] Phase 4 Step 1: findings table printed with the Analyzed/Skipped thread list and Confirmed / Uncertain / Filtered sections
- [ ] Phase 4 Step 2: per-finding AUQ fired for each UNCERTAIN; sequential, not batched
- [ ] Phase 4 Step 3: final handoff-routing AUQ fired
- [ ] Phase 4 Step 4: handoff file written via `atomic_state_write` if user chose to emit
- [ ] Phase 4 Step 5: `/improve-template` invoked if user chose "launch now"
- [ ] Phase 4 Step 6: state-<slug>.md cleaned up per helper § Cleanup contract
- [ ] No mutations to the analyzed thread file or any project file outside `.geniro/state/` and `.geniro/state/handoff/`

---

## PHASE 1: PARSE

**Purpose:** Turn each raw thread file into a normalized events list the detection phase can operate on. Step 1 resolves which threads; Steps 2-5 run per thread in that set.

### Step 1: Resolve the thread set

`$ARGUMENTS` takes one of three shapes. Resolve it without asking — every shape has a defined answer.

| `$ARGUMENTS` | Mode | Thread set |
|---|---|---|
| a path or bare filename | single | that one thread |
| two or more paths | batch | exactly those threads, in the order given |
| a bare integer N, or `--last=N` | batch | the last N work-bearing threads |
| empty | batch | the last 3 work-bearing threads |

**Single mode.** Resolve the path; for a bare filename search the current working tree first, then the config-dir `projects/` trees. Check the file exists, is readable, and is under the 5 MB hard cap. Between 1 MB and 5 MB, warn before continuing — large threads slow the judge pass.

**Explicit paths.** Two or more paths skip discovery and run as a batch over exactly those threads — this is how `/find-threads` hands over a multi-thread pick, and running them as one batch instead of N single runs is what earns the Phase 3 recurrence merge. Apply the single-mode existence and size checks to each; skip and name an oversize one rather than aborting; exclude this session's own log even when it is named (invariant #5); clamp to the 5-thread cap and say so.

**Batch mode.** Discover threads with the sibling scan engine, which already enumerates every config-dir root, keeps only threads that did agentic work, and reports each thread's size and true project label:

```bash
python3 "<this skill's base directory>/../find-threads/scan.py" 2>/dev/null | sort -t$'\t' -k1,1nr
```

It prints one TSV row per thread — `mtime · date · oversize · kind · turns · relevance · hits · label · title · path · snippet` — and the sort makes it newest-first across all projects. Walk the rows top-down and take the first N that survive both filters:

- **Skip this session's own log** (invariant #5). Identify it by session id: the session scratchpad directory path ends `<session-id>/scratchpad`, and the log filename is `<session-id>.jsonl`. When no scratchpad path is available, fall back to skipping the newest thread whose project label equals the current working directory — a session running this skill from that directory is writing exactly that log.
- **Skip an oversize log** (`oversize` column = 1). Name it in the report so the skip is visible; do not abort the batch.

Do NOT filter on `mtime` age. A recent timestamp means a session tab is open, not that a run is in progress — idle sessions keep touching their logs, so an age cutoff silently drops finished threads that are the most interesting ones. The only log that must be excluded is this one.

Post-process the scan output in a single command, never a per-file shell loop: on macOS the zsh sandbox strips `PATH` inside a `while` / `for` body, so `tail`/`cut`/`awk` vanish partway through and the run half-fails.

Clamp N to the 5-thread cap and say so if the user asked for more. If the scan yields nothing — a fresh machine, no work-bearing threads — report that plainly and stop; there is nothing to analyze and no question worth asking.

If `scan.py` is absent (the sibling skill was removed), fall back to enumerating `*.jsonl` under `~/.claude/projects/`, `$CLAUDE_CONFIG_DIR/projects/` when set, newest-first by mtime, applying the same two filters. The fallback loses the work-bearing filter, so state that the set may include trivial threads.

Echo the resolved set before Phase 1 Step 2 — one line per thread with its date, project label, and title — so the user sees what is about to be analyzed.

### Step 2: Auto-detect format

Sniff the first 200 bytes with `head -c 200 <file>`. Detection rules:

- Begins with `{"type":"summary"` or `{"type":"user"` or `{"type":"assistant"` followed by a comma — **JSONL** (Claude Code session log).
- Begins with `# `, `## `, or `**User:**` / `**Assistant:**` block markers — **markdown**.
- Otherwise — fall back to markdown and warn the user that parsing degrades to heuristic regex.

Record the detected format in the Phase 1 checkpoint.

### Step 3: Normalize to events list

Each check queries the thread file for the fields below with `jq` / `grep` — the events list is a projection over the file, never a multi-MB log read into your context. One row per event:

| Field | Source — JSONL | Source — markdown |
|---|---|---|
| `idx` | line number in the .jsonl | block index in the .md |
| `role` | `.type` field (`user` / `assistant` / `tool_use` / `tool_result` / `summary`) | regex on block header (`**User:**` → user, etc.) |
| `content` | `.message.content` array | block body |
| `tool_name` | `.message.content[].name` when `tool_use` | regex on fenced ```` ```tool ```` blocks |
| `tool_input` | `.message.content[].input` JSON | regex-extracted JSON block (best-effort) |
| `timestamp` | `.timestamp` ISO field | not available — use idx as proxy |

JSONL parsing uses `jq -Rc 'fromjson?'` per the project memory rule — never bare `jq -c` (jq aborts on first parse error, silently wedging the pipeline).

### Step 4: Extract pipeline metadata

Scan the events list for Geniro-skill signals:

- Was a `/geniro:<skill>` slash command invoked? → `geniro-run: yes` + record which skill.
- Was an `Agent(subagent_type=...)` call made? → record spawn sites for Phase 2 checks A1-A7.
- Was an `AskUserQuestion` call made? → record approval gates for Phase 2 check D2.
- Was a TodoWrite call made? → record final state for Phase 2 check D3.
- Were `${CLAUDE_PLUGIN_ROOT}` / `_shared/` paths referenced? → confirms plugin-context.

Skip plugin-specific checks (the `[plugin]` rows in checks-reference.md) when `geniro-run: no` AND no plugin signals appear. Generic checks still apply.

### Step 5: Write Phase 1 checkpoint

Record, per thread: file path, format, byte count, events count, geniro-run flag, detected skill name (if any), spawn-site count, AUQ-gate count. In a batch, also record the resolved set and anything skipped (live, oversize) so a resume re-uses the same set instead of re-resolving against a moved "last 3".

---

## PHASE 2: DETECT

**Purpose:** Run every check in the taxonomy against each thread's normalized events list and produce a raw findings list for filtering. Every finding carries its thread id from here on — Phase 3 cannot merge across threads without it.

### Step 1: Run mechanical checks

For each `[M]` check in `${CLAUDE_PLUGIN_ROOT}/.claude/skills/analyze-thread/checks-reference.md` (see § Mechanical checks reference table), run the documented detection logic. Detection logic is one of three shapes:

- **jq predicate** over the JSONL events (e.g., A6 over-spawn detects identical `tool_input` across two `tool_use` events in the same assistant turn).
- **grep pattern** over the event content (e.g., G2 `--no-verify` scan).
- **windowed sequence match** over the events list (e.g., B3 infinite-loop detects same `tool_name` + same `tool_input` 3+ times in a sliding window of 5 events).

Each mechanical hit produces a draft finding: `{thread_id, check_id, category, severity, confidence: high, evidence: [event_idx range], rationale}`. Mechanical confidence is always `high` — the rule either matched or it didn't. `thread_id` is the session log's short id (first 8 chars of its filename), which stays readable in the merged report.

### Step 2: Spawn the LLM-judge

ONE agent spawn per thread, and in a batch every one of them goes in the SAME assistant response (invariant #3). Pre-inline, per spawn:
- The short-form taxonomy per invariant #3 — `checks-reference.md` §4 in full plus one line per mechanical check ID, as text in the prompt, never as a path.
- The mechanical findings from Step 1 (so the judge doesn't re-discover them and can use them as context).
- The top-3 most-suspicious thread excerpts per `[J]` check, sliced to keep total excerpts ≤ 60 K tokens. Suspicion ranking heuristic: events near mechanical-finding clusters, events near `AskUserQuestion` calls, events near phase-boundary narration ("Phase 3:", "shipping", "review").

```
Agent(subagent_type="general-purpose", prompt="""
## Task: Judge thread for documented failure modes

You are reviewing ONE saved Claude conversation thread ({{thread_id}}) to detect
failure modes that were committed during execution. You do NOT fix anything — you
only detect and report. The mechanical pre-pass has already found some issues;
build on those, don't re-discover them.

### Canonical taxonomy ([M] / [J] / scope tags)
{{checks-reference.md §4 table verbatim + one line per mechanical check ID}}

### Mechanical findings already detected
{{mechanical findings from Step 1, as a table}}

### Thread excerpts (top-3 per judged check)
{{excerpts}}

### Your task

For each `[J]` check that mechanical did NOT already cover, scan the excerpts
and report findings as a JSON array, one object per finding:

{
  "thread_id": "{{thread_id}}",
  "check_id": "E2",
  "category": "Instruction-following & drift",
  "severity": "warning",
  "confidence": "medium",
  "evidence": [{"event_idx": 47, "excerpt": "first 200 chars"}],
  "rationale": "one-paragraph explanation"
}

Severity ladder: blocker | warning | nit.
Confidence ladder: high (unambiguous in trace) | medium (plausible but contestable) |
low (heuristic match, would need a second pair of eyes).

Also surface NOVEL findings — patterns of failure you spotted that don't fit any
documented check. Tag those with check_id = "NOVEL-N" and add a
`novel_pattern_name` field.

Do NOT propose fixes. Do NOT speculate on intent. Stick to what the trace shows.
Return ONLY the JSON array, no preamble.
""", description="Judge: thread failure detection")
```

### Step 3: Merge and write checkpoint

Combine mechanical findings + judge findings into a single raw list, each entry keeping its `thread_id`. Write checkpoint with `findings-raw: <count>` (per thread in a batch). If any one thread exceeds the 60-cap, halt and report — that signals a parser misclassification on that thread.

A judge spawn that returns nothing usable (empty, unparseable, or the agent errored) leaves its thread with mechanical findings only. Note the degradation in the checkpoint and the Phase 4 report; do not silently present a mechanical-only thread as fully judged, and do not re-spawn more than once.

---

## PHASE 3: FILTER (orchestrator-inline)

**Purpose:** Merge the batch, then triage raw findings to TRUE-POSITIVE / UNCERTAIN / drop the rest. No subagent — this is reasoning over Phase 2's structured output.

### Step 1: Merge across threads (batch only)

Collapse findings that share a `check_id` AND the same underlying defect into ONE finding carrying `threads: [<thread_id>, ...]`. Same check on a genuinely different root cause stays separate — the test is whether one fix in one place resolves every occurrence. Keep each thread's evidence range under its own thread id; a merged finding's evidence reads `<thread_id>:<event range>` per occurrence.

Recurrence then feeds triage: a defect confirmed in 2+ threads is systematic rather than incidental, so it enters Step 2 one confidence level higher (low → medium, medium → high) and sorts above single-thread findings of equal severity. It never raises severity — how often a defect happens and how much damage it does are independent.

In single mode this step is a no-op; every finding carries one thread id.

### Step 2: Tag each finding

For each finding, the orchestrator tags one of four:

| Tag | When | Action |
|---|---|---|
| **TRUE-POSITIVE** | High confidence + evidence event range cleanly matches the check spec + no contradicting context | Keep; default-include in Phase 4 handoff |
| **UNCERTAIN** | Medium/low confidence, OR evidence range ambiguous, OR judge tagged as "plausible but contestable" | Keep; per-item AUQ in Phase 4 |
| **REDUNDANT** | Duplicate of another finding **within the same thread** (same root cause, different surface symptom), OR mechanical-and-judge both flagged the same event range | Drop; merge evidence into the surviving finding. The same defect in a DIFFERENT thread is never redundant — Step 1 already merged it and its recurrence is the signal (invariant #4) |
| **FALSE-POSITIVE** | The mechanical regex matched a benign case (e.g., A6 over-spawn flagged a TodoWrite that legitimately listed 5 parallel items), OR the judge flagged something that contradicts a documented exception in the skill body | Drop; log reason for Phase 4 transparency section |

For NOVEL findings: always UNCERTAIN unless the rationale ties to a documented anti-rationalization row in some skill body's table — then TRUE-POSITIVE.

Write Phase 3 checkpoint with `findings-kept: <count>`, `filtered: <count + reasons summary>`, and in a batch `merged: <raw count> → <merged count>`.

---

## PHASE 4: PRESENT (WAIT — user gates)

**Purpose:** Show the user grouped findings, gate UNCERTAIN ones individually, and emit the handoff.

### Step 1: Print the findings table

Group by category. Within each category, sort by recurrence (most threads first), then severity (blocker → warning → nit), then confidence (high → low).

```
## Analysis: <thread basename, or "N threads" in batch mode>

Analyzed:
- <thread_id> · <date> · <project label> · <title> · <events> events · Geniro-run: <yes/no — skill: <name>>
- (one line per thread; in single mode this is one line)
Skipped: <thread_id> (still being written) · <thread_id> (7.2 MB, over the 5 MB cap)

### Confirmed findings (default-include)
| # | Threads | Category | Check | Severity | Confidence | Evidence | Suggested fix target |
|---|---|---|---|---|---|---|---|
| 1 | 3/3 | Subagent spawning | A1 missed parallel-spawn | warning | high | a1f42fdd:12-14 · d34948e9:88-91 · 0cd65de4:40-44 | skills/review/SKILL.md §Phase 2 |
| ...

### Uncertain findings (gated below)
| # | Threads | Category | Check | Severity | Confidence | Evidence | Rationale |
| 5 | 1/3 | Context | H1 first-vs-last contradiction | warning | medium | a1f42fdd:4 vs 198 | judge: "user asked X early, agent did not-X at the end without acknowledgement" |
| ...

### Filtered (transparency)
- a1f42fdd check_id=A6 event-range=22-23 — FALSE-POSITIVE: TodoWrite legitimately listed 5 items, not duplicate spawns
- a1f42fdd check_id=E4 event-range=87 — REDUNDANT: same root cause as finding #3
```

Drop the `Threads` column in single mode — a column reading `1/1` on every row is noise.

### Step 2: Gate uncertain findings

For EACH uncertain finding, fire `AskUserQuestion` (do NOT batch into one multiSelect — per-finding gating is what the user asked for):

- **Question:** "Finding #<N> (<check_id> — <one-line rationale>; seen in <M> of <T> threads): keep, drop, or challenge?"
- **Options:**
  - "Keep — include in handoff"
  - "Drop — false positive"
  - "Challenge — show me the full evidence excerpt and re-decide" (loops back with the full thread slice)

Process answers in sequence. Add KEPT items to the confirmed list; record DROPPED items in the filtered section.

### Step 3: Final user gate on confirmed list

Print the updated confirmed list (including newly-promoted UNCERTAIN items). Fire ONE final `AskUserQuestion`:

- **Question:** "Confirmed findings ready. How to hand off?"
- **Options:**
  - "Emit handoff and launch /improve-template now (Recommended)"
  - "Emit handoff only — I'll run /improve-template later"
  - "Drop specific findings before handoff" — loops back with multiSelect over the confirmed list
  - "Skip — no handoff; the printed report is enough"

### Step 4: Emit the handoff

If the user chose either of the first two options, write `.geniro/state/handoff/from-analyze-thread-<branch>.md` via `atomic_state_write`. Emit each kept finding as a machine-readable `open_questions[]` frontmatter entry per the T2 contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 (each entry needs `id` / `source` / `question` / `status`; `severity`, `recurrence`, and `suggested_action` are producer-specific extensions). The body `## Open questions` block is a human-readable mirror only — the frontmatter array is the source of truth a consumer parses.

```yaml
---
tier: T2
producer: analyze-thread
schema-version: 1
branch: <current branch>
timestamp: <ISO-8601 UTC>
consumer: improve-template
source_threads:                        # one entry per analyzed thread; single mode has one
  - id: <thread_id>
    path: <path>
findings_count: <N>
open_questions:
  - id: q1
    source: <check_id>                 # the check that surfaced the finding, e.g. A1
    question: "<one-line finding summary>"
    context: |                         # OPTIONAL — 2-6 line problem framing
      <category> — <what the trace shows>. Suggested target: <file>.
    related_findings: []               # finding has no /review F-id; leave empty
    severity: <blocker|warning|nit>    # producer-specific extension
    recurrence: <M>/<T>                # producer-specific extension — threads hit / threads analyzed
    suggested_action: <one sentence — usually "rewrite instruction at <anchor>" or "add anti-rationalization row" or "extend Phase N gate">
    status: unresolved
  # (one entry per kept finding: q2, q3, ...)
---

## Open questions
- [ ] q1 (<check_id> — <category>, seen in <M>/<T> threads): <one-line>. Target: <file>. Evidence: <thread_id>:<range>. Suggested action: <one sentence>.

(one bullet per kept finding, mirroring the frontmatter entry by `id`)
```

`/improve-template` reads this handoff when invoked with the `process-handoff` argument (Mode Detection → Complexity Gate handoff-ingestion path) and routes each parsed finding to its appropriate flow (Phase 1-fast / full pipeline depending on complexity).

### Step 5: If "launch now", invoke /improve-template

Print a one-line summary of the handoff and call `/improve-template` with `$ARGUMENTS` set to "process handoff from analyze-thread". `/improve-template` will pick up the handoff file from its standard read location.

If the user chose "emit handoff only" or "skip": print the handoff path and the exact command (`/improve-template process-handoff`) for them to run later.

### Step 6: Cleanup

Remove `.geniro/state/analyze-thread/state-<slug>.md` per the helper § Cleanup contract — delete only the current branch's slug, never globbing all state files.

The handoff file at `.geniro/state/handoff/from-analyze-thread-<branch>.md` is T2 and survives until `/improve-template` consumes it (per the standard handoff lifecycle in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md`).

---

## Modifier handling

| Modifier in `$ARGUMENTS` | Effect |
|---|---|
| `--last=N` (or a bare integer) | Batch mode over the last N work-bearing threads, clamped to the 5-thread cap. Same as passing nothing, which uses N=3. |
| `--mechanical-only` | Skip Phase 2 Step 2 LLM-judge spawn; only mechanical checks run. Cheaper and faster but loses every judged check. Pairs well with a large batch, where the judges dominate cost. |
| `--no-handoff` | Phase 4 Step 4 skipped; the findings report is printed and no handoff file is written. Useful when the user wants to read findings without committing to fix anything. |
| `--strict` | Tighten Phase 3 filter: treat medium-confidence findings as TRUE-POSITIVE not UNCERTAIN (skips per-item AUQ, includes them by default). Use when running on a thread the user already trusts to be problematic. |
| `--lenient` | Loosen Phase 3 filter: treat high-confidence judged findings as UNCERTAIN (forces AUQ). Use on threads where many findings are likely benign. |
| `--format=jsonl` / `--format=markdown` | Skip Phase 1 Step 2 auto-detect and force the format. Use when sniffing misclassifies. |

---

## Task execution entry / state recovery

On invocation:

1. Resolve the thread set per Phase 1 Step 1, then compute `<slug>`: the thread's short id in single mode, `batch-<newest thread's short id>` in batch mode (never the project name, and never a bare timestamp — a slug must be stable enough for a resume to find it).
2. `Glob(".geniro/state/analyze-thread/state-<slug>.md")` — if found, run the helper's Case A/B/C/D mismatch UX before resuming.
3. If validating fails (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md`), fire the recovery AUQ from that helper.
4. On clean start: print "Analyzing <basename> — phase 1 of 4", or "Analyzing <N> threads — phase 1 of 4", and proceed.

On resume from a checkpoint: skip completed phases, print "Resuming at phase N of 4", continue.

---

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/.claude/skills/analyze-thread/checks-reference.md` — canonical check taxonomy + per-check detection logic
- `${CLAUDE_PLUGIN_ROOT}/.claude/skills/find-threads/scan.py` — the thread-discovery engine batch mode calls. Its module docstring documents every output column, the config-dir roots it scans, and the work-bearing classification. Add a new config dir by exporting `FIND_THREADS_EXTRA_ROOTS` (colon-separated), which overrides its `EXTRA_ROOTS` default
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` — slug rules + Case A/B/C/D resume UX
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` — state-file write helper (mandatory)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md` — pre-resume validator + recovery AUQ
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` — T1 / T1.5 / T2 lifecycle (handoff lives at T2)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` — bare/prefixed/general-purpose degradation ladder
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` — `model=` vs OMIT rules
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` — message-first per-finding gate protocol (the shape Phase 4 Step 2 fires)
- `${CLAUDE_PLUGIN_ROOT}/.claude/skills/improve-template/SKILL.md` — handoff consumer
