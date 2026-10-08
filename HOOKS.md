# Geniro Plugin — Hooks Documentation

Hooks for the geniro plugin: one narrow PreToolUse guard and the SessionStart lifecycle hooks. The plugin deliberately ships no broad command-string guards any more — see §Removed guards before adding one.

## Configuration overview

Hook configuration is **split** across three files:

| File | Purpose |
|---|---|
| [`hooks/hooks.json`](hooks/hooks.json) | Registers event-driven hooks (PreToolUse, SessionStart) for Claude Code; Codex also runs it from the plugin install once the user trusts the hooks in `/hooks`. Auto-discovered at the `hooks/hooks.json` convention path — deliberately NOT declared in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json), which stays metadata-only. Adding a `hooks` field there would duplicate an auto-discovered path and risk double-registration; see [`.claude-plugin/PLUGIN_SCHEMA_NOTES.md`](.claude-plugin/PLUGIN_SCHEMA_NOTES.md) §Component declaration. |
| [`settings.json`](settings.json) (root) | Template only — Claude Code accepts a `statusLine` command solely from the user's or project's own settings, so this bundled copy never runs for the plugin itself; `/geniro:setup` copies it into the user config dir, and that copy is the operative one (see §geniro-statusline.js). The status line is NOT a Claude Code hook — it's a separate display feature. Plugin-shipped `settings.json` cannot grant permissions either (Claude Code ignores a `permissions` block here) — permission rules belong in the consumer's own user/project settings. |
| [`cursor/hooks.json`](cursor/hooks.json) | Registers the same hook scripts for the Cursor runtime. Pointed to by [`.cursor-plugin/plugin.json`](.cursor-plugin/plugin.json) `hooks` field. Every entry runs through the shim (below) rather than calling `hooks/*.sh` directly. |

The status messages set on each `hooks.json` entry (e.g. `"Checking for git add -f on .geniro/..."`) appear as spinner text while the hook runs.

### Cursor wiring (`cursor/hooks.json` → the shim)

Cursor speaks a different hook dialect, so its manifest points every entry at [`cursor/hooks/claude-hook-shim.sh`](cursor/hooks/claude-hook-shim.sh), which takes a script basename from `hooks/` and translates in both directions — one script set for every runtime, no fork:

| Direction | Claude Code dialect | Cursor dialect |
|---|---|---|
| Event names | `PreToolUse` with a `Bash` matcher; `SessionStart` | `beforeShellExecution` / `sessionStart` (camelCase). Any other event reaching the shim runs nothing; a permission event among them is answered allow. |
| Stdin payload | `{tool_name, tool_input, cwd}` | `{command, cwd}` for shell events, folded to `{tool_name:"Bash", tool_input:{command}, cwd}` |
| Working directory | guards walk up from `$PWD` | the shim `cd`s into the payload's `cwd` first, so the walk-up lands in the project the action targets |
| Block signal | `exit 2` + reason on stderr | `{"permission":"deny","agent_message":"<reason>"}` + exit 0, so the reason reaches the Cursor agent |
| Pass signal | `exit 0`, no output | `{"permission":"allow"}` — Cursor blocks a permission hook that exits 0 without a verdict. A crash's exit status passes through for `failClosed` to judge |
| Session context | `hookSpecificOutput.additionalContext` | `additional_context` |
| Notices | stdout `systemMessage` | `agent_message` on the allow |
| `jq` missing | the script announces itself inactive via `systemMessage` | the shim emits the same inactivity notice itself and does not run the script |

Wired for Cursor: the force-add guard on `beforeShellExecution` (with `"failClosed": true` — Cursor otherwise fails open on a crash, timeout, or any non-2 exit) plus session-start restore. The marketplace update check is deliberately not wired: it depends on Claude Code's `claude plugin` registry. Add a new hook to `cursor/hooks.json` only when its event maps cleanly onto the translation map at the top of the shim. `tests/cursor/hook-shim.sh` covers the translation — extend it when the map changes.

## Hook scripts

| Script | Event | Blocking | Description |
|---|---|---|---|
| [`block-geniro-force-add.sh`](hooks/block-geniro-force-add.sh) | PreToolUse `Bash` | exit 2 = block | Blocks `git add -f` / `--force` (and `git update-index --force`) on `.geniro/` paths. Bypass: `git-add-force-geniro` |
| [`session-start-restore.sh`](hooks/session-start-restore.sh) | SessionStart `matcher: "compact\|resume\|startup"` | non-blocking | Compaction-survival. Resolves the active T1.5 state.md across all three layouts (planning task-dir / state-per-skill / state singleton); skips state.md candidates already in a terminal `phase:`/`status:` during resolution, so a finished task is never surfaced as resumable AND cannot shadow an in-flight task on the same branch in a later resolution tier; pre-flights `validate_state_file`; emits an `additionalContext` block-set (per-source prefix · suggested files · validation-failure recovery · helper-missing notice · non-resumable-actions warning · `## Errors` / `## Open Questions` / persisted `approvals:` from state.md frontmatter · resume protocol). Also runs L2 auto-archive. Read-only on state.md; the only writes are `learnings.jsonl` (auto-archive flip) + `.archive-stale.{hash,lock}`. |
| [`geniro-check-update.js`](hooks/geniro-check-update.js) | SessionStart | non-blocking, detached | Background-checks GitHub for plugin updates; exits as a no-op under Codex |
| [`geniro-statusline.js`](hooks/geniro-statusline.js) | `statusLine.command` (settings.json) | non-blocking | Two-row width-justified status line (model — effort · task · topic · 5h limit · cost · update / dir · context · last prompt) |
| [`backpressure.sh`](hooks/backpressure.sh) | **NOT registered** — utility library | — | Sourced by skills (e.g. /refactor, /review) to compress verbose test/build output |

### block-geniro-force-add.sh

**Event:** PreToolUse `Bash`. **Stdin:** `jq -r '.tool_input.command // ""'`. **Block exit:** `exit 2`.

Force-adding a gitignored file puts it in the IDE's Source Control panel, where one "Discard All Changes" click deletes it — a real incident wiped force-added `.geniro/actions/*.md` that way. Track a `.geniro/` subdir by negating it in `.gitignore` instead (`!.geniro/actions/` plus `!.geniro/actions/**`).

Blocks a command segment that runs `git add` or `git update-index` with `-f` (alone or in a short-flag cluster), `--force`, or an unambiguous prefix of it (`--f` … `--forc`), AND names a `.geniro/` path. The `git` word matches in any case and path-qualified; git's global options (`-C <path>`, `-c k=v`, `--git-dir`, …) are skipped. Heredoc bodies are dropped and quoted spans containing whitespace are blanked first, so a commit message or a handoff that merely mentions the rule passes.

It reads the command as written — no variable resolution, no `bash -c` / `eval` payloads, no interpreter calls. That literalness is the design, not a gap to close: the deleted guards chased those channels and blocked read-only commands far more often than they caught a real write (§Removed guards).

**Per-project allowlist:** walks up from cwd (then, from a linked worktree, the main checkout) looking for `.geniro/safety.json` and honors `"git-add-force-geniro"` in `allow_patterns[]`. A malformed `safety.json` does not allow. On block, the message names the `.gitignore` negation and the exact snippet to add.

**Degraded mode (no jq):** exits 0 with a `systemMessage` saying the guard is inactive.

### session-start-restore.sh

**Event:** SessionStart `matcher: "compact|resume|startup"`. **Block exit:** never blocks. **Timeout:** 10s.

Wired as `SessionStart` with `matcher: "compact|resume|startup"` (Anthropic-canonical; `PostCompact` itself does not support `additionalContext`). `clear` is explicitly unmatched — user reset respected. Resolves the active T1.5 `state.md` via canonical slug match + frontmatter `branch:` fallback across all three layouts (planning task-dir / state-per-skill slug / state singleton). Candidates already in a terminal state — terminal `phase:` (`done`/`aborted`/`routed`/etc.) or terminal `status:` — are SKIPPED during resolution, so a finished task is never surfaced as resumable and cannot shadow an in-flight task on the same branch in a later tier (e.g. a done /plan task-dir next to a live /debug slug dir); a defense-in-depth gate re-checks the final pick. Pre-flights `validate_state_file` and degrades gracefully if the helper is missing.

Emits an `additionalContext` block-set:

- Per-source prefix (compact / resume / startup). From a linked worktree it also names the main checkout as `.geniro/`'s home — the worktree never carries the gitignored `.geniro/`, and a session with no skill running never reads the loader, so without the line it searches its own cwd and reports the project's instructions missing.
- Suggested files (L4 instructions set — `global.md` / `memory.md` / `code-style.md` / per-skill — routed through `load-custom-instructions.md` MODE: refresh; CLAUDE.md, `_FEATURES.md`, state.md, spec.md, plan.md as direct Reads). `.geniro/` paths are pre-resolved in the loader's order — the working tree's copy, else the main checkout's absolute path; an external instructions dir is listed flat.
- Validation-failure recovery directive (when `validate_state_file` reports a structural error).
- Helper-missing notice (when the validator binary itself is absent).
- Structured non-resumable-actions warning per state.md frontmatter (`git-push`, `pr-created`, `pr-comment-posted`, `pr-comment-amended`, `pr-review-comment-batch`, `git-commit`, `slack-notify-sent`, `release-tagged`, unknown-action fallback).
- Unresolved errors from state.md `## Errors`, pending `## Open Questions`, and persisted `approvals:` from state.md frontmatter — each entry's category, pick, phase and timestamp, plus its `classes_shown`, `why`, and `result` when the producer recorded them. `evidence` stays in the file rather than the block. `classes_shown` must be written as an inline flow sequence (`classes_shown: [git-push, pr-created]`) — this hook's frontmatter block-list parser reads a YAML block sequence there as the start of the next `approvals[]` entry, flushing the current one early and inflating the approvals count.
- Resume protocol (suppressed when the resolved task is in a terminal state).
- Auto-archive of stale L2 entries (default ON, hash-gated + mkdir-locked for multi-tab safety; opt-out via `safety.json` `memory.auto_archive_stale: false`); when entries are flipped the `systemMessage` gains an "auto-archived: N" suffix.
- Verification-coverage line — the verified-fraction of live (non-deprecated) learnings (`verified: N/total (P%)`), computed independently of the auto-archive threshold so it surfaces every session (default ON, opt-out via `safety.json` `memory.show_coverage: false`); when present the `systemMessage` gains a "memory verified: N/total (P%)" suffix.
- Memory-backend-active notice — when `.geniro/instructions/memory.md` routes the `learnings` layer to a `replace`-mode backend (no local file), the coverage line is absent, so the `systemMessage` gains a "memory backend active" suffix in its place. Detection-only; the hook is shell and never queries the backend.

`systemMessage` one-liner emitted on every source except cold startup with no active task (an auto-archive event, a coverage line, or a memory-backend notice overrides that suppression). Read-only on state.md — never writes it; the only writes are `.geniro/knowledge/learnings.jsonl` (the auto-archive flip) and `.geniro/knowledge/.archive-stale.{hash,lock}` (the hash-gate + multi-tab lock).

### geniro-check-update.js

**Event:** SessionStart. **Block exit:** never blocks. **Timeout:** 5s.

Spawns a detached child process via `spawn(..., detached: true, stdio: 'ignore')` then `child.unref()`; the parent consumes stdin and exits immediately so session start is never blocked. Under Codex, which also runs this hook, the parent skips the spawn when `PLUGIN_ROOT` is set and equals `CLAUDE_PLUGIN_ROOT` — Codex exports both, with the same value, to plugin hooks; Claude Code exports only `CLAUDE_PLUGIN_ROOT` — because only Claude Code's status line reads the cache, and the check would otherwise create `~/.claude` and call GitHub at every Codex session start. The child fetches GitHub `releases/latest` (10s timeout, fallback to `raw.githubusercontent.com`) and writes the result to `~/.claude/cache/geniro-update-check.json`. The status line consumes that cache to surface "update available" indicators.

The child also re-syncs `~/.claude/hooks/geniro-statusline.js` from the plugin's own copy when the two differ. Claude Code accepts a `statusLine` command only from user or project settings, so the plugin cannot point at its own file — `/geniro:setup` installs a copy (§3.6) and `/geniro:update` refreshes it (Phase 3 Step 4). A background marketplace auto-update runs neither, so for exactly the users who opted into `autoUpdate` the copy would drift behind the plugin forever. Writes via rename so a concurrent render never reads a half-written file, and only ever overwrites a copy that already exists — creating one would install a status line the user never configured.

### geniro-statusline.js

**Wiring:** [`settings.json`](settings.json) `statusLine.command`. Not registered in `hooks.json` — `statusLine` is a separate Claude Code display feature, not a hook event.

**Stdin (3s timeout):** JSON containing `model.display_name`, `model.id`, `effort.level`, `workspace.current_dir`, `context_window.remaining_percentage`, `context_window.context_window_size`, `session_id`, `transcript_path`, `rate_limits.five_hour.{used_percentage,resets_at}`, `cost.total_cost_usd`. Also reads `~/.claude/cache/geniro-update-check.json` and `~/.claude/plugins/installed_plugins.json` for the update banner, `~/.claude/todos/*.json` for the in-progress task, and the tail (last 256KB) of `transcript_path` for the session topic (`ai-title`) and the latest user prompt (`last-prompt`).

Renders a **two-row, width-justified** ANSI bar (uses the `COLUMNS` env var Claude Code exports, v2.1.153+):

- **Line 1:** `[model — effort · task]` left, `«session topic»` (the `ai-title`) centered, `[5h rate-limit · cost · ⬆ update]` right (update pinned rightmost).
- **Line 2:** `[dir · context bar]` left, `«latest user prompt»` (the `last-prompt`) centered.
- Model shows the full name (`display_name`, e.g. `Opus 4.8 (1M context)`; reconstructed from `model.id` when the client sends a bare family word) in a bold family colour (Opus purple / Sonnet blue / Haiku green). Reasoning effort, set off by a spaced ` — ` dash, is graded low→max (gray→orange→red). Directory is teal.
- Context %: green (<50%), yellow (50-65%), orange (65-80%), red blinking (>80%); token count rides inside the bar. 5h limit: green (<70%), yellow (<90%), red (≥90%) + reset countdown.
- Update banner: Claude Code's marketplace auto-update lands a new version on disk up to ten minutes *after* a session starts, so the version a session runs and the version on disk routinely differ, and the check-update cache — written once at SessionStart — reports an update that has already arrived. The banner reconciles three sources on every render: the version this session loaded (`.claude-plugin/plugin.json` under `CLAUDE_PLUGIN_ROOT`, else beside the hook), the version on disk (`installed_plugins.json`), and the latest upstream (the cache's `latest`). Disk ahead of the session → `/reload-plugins` (nothing to fetch); otherwise local behind upstream → `/geniro:update`; otherwise no banner. Disk-ahead wins when both hold; the reload is cheaper and the next session's check re-surfaces whatever is still upstream.
  Neither the cache's `installed` nor its `update_available` is trusted: one cache file is shared by every session, so both belong to whichever session wrote it last — reading `installed` told a freshly started session, already on the newest version, to reload. They are used only as a last resort, when no local version is knowable at all (the statusline copy `/geniro:setup` installs into the user config dir has no manifest beside it, and a `--plugin-dir` run has no registry).
- No PR badge — Claude Code already shows the open PR in its own bottom row, so a second copy here would just duplicate it.
- Every segment except model/dir/context is conditional — it renders only when its field is present, so the bar stays compact on a fresh session.
- Lines justify to two columns short of the window edge (margin for Claude Code's UI padding). `visLen` charges East-Asian-ambiguous glyphs (`— … ↻ │`) as double-width so fonts that draw them wide don't overflow and get the right segment truncated. When `COLUMNS` is absent or the window is < 40 cols, falls back to a plain `│`-separated two-row join.
- `settings.json` sets `refreshInterval: 10`, so the bar also re-renders every 10s — the reset countdown and the latest-prompt segment stay current between assistant messages (the event-driven update only fires after each assistant turn).

Always exits 0; falls back to the literal string `geniro` if JSON parse fails.

### backpressure.sh

**Event:** none — this is a utility library, not a hook. Intentionally NOT in `hooks.json`.

Skills source this file (or invoke it directly) to wrap verbose test/build/lint commands and surface only failures. Pattern:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" "Tests" "npm test"
# or
source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Tests" "npm test"
```

On success: emits `✓ <description> passed (<summary>)`, where `<summary>` is a detected framework test count or `<N> lines of output`. On failure: filters and caps output at `GENIRO_BACKPRESSURE_CAP` lines (default 150). Manages its own `mktemp` lifecycle; no persistence.

Current sourcing call sites: `grep -rl 'backpressure.sh' skills/`. `skills/refactor/SKILL.md` names the helper in prose but does not source it — the sourcing lives in that skill's phase-2 body.

## Removed guards

Deleted 2026-09-29: `file-protection.sh`, `security-pattern-check.sh`, `block-dangerous-git.sh`, `block-geniro-deletion.sh` (all but its force-add check, kept above), `enforce-state-helper.sh`, and their shared parser `lib/write-vectors.sh`.

Across ~3,400 transcripts from 21 days they fired 296 times, 267 of them still reproducible on the final code, and not one block prevented a mistake:

| Guard | Blocks | What it actually blocked |
|---|---|---|
| `block-dangerous-git.sh` | 106 | Git commands the agent meant to run on its own branch or worktree — `branch -D` on squash-merged branches, `reset --hard origin/<branch>`, `worktree remove --force`, `push --delete`, `push --force-with-lease`, `checkout -f`, `stash drop` |
| `block-geniro-deletion.sh` | 69 | 47 of the 58 still-reproducible blocks were read-only commands (`ls $MAIN/.geniro/knowledge/` beside an `atomic_state_write` call reported as `rm -rf`); the rest were intended cleanups |
| `enforce-state-helper.sh` | 62 | Write/Edit on `state.md`, planning notes, `.geniro/actions/*.md`; the run then re-sent identical content through the helper, which adds only tmp+rename atomicity |
| `file-protection.sh` | 50 | Its Bash branch guessing write targets from command text — Python edit scripts whose code said `row.key` read as writing a private key, `.git/info/exclude` appends, tfstate backups into a scratchpad |
| `security-pattern-check.sh` | 7 | Scratch probe files and intended code (`rejectUnauthorized: false` in a crawler) |

What replaces them is prose, not mechanism. State writes still go through the helpers per `CLAUDE.md` §State Files. Destructive git and bulk `.geniro/` deletion follow the model's own judgment and Claude Code's permission system. Security patterns are `/geniro:review`'s security dimension. A new PreToolUse guard needs the opposite evidence first: a declared target it reads rather than infers from command text, and measured blocks that prevented real damage.

## Testing

```bash
# Force-add guard (expect exit code 2 = blocked)
echo '{"tool_input":{"command":"git add -f .geniro/actions/x.md"}}' | ./hooks/block-geniro-force-add.sh
echo "exit=$?"

# Full smoke-test suites
bash tests/hooks/block-geniro-force-add.sh
bash tests/cursor/hook-shim.sh
```

## Key Safety Principles

1. **Exit Code 2 for Blocking** — Never use exit 1 (which is FAIL-OPEN)
2. **Stdin Consumption** — All hooks consume stdin as first action
3. **JSON Parsing** — Use jq for safe input extraction
4. **Error Messages to Stderr** — Clear feedback redirected to user
5. **Graceful Degradation** — hooks fail open when a dependency (e.g. `jq`) is missing: the guard loudly (a `systemMessage` says it is not running), convenience hooks silently (never wedge the session)
6. **Read a declared target** — a guard inspects a field the tool declares, or a literal command word; it never reconstructs intent from arbitrary command text (§Removed guards)

## Sources & References

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide)
- Exit code behavior: Exit 0 = allow, Exit 2 = block (PreToolUse only); PostToolUse / Stop / SessionStart always exit 0
- statusLine wiring: see [`settings.json`](settings.json) and [Claude Code statusLine docs](https://code.claude.com/docs/en/statusline)
