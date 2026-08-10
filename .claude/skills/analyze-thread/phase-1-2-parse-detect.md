# /analyze-thread — Phase 1 & Phase 2

Phase bodies for `.claude/skills/analyze-thread/SKILL.md`. Read on entry to Phase 1; re-read on entry to Phase 2 and on any resumption of either, including after a compaction — the spine keeps the phase headings, the loop invariants, the anti-rationalization table, and the Definition of done, this file carries the Steps.

## Contents

- Phase 1 — Parse (Steps 1-5)
- Phase 2 — Detect (Steps 1-3, incl. the LLM-judge spawn template)

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

**Single mode.** Resolve the path; for a bare filename search the current working tree first, then the config-dir `projects/` trees. Check the file exists, is readable, and is under the hard cap (SKILL.md §Budgets & quality gates — Thread file size row). Between the warn threshold and the hard cap, warn before continuing — large threads slow the judge pass.

**Explicit paths.** Two or more paths skip discovery and run as a batch over exactly those threads — this is how `/find-threads` hands over a multi-thread pick, and running them as one batch instead of N single runs is what earns the Phase 3 recurrence merge. Apply the single-mode existence and size checks to each; skip and name an oversize one rather than aborting; exclude this session's own log even when it is named (invariant #5); clamp to the 5-thread cap and say so.

**Batch mode.** Discover threads with the sibling scan engine, which already enumerates every config-dir root, keeps only threads that did agentic work, and reports each thread's size and true project label:

```bash
python3 "<this skill's base directory>/../find-threads/scan.py" 2>/dev/null | sort -t$'\t' -k1,1nr
```

It prints one TSV row per thread — `mtime · date · oversize · kind · turns · relevance · hits · label · title · path · snippet` — and the sort makes it newest-first across all projects. Walk the rows top-down and take the first N that survive both filters:

- **Skip this session's own log** (invariant #5). Identify it by session id: the session scratchpad directory path ends `<session-id>/scratchpad`, and the log filename is `<session-id>.jsonl`. When no scratchpad path is available, fall back to skipping the newest thread whose project label equals the current working directory — a session running this skill from that directory is writing exactly that log.
- **Skip an oversize log** (`oversize` column = 1). Name it in the report so the skip is visible; do not abort the batch.

Do NOT filter on `mtime` age. A recent timestamp means a session tab is open, not that a run is in progress — idle sessions keep touching their logs, so an age cutoff silently drops finished threads that are the most interesting ones. The only log that must be excluded is this one.

Post-process the scan output in one command, never a per-file shell loop — the sandbox constraint that makes such a loop half-fail is documented in `scan.py`'s module docstring.

Clamp N to the 5-thread cap and say so if the user asked for more. If the scan yields nothing — a fresh machine, no work-bearing threads — report that plainly and stop; there is nothing to analyze and no question worth asking.

If `scan.py` is absent (the sibling skill was removed), fall back to enumerating `*.jsonl` under `~/.claude/projects/`, `$CLAUDE_CONFIG_DIR/projects/` when set, newest-first by mtime, applying the same two filters. The fallback loses the work-bearing filter, so state that the set may include trivial threads.

Echo the resolved set before Phase 1 Step 2 — one line per thread with its date, project label, and title — so the user sees what is about to be analyzed.

### Step 2: Auto-detect format

Sniff the file's opening bytes. Detection rules:

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

Query the thread for Geniro-skill signals:

- Was a `/geniro:<skill>` slash command invoked? → `geniro-run: yes` + record which skill.
- Was an `Agent(subagent_type=...)` call made? → record spawn sites for Phase 2 checks A1-A7.
- Was an `AskUserQuestion` call made? → record approval gates for Phase 2 check D2.
- Was a TodoWrite call made? → record final state for Phase 2 check D3.
- Were `CLAUDE_PLUGIN_ROOT`-rooted / `_shared/` paths referenced? → confirms plugin-context.

Skip plugin-specific checks (the `[plugin]` rows in checks-reference.md) when `geniro-run: no` AND no plugin signals appear. Generic checks still apply.

### Step 4b: Build the expectation set

The A-H checks read an action and ask whether it was wrong. The I- and K-class checks ask what is *missing* — an instruction file never loaded, a phase never entered, an approval never asked — and a missing thing has no event to match on. They need a declared side, and Step 4b is where it is built.

Project it out of the trace, per the field list and the degradation ladder in `checks-reference.md` §8. Everything needed is in the thread: the injected skill body carries the phases, phase-body pointers, load sites, and gates; each instruction file's own tool_result carries the blocks it shipped. Where a field is missing, take the §8 degradation rather than substituting this checkout for it (invariant #9), and let the weakening travel with each finding instead of being decided once for the thread.

Skip the step when `geniro-run: no` — a thread with no skill run declares nothing (invariant #10). Echo the set's shape in one line so the user can see what coverage will be measured against, and spot a parse that read nothing.

### Step 5: Write Phase 1 checkpoint

Record, per thread: file path, format, byte count, events count, geniro-run flag, detected skill name (if any), spawn-site count, AUQ-gate count, and the expectation set with the degradation level it was built at (full trace / partial trace / project-read / none). In a batch, also record the resolved set and anything skipped (live, oversize) so a resume re-uses the same set instead of re-resolving against a moved "last 3".

---

## PHASE 2: DETECT

**Purpose:** Run every check in the taxonomy against each thread's normalized events list and produce a raw findings list for filtering. Every finding carries its thread id from here on — Phase 3 cannot merge across threads without it.

### Step 1: Run mechanical checks

For each `[M]` check in `.claude/skills/analyze-thread/checks-reference.md` (see § Mechanical checks reference table), run the documented detection logic. Detection logic is one of three shapes:

- **jq predicate** over the JSONL events (e.g., A6 over-spawn detects identical `tool_input` across two `tool_use` events in the same assistant turn).
- **grep pattern** over the event content (e.g., G2 `--no-verify` scan).
- **windowed sequence match** over the events list (e.g., B3 infinite-loop detects same `tool_name` + same `tool_input` 3+ times in a sliding window of 5 events).

Each mechanical hit produces a draft finding: `{thread_id, check_id, category, severity, confidence: high, evidence: [event_idx range], rationale}`. Mechanical confidence is always `high` — the rule either matched or it didn't. `thread_id` is the session log's short id (first 8 chars of its filename), which stays readable in the merged report.

The I- and K-class coverage checks are the exception on both counts, because they match on an absence rather than an event: they roll up per declaration site rather than per item, and their confidence tracks how much of the trace you could see rather than how cleanly the rule matched. Both rules are canonical in `checks-reference.md` §I-class.

### Step 2: Spawn the LLM-judge

ONE agent spawn per thread, and in a batch every one of them goes in the SAME assistant response (invariant #3). The judge is a spawned subagent that shares none of your context and cannot be assumed to resolve a `CLAUDE_PLUGIN_ROOT`-rooted path inside its own run, so the taxonomy travels as inlined text, never as a bare path it may fail to open — a bare path would leave it judging against nothing and say so nowhere. Pre-inline, per spawn:
- The short-form taxonomy — `checks-reference.md` §4 (the `[J]` table) in full, plus one line per mechanical check ID already run. §§1-3 detection logic, §5, §6, and §7 are orchestrator-side and stay out of the seed — inlining them would blow the seed budget (SKILL.md §Budgets & quality gates — LLM-judge token budget row).
- **This thread's expectation set** from Phase 1 Step 4b, with the degradation level it was built at. The judged coverage checks (the judged I/K-class rows in `checks-reference.md` §4) have no declared side without it and silently return nothing; the judge cannot re-derive it, because the turns it came from may not survive the excerpt slice. Send the set itself, never a pointer.
- The mechanical findings from Step 1 (so the judge doesn't re-discover them and can use them as context).
- The most-suspicious thread excerpts, ranked and sliced per `checks-reference.md` §7, which carries the weighted signal set and the always-include opening and closing turns. Keep the total within the excerpt budget (same Budgets row).

```
Agent(subagent_type="general-purpose", prompt="""
## Task: Judge thread for documented failure modes

You are reviewing ONE saved Claude conversation thread ({{thread_id}}) to detect
failure modes that were committed during execution. You do NOT fix anything — you
only detect and report. The mechanical pre-pass has already found some issues;
build on those, don't re-discover them.

### Canonical taxonomy ([M] / [J] / scope tags)
{{checks-reference.md §4 table verbatim + one line per mechanical check ID}}

### What this run declared it would do
{{expectation set from Phase 1 Step 4b — phases, phase bodies, steps, gates,
load sites, refresh sites, per-file instruction blocks, custom reviewers}}
Built at: {{full trace | partial trace | project-read}}.
This is the declared side of every judged coverage check (the judged I/K-class
rows in checks-reference.md §4): judge the trace against THIS list, not against
what a skill of this kind usually does. An item absent from this list was never
declared, so it cannot be missing.

### Mechanical findings already detected
{{mechanical findings from Step 1, as a table}}

### Thread excerpts (top-3 per judged check)
{{excerpts}}
Excerpts are a slice, not the whole thread. Where a declaration's boundary is
not in the slice, say so in the rationale and lower confidence — an absence you
could not see is not evidence of an absence that happened.

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
