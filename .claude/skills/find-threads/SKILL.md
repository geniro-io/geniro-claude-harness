---
name: find-threads
description: "Use when finding past Claude Code conversation threads — across every project and every config dir on this machine — to hand selected ones to /analyze-thread for failure analysis. Scans the projects/ tree of each config dir, keeps threads that did agentic work (edited code, ran a skill, or spawned a subagent — so read-only review/debug/investigate runs are included), tags each edited or read-only, and either lists them grouped by project or, when you pass a query, searches inside the thread bodies (PR number, error string, filename, or a topic phrase) and ranks the matches. Pass --code-only to restrict to code-editing threads. Takes a free-text pick. Skip for analyzing one already-known thread file (call /analyze-thread directly) or live debugging (/geniro:debug)."
context: main
model: inherit
allowed-tools: [Read, Bash, Glob, Grep, AskUserQuestion]
argument-hint: "[search query — PR number / phrase / filename — or empty for all] [--code-only]"
---

# /find-threads — discover work-bearing Claude threads and hand them to /analyze-thread

## Contents

- Phases
- Loop invariants
- Anti-rationalization
- Definition of done
- Budgets & caps
- ACI per-phase tool surface
- Phase 1 (discover) · Searching by content
- Phase 2 (present) · Phase 3 (select & launch)
- REFERENCE

---

You are the orchestrator for finding past Claude Code conversation threads that did substantive agentic work and routing the ones the user picks to the existing `/analyze-thread` skill. The sibling `scan.py` enumerates every project's session logs across all config dirs, keeps threads that edited code OR ran a skill OR spawned a subagent (tagging each `edited` or `read-only`, so read-only review/debug/investigate runs are surfaced too), and — when the user passes a query — searches inside the thread bodies and ranks the matches. You present the survivors, take a free-text selection, then launch `/analyze-thread` on the first batch of up to five picks and print any overflow batches as a ready-to-run queue. You only READ session logs — you never modify them, and you never edit `/analyze-thread`.

**Input:** an optional query and/or the `--code-only` flag in `$ARGUMENTS`.
- **Empty** → list every work-bearing thread (edited + read-only), grouped by project.
- **A query** (e.g. `2649`, `bright data`, `case-radar.ts`, `didnt post low`) → keep only threads whose body, title, or project path matches, ranked best-first. See **Searching by content** below for what to type.
- **`--code-only`** → restrict the result set to code-editing threads (the legacy behavior); combines with a query.

**Output:** a titled list of threads, each tagged `edited` or `read-only`, + (on the user's pick) a launched `/analyze-thread <paths…> --format=jsonl` directive for the first batch, plus a queue for any overflow.

---

## Phases

1. **Discover** — run `scan.py`. It enumerates every `*.jsonl` session log under each config dir's `projects/`, keeps threads that did agentic work — an `edited` thread calls a code-edit tool (`Edit` / `Write` / `MultiEdit` / `NotebookEdit`); a `read-only` thread spawns a subagent or invokes a Skill but never edits code — and for each survivor extracts its kind, a title, the true project label, the date, a turn count, and an oversize flag. `--code-only` drops the read-only threads. With a query it also scores each thread by content match and drops non-matches.
2. **Present** — render the survivors. No query → grouped by project, newest-first. A query → one flat list ranked best-first, each row showing its project, date, title, kind (`edited`/`read-only`), a match indicator, and a snippet. Number every shown row.
3. **Select & launch** — take a free-text reply (`1,4,7` / `1-5` / `all`), resolve it to absolute paths, echo the set for confirmation, then launch `/analyze-thread` on the first batch of up to 5 picks and print any overflow as a runnable queue.

---

## Loop invariants

1. **Read-only on session logs.** This skill only reads thread files; it writes nothing and never edits `/analyze-thread`. The downstream `/analyze-thread` is also read-only on the thread it analyzes.
2. **`--format=jsonl` on every launched command.** Every current session log begins with a line like `{"type":"last-prompt"…}` / `{"type":"queue-operation"…}` — none begin with `{"type":"summary|user|assistant"}`, so `/analyze-thread`'s format sniff would misread them as markdown. Forcing `--format=jsonl` skips the sniff and is mandatory on the launched command and every queued command.
3. **Free-text selection, not a multiSelect question.** A single project can hold well over a hundred threads; an `AskUserQuestion` caps at 4 options, so one-option-per-thread cannot present them. Selection is a numbered chat list plus a free-text reply, parsed and echoed back. The only `AskUserQuestion` is the lean launch-confirmation gate (3 options).
4. **Project label comes from the thread's `cwd`, not the folder name.** Decoding the `projects/<encoded>` folder name by turning `-` into `/` corrupts labels for projects with literal hyphens (e.g. `claude-plugin`). `scan.py` reads the true path from the JSONL `cwd` field instead.
5. **English-only skill body.** Thread titles are runtime data and may contain any language — render them as-is in the list. The skill body itself stays English-only.
6. **Scan every config dir, not just `~/.claude/`.** A thread's session logs live under whichever config dir was active when it ran. `scan.py` scans `~/.claude/projects`, `$CLAUDE_CONFIG_DIR/projects` when that env var is set, and every path in `$FIND_THREADS_EXTRA_ROOTS` (colon-separated; `scan.py`'s `EXTRA_ROOTS` default when unset) — so a thread under a second config dir is never invisible. Add a config dir by exporting it, not by editing source.
7. **Search returns ranked candidates; you disambiguate the top few.** `scan.py` ranks by term proximity, not certainty. A worktree dir named `pr-2649` mentions that number without being the PR-2649 review. Before presenting or launching a query result, confirm the top candidates are what the user means — check which skill actually ran, or that a real PR reference is present — rather than trusting rank #1 blindly.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll present the threads as a multiSelect AskUserQuestion so the user just clicks." | Invariant #3: a project holds far more threads than the AUQ can offer. Number them in chat and take a free-text reply. |
| "The thread is obviously JSONL, so /analyze-thread will detect it — I'll drop `--format=jsonl`." | Invariant #2: the sniff misreads a current session log as markdown. Every launched and queued command carries `--format=jsonl`. |
| "I'll search the bodies myself with `grep -r <query>`." | `grep` skips image-laden `.jsonl` logs as binary unless forced with `-a`, and a per-file shell loop half-fails in this sandbox for the reason `scan.py`'s module docstring gives. Run `scan.py` — one Python process, invariant #6, Phase 1. |
| "A bare number like `2649` should match those digits anywhere in the body." | That matches UUIDs, cache-token counts, and timestamps that happen to contain `2649` — dozens of false hits. `scan.py` reads a 3–6 digit query as a PR reference (`pull/2649` / `#2649` / `pr-2649`) and only falls back to the raw number when no PR reference exists. |
| "Rank #1 is obviously the thread — launch it." | Invariant #7: rank is proximity, not certainty. Confirm the top candidates ran the skill the user means before launching. |
| "I'll only scan `~/.claude/projects`." | Invariant #6: a thread under a second config dir would be invisible. `scan.py` already scans every configured root. |
| "I'll label each project by decoding its folder name (`-` → `/`)." | Invariant #4: that corrupts any project whose path has a literal hyphen. `scan.py` reads the true path from the JSONL `cwd` field. |
| "After `more <project>` I'll re-render that project's threads numbered from 1." | Renumbering on expand makes a pick collide with numbers already given to other rows. Numbers are assigned once across the full kept set; expansion only reveals hidden rows' existing numbers. |
| "The user picked 9 threads — I'll pass all 9 to one `/analyze-thread` call for the widest recurrence signal." | `/analyze-thread` clamps a run at its per-run thread cap (its §Budgets & quality gates), so the tail is silently dropped. Launch one full batch and queue the overflow as further batches. |
| "An oversize thread is fine to queue — let the user find out." | `/analyze-thread` refuses a file over its size cap (its §Budgets & quality gates), so the queued command would just fail. Flag oversize threads up front so the user can split them first. |
| "The user wants threads worth analyzing — I'll skip the read-only review/debug runs." | The default surfaces `read-only` threads on purpose: a `/geniro:review` or `/geniro:debug` run that edited nothing is exactly what `/analyze-thread` inspects for pipeline failures. Drop them only when the user passes `--code-only`. |

---

## Definition of done

- [ ] Phase 1: `scan.py` ran across every config root and returned the work-bearing set
- [ ] Phase 2: results rendered per the display rules above, `[read-only]` rows tagged
- [ ] Phase 3: selection parsed and echoed; launch-confirmation AUQ fired
- [ ] Phase 3: launchable picks launched as ONE `/analyze-thread <paths…> --format=jsonl`; overflow queued (same flag); oversize picks listed separately, not queued
- [ ] No session log or any other file modified by this skill

---

## Budgets & caps

| Budget | Value | Why |
|---|---|---|
| List wall-clock | a few seconds typical; ~10s on a years-deep multi-config tree | An `edited` thread short-circuits on the first code-edit; a `read-only` thread is confirmed only after the full signal-cap scan finds no edit, so it is the costlier classification — still bounded by the signal-scan cap |
| Search wall-clock | ~5–10s | A query reads up to 12 MB of each thread's body to score matches; bounded so a 60 MB log can't dominate |
| Title scan window | first 2 MB of each file | The embedded `ai-title` line can sit ~1.5 MB into a large log; 2 MB captures it while bounding work |
| Body search window | first 12 MB of each file | Covers the vast majority of logs whole; a match deeper than 12 MB in a giant log may be missed (acceptable — one early hit still surfaces the thread) |
| List display cap | newest 10 per project, with "show more" | Past ~10 rows per project the list becomes unscannable; the rest expand on request |
| Search display cap | top 15 ranked, with "show more" | A common-word query can match every thread; ranking floats the real matches up, so show the best 15 and expand on request |
| Oversize flag | threads over `/analyze-thread`'s file-size cap (its §Budgets & quality gates) | Flag them rather than silently queueing a command `/analyze-thread` will refuse |

---

## ACI per-phase tool surface

| Phase | Tools used | Notes |
|---|---|---|
| 1 Discover | Bash (`python3 scan.py`) | One process produces the row list (list or ranked-search) |
| 2 Present | (orchestrator inline) | No tools — render the rows into tables |
| 3 Select & launch | AskUserQuestion, Read | AUQ for the launch-confirmation gate; Read only if previewing a thread before launch |

---

## PHASE 1: DISCOVER

Run the sibling engine. `SKILL_DIR` is this skill's base directory — the absolute path shown in the invocation header (`Base directory for this skill: …`).

```bash
# Empty (list mode), a query (search mode), and/or --code-only — all passed through verbatim.
python3 "${SKILL_DIR}/scan.py" $ARGUMENTS
```

It prints one tab-separated row per surviving thread:

```
mtime · date · oversize · kind · turns · relevance · hits · project_label · title · abs_path · snippet
```

- **`kind`**: `edited` (calls a code-edit tool) or `read-only` (spawns a subagent / invokes a Skill but never edits code). `--code-only` keeps only `edited`.
- **`turns`**: a trailing `+` (`412+`) means the thread outran the engine's read cap, so the count is a floor — render the `+`.
- **List mode** (`relevance`=`hits`=0, `snippet` empty): sorted by project, then newest-first.
- **Search mode**: kept only when the query matches the body, title, or label; `relevance` = how many query terms co-occur within one ~160-char window (proximity), `hits` = total term occurrences, `snippet` = cleaned text around the densest match. Sorted relevance-desc, hits-desc, newest.

It also prints a `#SUMMARY threads=… projects=… edited=… read-only=…` line on stderr — the aggregate counts Phase 2's header quotes.

Every parsing guard (true `cwd` label, 2 MB title window, first-real-prompt fallback, oversize flag, multi-root scan, PR-number handling, the `edited`/`read-only` classification) lives in `scan.py` — read its module docstring before changing search behavior.

If the engine prints nothing, no work-bearing threads matched (or the query / `--code-only` excluded them all) — tell the user, name the query if any, and stop.

---

## Searching by content

Type the most **distinctive** token you remember from the thread. Distinctive beats descriptive — the engine matches text that is literally in the thread, not your after-the-fact summary of it.

| You remember… | Type | Why it works |
|---|---|---|
| the tracker ticket | `CI-317` or `CI317` | An issue key matches separator-insensitively — `CI-317`, `CI317`, `CI 317` all find the canonical hyphenated spelling threads use. Type it however you remember it; the hyphen is optional |
| the PR it reviewed | `2649` | A bare 3–6 digit query is read as a PR reference (`pull/2649`, `#2649`, `pr-2649`), so it ignores the same digits buried in UUIDs, token counts, and timestamps |
| an error or log string | `ECONNREFUSED` or `null pointer` | Rare strings match few threads — high precision |
| a file it edited | `case-radar.ts` | Filenames appear verbatim in edit-tool calls |
| only the topic | `bright data` / `rls roles` | Multi-word queries rank by proximity — threads where the words cluster outrank threads where a common word merely appears scattered |

Tips:
- A vague paraphrase (`didnt post low`) matches loosely — every thread containing "post" or "low" is kept, and ranking does the work. Prefer a PR number or a unique token when you have one.
- Multiple words are OR-matched for recall but ranked by how tightly they co-occur, so the real match usually lands in the top few even amid many loose matches.

**Finding a whole feature, not one thread.** A single ticket key only finds threads that *name that ticket*. But a feature's real work-in-progress is spread across sibling tickets, follow-up PRs, and threads titled after the feature (not the key) — so one key shows fragments, never the whole epic. To assemble the complete chain, pass several terms at once: the feature noun plus the sibling keys — `CI-315 CI-316 CI-317 cw_case`. The terms are OR-matched into one ranked list, with threads touching several of them floated to the top by proximity. When a user asks for "all the work on X" and a single key returns a thin set, widen to a multi-term query before concluding the work isn't there.

---

## PHASE 2: PRESENT

### List mode (no query)

Rows arrive sorted by project then newest-first. Walk them top to bottom; start a new project block when `project_label` changes.

**Number every kept row first, across the whole list.** Assign global numbers 1, 2, 3, … N before hiding anything. Each thread keeps its number whether or not it is shown, and the next project continues the count past the previous project's FULL row count (if project A has 45 threads, project B's first shown row is #46, even though only #1–10 of A are visible).

```
## Threads — <N> across <M> projects (<E> edited, <R> read-only)

### <project name>  (<full path>)
   1.  <date>  <title>                        (<turns> turns)
   2.  <date>  <title>  [read-only] [>5 MB]   (<turns> turns)
   ...
  10.  <date>  <title>  [read-only]           (<turns> turns)
  … +<K> more in this project (#11–<last>) — reply "more <project name>" to reveal them
```

Rules:
- The header's four counts come from the engine's `#SUMMARY` line, not from tallying rows.
- Numbers are assigned once across the full kept set and never change. Show the newest 10 rows per project; hidden rows keep their already-assigned numbers and are *revealed*, not renumbered, on `more <project name>`.
- Tag `read-only` rows with `[read-only]`; `edited` rows carry no tag (they are the common case, so tagging only the minority keeps the list scannable).
- Mark oversize rows with `[>5 MB]` and note once that `/analyze-thread` refuses them.
- Keep titles on one line (already truncated to ~100 characters).

### Search mode (a query)

Rows arrive ranked best-first across all projects. Present ONE flat list (relevance ordering beats project grouping when the user is hunting a specific thread). Number the shown rows 1…N.

```
## Threads matching "<query>" — top <shown> of <total>

   1.  <date>  <title>  [read-only]  [<project name>]  (<turns> turns)  <match indicator>
          ↳ <snippet>
   2.  ...
  … +<K> more — reply "more" to reveal the rest (lower-ranked)
```

Rules:
- Show the top 15; reveal the rest on `more`. A common-word query can match every thread — say so (`<total>` from the `#SUMMARY` line) so the user knows ranking, not exclusion, is in play.
- Include the snippet so the user can tell matches apart at a glance.
- Tag `read-only` rows with `[read-only]`; `edited` rows carry no tag. The kind is load-bearing when the user is hunting a pipeline run (a read-only `/geniro:review` is exactly an `/analyze-thread` target).
- Before presenting, sanity-check the top candidates against what the user asked for (invariant #7) — e.g. if they want a `/review` run, confirm the rank-#1 thread actually ran that skill, not merely mentions the PR. Note any candidate you down-rank and why.
- Mark oversize rows with `[>5 MB]`.

If the list is empty, say no work-bearing threads matched (name the query) and stop.

---

## PHASE 3: SELECT & LAUNCH

### Step 1 — Take the selection

Ask the user to reply in free text. Accept:
- a comma list: `1,4,7`
- a range: `1-5`
- a mix: `1-3,8,11`
- `all` — every thread in the list (after any active query)

Parse the reply against the numbered list, resolve each number to its absolute path, and drop any number outside the list (note which were ignored).

### Step 2 — Confirm

Echo the resolved set back as a short list (`#`, title, path) so the user sees exactly what will run. Then fire ONE `AskUserQuestion`:

- **Header:** "Launch analysis"
- **Question:** "Launch /analyze-thread on these N threads? Up to five are analyzed together in one run; any beyond that print as a queue."
- **Options:**
  - "Launch — up to five now, rest queued (Recommended)"
  - "Let me re-pick" — return to Step 1
  - "Cancel" — stop, change nothing

If any selected thread is oversize (`>5 MB`), name those here and warn that `/analyze-thread` rejects them as-is — Step 3 keeps them out of the runnable queue.

### Step 3 — Launch the first, queue the rest

On "Launch", split the selection into launchable (`≤5 MB`) and oversize (`>5 MB`) picks, then group the launchable ones into batches of at most 5 — `/analyze-thread`'s per-run cap. One batch is one run, and a run carrying several threads is what produces the cross-thread recurrence merge; splitting the same picks into single-thread runs throws that merge away.

Launch the FIRST batch now as a chat slash-command directive (the same sibling-launch pattern `/analyze-thread` itself uses for `/improve-template` — a slash command in chat, not a subagent):

```
/analyze-thread <abs-path-1> <abs-path-2> … --format=jsonl
```

Then print any remaining batches as a fenced, runnable queue — one command per batch, each carrying `--format=jsonl`:

```
Queued — run this after the first finishes:
/analyze-thread <abs-path-6> <abs-path-7> … --format=jsonl
```

List any oversize picks separately under "Too large to analyze as-is (over 5 MB — split first)" with their paths — do NOT put them in the runnable queue, because `/analyze-thread` refuses them and the command would just fail. If every pick is oversize, launch nothing and say so, naming the oversize threads.

---

## REFERENCE

- `scan.py` (sibling) — the discovery + search engine. Module docstring documents every column, root-resolution, the PR-number rule, the proximity score, the `edited`/`read-only` classification, and the `--code-only` flag. Add a new config dir by exporting `FIND_THREADS_EXTRA_ROOTS` (colon-separated), which overrides its `EXTRA_ROOTS` default.
- `.claude/skills/analyze-thread/SKILL.md` — the downstream consumer: input contract (one or more thread paths in `$ARGUMENTS`, clamped at 5 per run), the `--format=jsonl` modifier, the 5 MB cap, and the sibling-launch pattern this skill mirrors
- `.claude/rules/skill-authoring.md` · `.claude/rules/skill-prose.md` · `.claude/rules/skill-structure.md` — authoring conventions this skill follows by convention (project-local skills are outside CI lint scope)
