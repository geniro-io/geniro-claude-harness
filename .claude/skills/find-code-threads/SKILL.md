---
name: find-code-threads
description: "Use when finding past Claude Code conversation threads that touched code — across every project on this machine — to hand selected ones to /analyze-thread for failure analysis. Scans ~/.claude/projects, keeps only threads that edited code, groups them by project with a title and date, and takes a free-text pick. Skip for analyzing one already-known thread file (call /analyze-thread directly) or live debugging (/geniro:debug)."
context: main
model: inherit
allowed-tools: [Read, Bash, Glob, Grep, AskUserQuestion]
argument-hint: "[optional filter — project or topic substring]"
---

# /find-code-threads — Discover code-bearing Claude threads and hand them to /analyze-thread

You are the orchestrator for finding past Claude Code conversation threads that edited code and routing the ones the user picks to the existing `/analyze-thread` skill. You scan every project's session logs under `~/.claude/projects/`, keep only threads that touched code, present them grouped by project with a short title, take a free-text selection, then launch `/analyze-thread` on the first pick and print the rest as a ready-to-run queue. You only READ session logs — you never modify them, and you never edit `/analyze-thread`.

**Input:** an optional filter substring in `$ARGUMENTS` (matches a project path or a thread title); empty means "every project".
**Output:** a grouped, titled list of code-bearing threads + (on the user's pick) a launched `/analyze-thread <path> --format=jsonl` directive for the first selection and a runnable queue for the rest.

---

## Phases

1. **Discover** — enumerate every `*.jsonl` session log under `~/.claude/projects/` with `find`, keep only threads whose content shows a code edit (`Edit` / `Write` / `MultiEdit` / `NotebookEdit`), and for each survivor extract a title, the true project label, the date, a turn count, and an oversize flag.
2. **Present** — render the survivors grouped by project, newest-first, each row numbered with its title, date, turn count, and an oversize marker; cap each project at the newest 10 with a "show more" affordance.
3. **Select & launch** — take a free-text reply (`1,4,7` / `1-5` / `all`), resolve it to absolute paths, echo the set for confirmation, then launch `/analyze-thread <first> --format=jsonl` and print the remaining picks as a runnable queue.

---

## Loop invariants

1. **Read-only on session logs.** This skill only reads thread files; it writes nothing and never edits `/analyze-thread`. The downstream `/analyze-thread` is also read-only on the thread it analyzes.
2. **`--format=jsonl` on every launched command.** Every current session log begins with a line like `{"type":"last-prompt"…}` / `{"type":"queue-operation"…}` — none begin with `{"type":"summary|user|assistant"}`, so `/analyze-thread`'s format sniff would misread them as markdown. Forcing `--format=jsonl` skips the sniff and is mandatory on the launched command and every queued command.
3. **Free-text selection, not a multiSelect question.** A single project can hold 45–66 code threads; an `AskUserQuestion` caps at 4 options, so one-option-per-thread cannot present them. Selection is a numbered chat list plus a free-text reply, parsed and echoed back. The only `AskUserQuestion` is the lean launch-confirmation gate (3 options).
4. **Project label comes from the thread's `cwd`, not the folder name.** Decoding the `~/.claude/projects/<encoded>` folder name by turning `-` into `/` corrupts labels for projects with literal hyphens (e.g. `claude-plugin`). Read the true path from the JSONL `cwd` field instead.
5. **English-only skill body.** Thread titles are runtime data and may contain any language — render them as-is in the list. The skill body itself stays English-only.

---

## Budgets & caps

| Budget | Value | Why |
|---|---|---|
| Discovery wall-clock | a few seconds typical; ~10s on a years-deep tree | The code-signal `grep -l` short-circuits on the first match, so kept threads are cheap; the per-thread turn count is the main cost on multi-GB histories |
| `ai-title` read window | first 2 MB of each file | The embedded `ai-title` line can sit ~1.5 MB into a large log; a 2 MB cap captures it while bounding work on 30–65 MB files |
| First-prompt read window | first 800 KB | The opening user turns (and the slash-command name) live in the first events; 800 KB covers them without reading whole logs |
| Per-project display cap | newest 10, with "show more" | Past ~10 rows per project the list becomes unscannable; the rest expand on request |
| Oversize flag | mark threads > 5 MB | `/analyze-thread` rejects files over its 5 MB hard cap, so flag them rather than silently queueing a command that will be refused |

---

## ACI per-phase tool surface

| Phase | Tools used | Notes |
|---|---|---|
| 1 Discover | Bash (`find`, `grep`, `jq`, `head`, `stat`, `date`, `awk`, `sed`) | One pipeline produces the row list |
| 2 Present | (orchestrator inline) | No tools — render the row list into grouped tables |
| 3 Select & launch | AskUserQuestion, Read | AUQ for the launch-confirmation gate; Read only if previewing a thread before launch |

---

## PHASE 1: DISCOVER

Run this Bash pipeline. It prints one tab-separated row per code-bearing thread:
`mtime · date · oversize · turns · project_label · title · abs_path`, sorted by project then newest-first.

```bash
projects="$HOME/.claude/projects"
ARGS="$ARGUMENTS"   # optional filter — empty means every project

find "$projects" -maxdepth 2 -name '*.jsonl' -type f 2>/dev/null | while IFS= read -r f; do
  # Code signal: keep only threads that edited code. grep -l short-circuits on the first match.
  grep -lE '"name":"(Edit|Write|MultiEdit|NotebookEdit)"' "$f" >/dev/null 2>&1 || continue

  size=$(stat -f '%z' "$f" 2>/dev/null || echo 0)
  mtime=$(stat -f '%m' "$f" 2>/dev/null || echo 0)
  oversize=0; [ "${size:-0}" -gt 5242880 ] && oversize=1
  date=$(date -r "${mtime:-0}" '+%Y-%m-%d' 2>/dev/null || echo '?')

  # True project label from the cwd field. Parse-then-extract, not grep-then-parse: the first line that
  # literally contains "cwd" is sometimes a base64 blob where the bytes happen to spell it; that line
  # fails to parse and would drop the thread onto the lossy encoded folder name, splitting one project
  # into two groups. Parse each line and take the first real .cwd. No read cap: grep -m1 closes the pipe
  # at the first cwd (SIGPIPE stops jq), so it reads only the opening lines even on a 60 MB log — and the
  # cwd can sit on line 3 behind a multi-MB first line, which a byte cap would miss. Folder-name decode
  # (with -- to survive a leading '-') is a last resort only.
  label=$(jq -Rr 'fromjson? | .cwd // empty' "$f" 2>/dev/null | grep -m1 .)
  [ -z "$label" ] && label="$(basename -- "$(dirname "$f")")"

  # Title preference: 1) embedded ai-title  2) first free-text user prompt  3) the slash-command name.
  title=$(head -c 2000000 "$f" 2>/dev/null | grep -m1 '"type":"ai-title"' \
          | jq -Rr 'fromjson? | (.aiTitle // empty) | .[0:100]' 2>/dev/null | head -1)
  if [ -z "$title" ]; then
    # Render each user turn's text (string content, or the text blocks of an array), newlines flattened.
    ut=$(head -c 800000 "$f" 2>/dev/null | jq -Rr '
      fromjson?
      | select(.type=="user")
      | (.message.content
         | if type=="string" then .
           elif type=="array" then (map(select(.type=="text").text // empty) | join(" "))
           else "" end)
      | gsub("[\r\n\t]+"; " ")
      | select(length>0)' 2>/dev/null)
    # First turn that is a real prompt: not a slash-command wrapper, not the injected skill body.
    real=$(printf '%s\n' "$ut" \
      | grep -vE '<command-|<local-command-|^ *Base directory for this skill:|^ *Caveat: The messages below' \
      | grep -vE '^[[:space:]]*$' | head -1)
    if [ -n "$real" ]; then
      title=$real
    else
      # Slash-command thread with no free-text prompt → use the command name as the label.
      title=$(printf '%s\n' "$ut" | grep -m1 '<command-name>' | sed 's/.*<command-name>//; s,</command-name>.*,,')
    fi
  fi
  [ -z "$title" ] && title="(code thread — no title)"
  title=$(printf '%s' "$title" | tr '\t\r\n' '   ' | cut -c1-100)
  label=$(printf '%s' "$label" | tr -d '\t\r\n')

  # Turn count: user + assistant events (awk, not grep -c, to avoid the BSD no-trailing-newline undercount).
  turns=$(awk '/"type":"(user|assistant)"/{n++} END{print n+0}' "$f" 2>/dev/null)

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$mtime" "$date" "$oversize" "$turns" "$label" "$title" "$f"
done \
  | sort -t"$(printf '\t')" -k5,5 -k1,1nr \
  | { if [ -n "$ARGS" ]; then awk -F'\t' -v q="$ARGS" 'BEGIN{q=tolower(q)} index(tolower($5 FS $6), q)'; else cat; fi; }
```

Why each guard is there:

- **`find`, never a bare `for f in "$d"*.jsonl`** — a bare glob aborts under zsh (`no matches found`) on a project dir that has no logs (empty `projects`, worktree dirs). `find` returns cleanly.
- **`jq -Rr 'fromjson?'`, never bare `jq`** — bare `jq` aborts on the first unparseable line and silently wedges the pipeline; `fromjson?` skips bad lines.
- **`stat -f` / `date -r`** — BSD coreutils form (this runs on the user's macOS). `stat -c` / `date -d` are GNU-only.
- **2 MB `ai-title` window** — the title line is often deep in the file; reading 2 MB captures the measured maximum offset without scanning a whole 60 MB log.
- **array-aware first-prompt** — modern user turns store content as an array of text blocks, not a bare string; both shapes are rendered.
- **filter on label + title only** — the optional `$ARGUMENTS` filter (`awk` on fields 5–6) matches the project path and title, not the epoch / date / turn-count / file-path columns, so a term like `claude` (in every file path) or a bare number does not match every row.

If the pipeline prints nothing, no code-bearing threads matched (or the filter excluded them all) — tell the user and stop.

---

## PHASE 2: PRESENT

Read the rows from Phase 1 and render them grouped by project. The rows arrive sorted by project then newest-first, so walk them top to bottom and start a new project block when the `project_label` changes.

**Number every kept row first, across the whole list.** Walk the full sorted set and assign global numbers 1, 2, 3, … N before hiding anything. Each thread keeps its number whether or not it is shown, so a pick always maps to exactly one thread — and the next project continues the count past the previous project's FULL row count (if project A has 45 threads, project B's first row is #46, even though only #1–10 of A are shown).

```
## Code threads — <N> across <M> projects

### <project name>  (<full path>)
   1.  <date>  <title>            (<turns> turns)
   2.  <date>  <title>  [>5 MB]   (<turns> turns)
   ...
  10.  <date>  <title>            (<turns> turns)
  … +<K> more in this project (#11–<last>) — reply "more <project name>" to reveal them

### <next project name>  (<full path>)
  46.  <date>  <title>            (<turns> turns)
   ...
```

Rules:
- Numbers are assigned once across the full kept set and never change. Display the newest 10 rows per project; hidden rows keep their already-assigned numbers (e.g. #11–45) and are *revealed*, not renumbered, when the user replies `more <project name>`.
- Mark oversize rows with `[>5 MB]` and note once below the list that `/analyze-thread` refuses files over 5 MB, so those need splitting before they can be analyzed.
- Keep titles on one line; they are already truncated to ~100 characters.
- If the list is empty, say no code-bearing threads matched (name the active filter, if any) and stop.

---

## PHASE 3: SELECT & LAUNCH

### Step 1 — Take the selection

Ask the user to reply in free text. Accept:
- a comma list: `1,4,7`
- a range: `1-5`
- a mix: `1-3,8,11`
- `all` — every thread in the list (after any active filter)

Parse the reply against the numbered list, resolve each number to its absolute path, and drop any number outside the list (note which were ignored).

### Step 2 — Confirm

Echo the resolved set back as a short list (`#`, title, path) so the user sees exactly what will run. Then fire ONE `AskUserQuestion`:

- **Header:** "Launch analysis"
- **Question:** "Launch /analyze-thread on these N threads? The first launchable one runs now; the rest print as a queue you can run one at a time."
- **Options:**
  - "Launch — first now, rest queued (Recommended)"
  - "Let me re-pick" — return to Step 1
  - "Cancel" — stop, change nothing

If any selected thread is oversize (`>5 MB`), name those here and warn that `/analyze-thread` rejects them as-is — Step 3 keeps them out of the runnable queue.

### Step 3 — Launch the first, queue the rest

On "Launch", split the selection into launchable (`≤5 MB`) and oversize (`>5 MB`) picks.

Launch the FIRST launchable pick now as a chat slash-command directive (the same sibling-launch pattern `/analyze-thread` itself uses for `/improve-template` — a slash command in chat, not a subagent):

```
/analyze-thread <first-launchable-abs-path> --format=jsonl
```

Then print the remaining launchable picks as a fenced, runnable queue — one per line, each carrying `--format=jsonl`:

```
Queued — run these one at a time after the first finishes:
/analyze-thread <abs-path-2> --format=jsonl
/analyze-thread <abs-path-3> --format=jsonl
```

List any oversize picks separately under "Too large to analyze as-is (over 5 MB — split first)" with their paths — do NOT put them in the runnable queue, because `/analyze-thread` refuses them at its 5 MB cap and the command would just fail. If every pick is oversize, launch nothing and say so, naming the oversize threads.

`--format=jsonl` is on every command for the reason in invariant #2. Do not batch multiple threads into one `/analyze-thread` call — it takes exactly one thread path per run.

---

## Modifier handling

| `$ARGUMENTS` | Effect |
|---|---|
| empty | Scan every project under `~/.claude/projects/`. |
| a substring (e.g. `crawler`, `review skill`) | Case-insensitive substring filter on the project-path and title columns only — keeps matching threads. It does not match the date, turn-count, or file-path columns, so `claude` (in every file path) or a bare number won't match everything. Useful to narrow a years-deep history to one project or topic. |

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll present the threads as a multiSelect AskUserQuestion so the user just clicks." | A single project holds far more than the 4-option AUQ cap, so one-option-per-thread cannot present them (invariant #3). Selection is a numbered list + free-text reply; the only AUQ is the 3-option launch confirmation. |
| "The thread is obviously JSONL, so /analyze-thread will detect it — I'll drop `--format=jsonl`." | Current session logs begin with `last-prompt` / `queue-operation` lines, which `/analyze-thread`'s sniff reads as markdown (invariant #2). Every launched and queued command must carry `--format=jsonl`. |
| "I'll label each project by decoding its folder name (`-` → `/`)." | That corrupts any project with a literal hyphen in its path (invariant #4). Read the true path from the JSONL `cwd` field. |
| "I'll grab the cwd with `grep -m1 '\"cwd\"'` then parse just that line." | The first line that literally contains `cwd` is sometimes a base64 blob where the bytes happen to spell it; that line fails to parse and the thread silently falls back to the lossy folder name, so one project splits into two groups in the list. Parse each line and take the first real `.cwd` (`jq -Rr 'fromjson? \| .cwd // empty' \| grep -m1 .`). |
| "After `more <project>` I'll re-render that project's threads numbered from 1." | Renumbering on expand makes a pick collide with numbers already given to other projects' rows. Numbers are assigned once across the full kept set; expansion only reveals the hidden rows' existing numbers (e.g. #11–45), never renumbers. |
| "Reading only the first 200 KB is enough to find the title." | The `ai-title` line can sit ~1.5 MB deep; a 200 KB window misses it on roughly half of titled threads. Read up to 2 MB for the title and 800 KB for the first-prompt fallback. |
| "I'll loop the project dirs with a glob (`for f in "$d"*.jsonl`)." | A bare glob aborts under zsh on a directory with no logs. Use `find … -name '*.jsonl'`, which returns cleanly on empty dirs. |
| "I'll launch all selected threads in one `/analyze-thread` call to save round-trips." | `/analyze-thread` takes exactly one thread path per run. Launch the first and print the rest as a runnable queue. |
| "An oversize thread is fine to queue — let the user find out." | `/analyze-thread` refuses files over its 5 MB cap, so the queued command would just fail. Flag oversize threads up front so the user can split them first. |

---

## Definition of Done

- [ ] Phase 1: `find`-based scan ran; only code-bearing threads kept; each row has a title, true `cwd` label, date, turn count, and oversize flag
- [ ] Phase 2: rows grouped by project, newest-first, numbered once across the full set (stable on expand), capped at 10/project with "show more"
- [ ] Phase 3: free-text selection parsed and echoed; launch-confirmation AUQ fired (with a `header`)
- [ ] Phase 3: first *launchable* pick launched as `/analyze-thread <path> --format=jsonl`; remaining launchable picks queued (each with `--format=jsonl`); oversize picks listed separately, not queued
- [ ] No session log or any other file modified by this skill

---

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/.claude/skills/analyze-thread/SKILL.md` — the downstream consumer: input contract (single thread path in `$ARGUMENTS`), the `--format=jsonl` modifier, the 5 MB cap, and the sibling-launch pattern this skill mirrors
- `.claude/rules/skill-authoring.md` · `.claude/rules/skill-prose.md` · `.claude/rules/skill-structure.md` — authoring conventions this skill follows by convention (project-local skills are outside CI lint scope)
