# Geniro Plugin — Hooks Documentation

Production-grade hooks for the geniro plugin. All hooks follow best practices from the official Claude Code documentation and proven implementations from Citadel, Claude Forge, and claude-pipeline.

## Configuration overview

Hook configuration is **split** across three files:

| File | Purpose |
|---|---|
| [`hooks/hooks.json`](hooks/hooks.json) | Registers event-driven hooks (PreToolUse, SessionStart) for Claude Code. Auto-discovered at the `hooks/hooks.json` convention path — deliberately NOT declared in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json), which stays metadata-only. Adding a `hooks` field there would duplicate an auto-discovered path and risk double-registration; see [`.claude-plugin/PLUGIN_SCHEMA_NOTES.md`](.claude-plugin/PLUGIN_SCHEMA_NOTES.md) §Component declaration. |
| [`settings.json`](settings.json) (root) | Template only — Claude Code accepts a `statusLine` command solely from the user's or project's own settings, so this bundled copy never runs for the plugin itself; `/geniro:setup` copies it into the user config dir, and that copy is the operative one (see §geniro-statusline.js). The status line is NOT a Claude Code hook — it's a separate display feature. Plugin-shipped `settings.json` cannot grant permissions either (Claude Code ignores a `permissions` block here) — permission rules belong in the consumer's own user/project settings. |
| [`cursor/hooks.json`](cursor/hooks.json) | Registers the same hook scripts for the Cursor runtime. Pointed to by [`.cursor-plugin/plugin.json`](.cursor-plugin/plugin.json) `hooks` field. Every entry runs through the shim (below) rather than calling `hooks/*.sh` directly. |

The status messages set on each `hooks.json` entry (e.g. `"Checking for destructive git operations..."`) appear as spinner text while the hook runs.

### Cursor wiring (`cursor/hooks.json` → the shim)

Cursor speaks a different hook dialect, so its manifest points every entry at [`cursor/hooks/claude-hook-shim.sh`](cursor/hooks/claude-hook-shim.sh), which takes a script basename from `hooks/` and translates in both directions — one script set, two runtimes, no fork:

| Direction | Claude Code dialect | Cursor dialect |
|---|---|---|
| Event names | `PreToolUse` with a `Bash` matcher / a file-tool matcher; `SessionStart` | `beforeShellExecution` / `preToolUse` / `sessionStart` (camelCase) |
| Stdin payload | `{tool_name, tool_input, cwd}` | `{command, cwd}` for shell events; `tool_input` with alias keys for file events — path (`path` / `target_file`) normalized to `file_path`, **and content (`contents` / `code_edit` / `new_string` / `new_source`) normalized to `content`** |
| Working directory | guards walk up from `$PWD` | the shim `cd`s into the payload's `cwd` first, so the walk-up lands in the project the action targets |
| Block signal | `exit 2` + reason on stderr | `{"permission":"deny","agent_message":"<reason>"}` + exit 0, so the reason reaches the Cursor agent |
| Session context | `hookSpecificOutput.additionalContext` | `additional_context` |
| Degraded mode (`jq` missing) | the script still runs: the three data-loss guards' coarse fail-closed scan exits 2 on a hit (§Key Safety Principles 5), and a stdout `systemMessage` announces whatever is inert | the shim runs the script too, then translates — an exit 2 becomes a `printf`-built `{"permission":"deny","agent_message":"<reason>"}`, anything else becomes the inactivity notice on the event's message key (`agent_message` / `additional_context`). Never silent, and the notice never carries a `permission` key, so it cannot vote "allow" over another hook's deny |

Both alias folds are load-bearing. Normalizing only the path key is a silent bypass: a content-reading guard such as the security pattern scan receives an empty field and exits 0 on a payload it would otherwise deny. Likewise, building a `cwd` field without moving into it leaves every guard inspecting the wrong tree. Without `jq` the shim still folds the path aliases, using shell string substitution, so the fail-closed scan sees an aliased target; the content fold is skipped there because no fail-closed scan reads content. `tests/cursor/hook-shim.sh` covers each alias spelling and both directions — extend it when the translation map changes.

Wired for Cursor: four Bash guards on `beforeShellExecution` — the destructive-git guard, the `.geniro/` deletion guard, protected-file writes, and the security pattern scan — plus three file-write guards on `preToolUse` (protected-file writes, state-helper enforcement, security pattern scan), plus session-start restore. The destructive-git and `.geniro/`-deletion guards are shell-only in BOTH runtimes: they inspect a command string, and a file-write event carries a path with no command to read — the same split `hooks/hooks.json` uses. State-helper enforcement is file-tool-only in both runtimes too, for the same reason its `beforeShellExecution` entry is gone: its Bash branch was removed 2026-08-13 (see `enforce-state-helper.sh` below).

**Deliberately not wired for Cursor** — the runtime has no compatible slot, so the conventions apply as instructions per [`skills/_shared/runtime-portability.md`](skills/_shared/runtime-portability.md) instead: one hook, the marketplace update check (Claude Code's `claude plugin` registry only). Add a new hook to `cursor/hooks.json` only when its event maps cleanly onto the translation map at the top of the shim.

## Hook scripts

The plugin ships 6 safety / lifecycle hooks, 1 sourced utility library, and 2 Node-based feature scripts:

| Script | Event | Blocking | Description |
|---|---|---|---|
| [`file-protection.sh`](hooks/file-protection.sh) | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` AND `Bash` | exit 2 = block | Blocks writes to lock files, keys, credentials, Git internals. The Bash branch catches shell-side writes into the same protected paths — twelve vectors plus the seven shell-indirection channels it re-runs itself on; see the full list in the `file-protection.sh` section below. Reads stay allowed. Bypass: `write-git-internal`, `write-lockfile`, `write-cert-key`, `write-credentials`, `write-tfstate`, `write-vault` |
| [`block-dangerous-git.sh`](hooks/block-dangerous-git.sh) | PreToolUse `Bash` | exit 2 = block | Blocks destructive git: force-push, reset --hard, branch -D, clean -fd, mass-discard checkout/restore, update-ref -d, filter-branch, remote-branch deletion (`git push --delete` / colon-refspec), stash deletion (`git stash clear` / `git stash drop`) |
| [`block-geniro-deletion.sh`](hooks/block-geniro-deletion.sh) | PreToolUse `Bash` | exit 2 = block | Blocks bulk deletion of `.geniro/` (bypass: `rm-geniro-tree`, `rm-geniro-subdir`, `rm-geniro-state-subdir`, `find-geniro-delete`, `worktree-remove-with-state`, `git-add-force-geniro`) |
| [`enforce-state-helper.sh`](hooks/enforce-state-helper.sh) | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` | exit 2 = block | Blocks direct writes to canonical state paths under `.geniro/state/`, `.geniro/planning/`, `.geniro/knowledge/`, `.geniro/instructions/`, `.geniro/actions/`, `.geniro/workflow/`. Shell-side writes are NOT matched — the guard reads `file_path` only; see its section below for why the Bash branch was removed. Suggests the helpers per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`. Also guards `.geniro/safety.json` itself, so a bypass cannot be self-granted in one write. Bypass: `enforce-state-helper`, plus `safety-json-edit` for the safety.json guard. |
| [`security-pattern-check.sh`](hooks/security-pattern-check.sh) | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` AND `Bash` | exit 2 = block | Cheap regex scan for high-signal security anti-patterns in file content (eval/exec, pickle, yaml.load, shell=True, curl\|sh, TLS bypass, XSS sinks, weak crypto). Per-pattern bypass: `sec-eval-exec`, `sec-pickle`, `sec-yaml-unsafe`, `sec-shell-injection`, `sec-curl-pipe-sh`, `sec-tls-bypass`, `sec-xss-sink`, `sec-weak-crypto`. Scope-limited to applicable file extensions per pattern. Logic-level issues (authz bypass, IDOR, race conditions) are not regex-detectable and require `/geniro:review`. |
| [`session-start-restore.sh`](hooks/session-start-restore.sh) | SessionStart `matcher: "compact\|resume\|startup"` | non-blocking | Compaction-survival. Resolves the active T1.5 state.md across all three layouts (planning task-dir / state-per-skill / state singleton); skips state.md candidates already in a terminal `phase:`/`status:` during resolution, so a finished task is never surfaced as resumable AND cannot shadow an in-flight task on the same branch in a later resolution tier; pre-flights `validate_state_file`; emits an `additionalContext` block-set (per-source prefix · suggested files · validation-failure recovery · helper-missing notice · non-resumable-actions warning · `## Errors` / `## Open Questions` / persisted `approvals:` from state.md frontmatter · resume protocol). Also runs L2 auto-archive. Read-only on state.md; the only writes are `learnings.jsonl` (auto-archive flip) + `.archive-stale.{hash,lock}`. |
| [`geniro-check-update.js`](hooks/geniro-check-update.js) | SessionStart | non-blocking, detached | Background-checks GitHub for plugin updates |
| [`geniro-statusline.js`](hooks/geniro-statusline.js) | `statusLine.command` (settings.json) | non-blocking | Two-row width-justified status line (model — effort · task · topic · 5h limit · cost · update / dir · context · last prompt) |
| [`backpressure.sh`](hooks/backpressure.sh) | **NOT registered** — utility library | — | Sourced by skills (e.g. /refactor, /review) to compress verbose test/build output |

### file-protection.sh

**Event:** PreToolUse `Edit|Write|MultiEdit|NotebookEdit` AND `Bash` (registered under both matchers in `hooks.json`; the script branches on `tool_name`). **Stdin:** `.tool_input.file_path` (or `.tool_input.notebook_path` for NotebookEdit) for the file tools; `.tool_input.command` for Bash. **Block exit:** `exit 2`.

**Bash branch:** extracts write targets the file-tool matcher never sees, then runs the same pattern set against each. Twelve vectors:

1. Redirection targets — `>`, `>>`, `>|`.
2. `tee` arguments (every non-flag token).
3. File arguments of an in-place `sed -i` span (the sed SCRIPT token is skipped — it is code, not a path), and GNU awk's two-token `-i inplace` extension (`awk`/`gawk`/`mawk`; the literal word `inplace` is skipped as the flag's value).
4. `cp`/`mv` destinations (the last non-flag token — copying FROM a protected file is a read and stays allowed).
5. `dd of=` targets.
6. `truncate` file arguments (the `-s` size operand is skipped).
7. `shred` file arguments (the `-n`/`-s` count operands are skipped).
8. `install` / `rsync` destinations — the last non-flag token, or the `-t` / `--target-directory` operand.
9. `ln -f … LINK` — the link target, when `-f`/`--force` is present (without it `ln` refuses to clobber).
10. `sponge`/`ed`/`ex` FILE (the last non-flag token) and `patch` FILE (the FIRST non-flag token — a second positional would be the patch file itself, which is read-only) — ordinary in-place-edit tools with no redirect, tee, sed -i, cp/mv or interpreter op of their own.
11. `curl -o`/`--output` and `wget -O`/`--output-document` — a download landing directly on a protected path, no redirect needed.
12. Interpreter-mediated writes — a scripting runtime on the roster in [`lib/write-vectors.sh`](lib/write-vectors.sh) (python / node / bun / bunx / deno / tsx / perl / ruby / php / lua / tclsh / Rscript, plus awk variants) opening a file for writing, a `pathlib` write, an interpreter copy/rename destination, a truncation (`os.truncate`/`fs.truncateSync`/…), or an awk program redirecting `print` into a file. Fires only on the conjunction interpreter + write op + target, so a read-only interpreter call stays allowed. A bare-identifier target first resolves against an earlier same-command assignment binding it to a path literal (`p = pathlib.Path("<lit>")`, `Path("<lit>")`, or `p = "<lit>"`) — the same "follow the binding" step this vector already applies to a shell `$VAR`, one level down inside the interpreter body. Only a target that still cannot be resolved falls through to matching every path-shaped token in the command as a candidate — narrowed 2026-08-18 after that fallback, unnarrowed, blocked a state-file write over a phrase in unrelated markdown PROSE it was writing; the identical unnarrowed shape was deleted outright from `enforce-state-helper` on 2026-08-13 (below) once it was measured producing compliance under a third of the time.

Directory-targeted extraction (`tar -C <dir>`, `unzip -d <dir>`) is a known, accepted gap, not a silent one: both write through every vector above (measured rc 0) because the vectors resolve a FILE operand, not a directory a subsequent archive member lands in. Left open as a judgment call — modeling it would mean resolving archive-member names, which these guards do not attempt for any other channel either.

Heredoc bodies are scrubbed before vectors 1-11 run (they are data, so a doc heredoc mentioning `> tls.key` stays allowed). Quoted string literals are unquoted first, THEN blanked: a WHITESPACE-FREE quoted or backslash-escaped redirect target (`> "tls.key"`, `> 'tls.key'`, `> tls.k""ey`) is a single shell word, recovered by the unquote pass and still caught — only a quoted span that CONTAINS whitespace, i.e. prose (`echo "see > tls.key"`), is blanked as data and stays allowed. Vector 12 scans the heredoc-scrubbed text with quoted literals left INTACT instead, because an interpreter's write target IS a quoted literal (`open('tls.key','w')`) — blanking it would blind the vector on its own true positives, and a heredoc merely AUTHORING TEXT that mentions an interpreter write must not read as performing one. One exception: a heredoc body actually FED TO an interpreter's stdin (`python3 <<EOF … EOF`) is executed, not authored into a file, so vector 12 keeps that body intact too. fd-dups (`>&2`) and `/dev/null` never match.

**Shell indirection.** A write can also reach the filesystem through a payload the guard's own scrub would destroy, so those payloads are extracted BEFORE the scrub and the guard re-runs itself on each — a block inside propagates out, and recursion terminates because a payload is always shorter than the command it came from. Seven channels: the `sh`/`bash`/`zsh`/`dash`/`ksh`/`ash`/`fish`/`csh`/`tcsh`/`xonsh`/`nu`/`elvish`/`rc` `-c` family (any flag cluster containing `c`), `eval`, a quoted program piped to a shell, a heredoc body fed to a shell, a process substitution a shell reads, an interpreter's shell-out call (`os.system`, `subprocess`, `child_process.exec*`, a Ruby backtick, …), and a herestring (`bash <<< '<payload>'`) — the mirror image of the pipe channel, with the shell word first and the payload following the `<<<` operator. The shell word itself is matched structurally, not by name list: a path-qualified (`/bin/sh`) or quoted (`"sh"`) spelling and any wrapper prefix whose own arguments are flags, `VAR=value` assignments, durations, or `{}` placeholders (`sudo`, `nohup`, `timeout 5`, `env FOO=bar`, `setsid`, `busybox`, …) all resolve to the same shell. Canonical implementation and the single source for all of this: [`lib/write-vectors.sh`](lib/write-vectors.sh) — sourced by `block-dangerous-git.sh`, `block-geniro-deletion.sh`, `file-protection.sh`, and `security-pattern-check.sh`, with a verbatim inline fallback so a vendored install shipping `hooks/` without `lib/` still recurses.

**Protects:**
- `.git/*` — Git internal files
- `pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `bun.lockb`, `cargo.lock`, `Gemfile.lock`, `composer.lock`, `poetry.lock`, `Pipfile.lock`, `go.sum` — lock files, outside a disposable tree
- `*.pem` — PEM certificates / private keys
- `*.key` — private key files
- `credentials.*`, `secrets.*` — credential files
- `*.tfstate` — Terraform state
- `.vault` — Vault files

**Does NOT protect (carve-outs added 2026-08-13, each from a measured false positive):**
- **`.env` files, in every spelling** — the pattern was removed outright. Copying one into a fresh worktree, a fixture tree, or a backup is ordinary setup work, and each carve-out added for it (`.env.example`, `.env*bak*`) still left the next spelling blocking; a run that hits this guard resends the identical command or hands it back to the user. Content-level secret scanning still runs in `security-pattern-check.sh`.
- **Lock files inside a disposable tree** — `/tmp`, `/private/tmp`, `/var/folders` (macOS mktemp), or a session scratchpad. A lock file there is a fixture no resolver will read.

Credential, key and state patterns deliberately still fire inside a temp tree: a real secret written to `/tmp` is a real secret on disk.

On block the message now names **what to do instead** — regenerate the lock file from the manifest, reference a credential from the environment rather than committing it, use `git config` rather than hand-editing `.git/` — before mentioning the `safety.json` bypass. Naming only the bypass left a run with two moves, resend or widen the allow list, and resends were what it measurably chose.

Implementation: case-insensitive pattern match via lowercase conversion; exit 2 to block (fail-safe).

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` and reads `allow_patterns[]` to opt out of specific pattern IDs. On block, the error message names the pattern ID and tells the user the exact `safety.json` snippet to add (or how to create the file if it doesn't exist). Pattern IDs: `write-git-internal`, `write-lockfile`, `write-cert-key`, `write-credentials`, `write-tfstate`, `write-vault`.

**Degraded mode (no jq):** the hook cannot parse tool input, so it first scans the raw payload for the highest-signal protected names (`*.pem`, `*.key`, `credentials.*`, `secrets.*`) and exits 2 on a hit. Only a clean scan falls open, and it falls open loudly — a `systemMessage` names the guard as inactive.

### block-dangerous-git.sh

**Event:** PreToolUse `Bash`. **Stdin:** `jq -r '.tool_input.command // ""'`. **Block exit:** `exit 2`.

Blocks destructive git operations by pattern ID: `force-push`, `force-push-with-lease`, `reset-hard`, `branch-delete-force`, `clean-fd`, `checkout-mass-discard`, `restore-mass-discard`, `update-ref-delete`, `filter-branch`, `push-delete`, `stash-drop`. The `push-delete` pattern blocks remote-branch deletion — both `git push <remote> --delete <branch>` and the colon delete-refspec form `git push origin :branch` — which the local `branch-delete-force` matcher never saw. The `stash-drop` pattern blocks `git stash clear` (deletes every stash entry) and `git stash drop` (deletes one) — both unrecoverable once the underlying commits fall out of the reflog; `git stash pop`/`git stash push` stay allowed. Pads the command with whitespace, joins backslash-newline continuations, and collapses newlines so flag matchers (e.g. `[[:space:]]-f[[:space:]]`) hit reliably even at start/end of string or inside multi-line commands. Git GLOBAL options (`git -C <path> push`, `git -c k=v push`, `--git-dir`/`--work-tree`, pager flags) are stripped before matching, so they cannot break the `git <subcommand>` adjacency the matchers rely on. Checkout/restore matchers block a standalone `.` / `./` / `*` pathspec with or without `--` (`git checkout .`, `git checkout HEAD -- .`), AND — under the same `checkout-mass-discard` pattern ID — `git checkout`/`git switch` carrying `-f`/`--force`/`--discard-changes`, which discard the whole working tree with no pathspec at all. `reset-hard` additionally covers the plumbing equivalent `git read-tree --reset -u HEAD`, which resets the index and working tree exactly like `reset --hard`. `git clean` dry-run spans (`-n`/`--dry-run`) are previews and stay allowed, evaluated per-span so a dry span cannot mask a destructive sibling in the same command.

**Known false positive (accepted, not closed):** the quote-blanking pass excludes `; & |` from a quoted span so two ordinary prose apostrophes straddling a real separator cannot pair across it and blank a live command sitting between them (see the pass's own comment). The cost is the mirror case — a quoted literal that GENUINELY contains a destructive token alongside a pipe, e.g. `grep -rnE 'foo|git push --force|bar' docs/`, is never recognized as a balanced quote and so is never blanked, and the token inside matches as if it were live syntax. Measured: `grep -rn 'git push --force' docs/` allows (no pipe in the literal); `grep -rnE 'foo|git push --force|bar' docs/` blocks (a false positive) despite never running git at all. The trade-off is deliberate — the alternative reopens the prose-apostrophe false block — so this is a documented cost, not a bypass to close.

**Variable indirection is resolved.** Every matcher requires the git subcommand to be a literal token adjacent to `git`, so a subcommand, flag, or path arriving through a variable used to evade all of them. `lib/write-vectors.sh` §F now substitutes assigned literals back into the command before any matcher runs — one pass covering every pattern here and `block-geniro-deletion.sh`'s argument spans, rather than a second matching pass per pattern. `SUB=push; git $SUB --force origin main` and `P=.geniro; rm -rf $P` both block; `B=status; git $B` does not.

**Still open:** a command word produced by a substitution rather than an assignment (`$(echo git) push --force`). Nothing in a guard evaluates anything, so the output of an arbitrary command is not resolvable — and a guess would block on whatever the substitution happened to look like.

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` and reads `allow_patterns[]` to opt out of specific pattern IDs. On block, the error message tells the user the exact `safety.json` snippet to add (or how to create the file if it doesn't exist).

**Degraded mode (no jq):** the guard cannot parse the command out of the tool JSON, so it first scans the raw payload for the highest-signal destructive tokens (`--force` / `--force-with-lease`, `reset --hard`, `filter-branch`) and exits 2 on a hit. Only a clean scan falls open, loudly, with a `systemMessage` naming the guard as inactive. The scan is coarse by design — it also matches a token inside a quoted string — accepted for a rarely-hit path where blocking a real force-push matters more than a false positive on prose.

### block-geniro-deletion.sh

**Event:** PreToolUse `Bash`. **Stdin:** `jq -r '.tool_input.command // ""'`. **Block exit:** `exit 2`.

Prevents bulk deletion of `.geniro/`, which holds user-authored persistent state (instructions, actions, workflow, `_FEATURES.md`, learnings, planning artifacts). A single accidental `rm -rf .geniro/` destroys all of it. Joins backslash-newline continuations, pads, and collapses newlines (mirrors `block-dangerous-git.sh`); strips git GLOBAL options so `git -C <path> worktree remove` and `git -C <path> add -f .geniro/...` cannot evade the matchers; and blanks quoted-string literals that merely MENTION `rm` (e.g. `echo "do not rm -rf .geniro/"`) so a doc reference is not mistaken for a real delete.

**Allowed by design (NOT blocked):** `rm -f <single-file>` at any depth (required by skills' state cleanup), and `rm -rf .geniro/<top>/<sub>/` with 3+ path segments (task-dir / slug-scoped trees), plus single-file deletes under `.geniro/state/` (`.geniro/state/<file>.<ext>`) and 4+ segment slug-scoped state files.

**Blocked by default** (each evaluated per-rm-span and per-arg so a deep arg cannot mask a shallow sibling):

- `rm-geniro-tree` — whole-tree `rm -rf .geniro/`, including absolute / `$PWD/` / `../`-prefixed spellings, prefix globs (`.gen*`, `.geniro*`), trailing globs (`.geniro/*`), and doubled-slash forms.
- `rm-geniro-subdir` — `rm -rf .geniro/<single-segment>/` (e.g. `.geniro/instructions/`), including `..`-escape forms; also `rmdir .geniro/<single-segment>` — bounded (it only succeeds on an empty directory) but the same node-loss shape at that segment depth.
- `rm-geniro-state-subdir` — `rm -rf .geniro/state/<skill>/` directory wipes (parallel-branch slug files still in flight).
- `find-geniro-delete` — `find … .geniro … -delete`, `-exec` with any of `rm` / `mv` / `unlink` / `shred` / `truncate` / `rmdir`, and `| xargs rm` bulk-walk spellings.
- `worktree-remove-with-state` — `git worktree remove`, but only when the target really holds un-routed `.geniro/` state. The guard resolves the worktree path (absolute, or relative to a leading `cd`), then blocks only if `git status --porcelain --ignored` reports untracked or ignored files under its `.geniro/` — the content removal destroys for good. A worktree with no `.geniro/`, or one whose `.geniro/` is fully tracked, goes through, and the block lists the at-risk files by name. An unresolvable target (a variable, or a relative path with no `cd` to anchor it) stays fail-closed. Until 2026-08-13 it fired on the command shape alone and told the caller to "verify the worktree's `.geniro/` is empty" — a precondition the caller could satisfy but the guard could not observe, so verifying never unblocked anything and every measured trace ended with the removal done by hand or abandoned.
- `git-add-force-geniro` — `git add -f` / `--force` on `.geniro/` paths (force-adding ignored files surfaces them in the IDE Source Control panel, where a single "Discard All Changes" click becomes a one-click data-loss vector; track `.geniro/` subdirs via `.gitignore` negation instead).

**Variable indirection is resolved** by the same shared pass as `block-dangerous-git.sh` — see that guard's entry above, including what remains open.

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` and reads `allow_patterns[]`. On block, the error message names the pattern ID and the exact `safety.json` snippet to add.

**Degraded mode (no jq):** the guard cannot parse the command out of the tool JSON, so it first scans the raw payload for a recursive `rm` naming `.geniro` and exits 2 on a hit. Only a clean scan falls open, loudly, with a `systemMessage` naming the guard as inactive. Coarse by design (it also matches the token inside a quoted string), on the same trade-off as the git guard.

### session-start-restore.sh

**Event:** SessionStart `matcher: "compact|resume|startup"`. **Block exit:** never blocks. **Timeout:** 10s.

Wired as `SessionStart` with `matcher: "compact|resume|startup"` (Anthropic-canonical; `PostCompact` itself does not support `additionalContext`). `clear` is explicitly unmatched — user reset respected. Resolves the active T1.5 `state.md` via canonical slug match + frontmatter `branch:` fallback across all three layouts (planning task-dir / state-per-skill slug / state singleton). Candidates already in a terminal state — terminal `phase:` (`done`/`aborted`/`routed`/etc.) or terminal `status:` — are SKIPPED during resolution, so a finished task is never surfaced as resumable and cannot shadow an in-flight task on the same branch in a later tier (e.g. a done /plan task-dir next to a live /debug slug dir); a defense-in-depth gate re-checks the final pick. Pre-flights `validate_state_file` and degrades gracefully if the helper is missing.

Emits an `additionalContext` block-set:

- Per-source prefix (compact / resume / startup).
- Suggested files (L4 instructions set — `global.md` / `memory.md` / `code-style.md` / per-skill — routed through `load-custom-instructions.md` MODE: refresh; CLAUDE.md, `_FEATURES.md`, state.md, spec.md, plan.md as direct Reads).
- Validation-failure recovery directive (when `validate_state_file` reports a structural error).
- Helper-missing notice (when the validator binary itself is absent).
- Structured non-resumable-actions warning per state.md frontmatter (`git-push`, `pr-created`, `pr-comment-posted`, `pr-comment-amended`, `pr-review-comment-batch`, `git-commit`, `slack-notify-sent`, `release-tagged`, unknown-action fallback).
- Unresolved errors from state.md `## Errors`, pending `## Open Questions`, and persisted `approvals:` from state.md frontmatter — each entry's category, pick, phase and timestamp, plus its `why` and `result` when the producer recorded them. `evidence` stays in the file rather than the block.
- Resume protocol (suppressed when the resolved task is in a terminal state).
- Auto-archive of stale L2 entries (default ON, hash-gated + mkdir-locked for multi-tab safety; opt-out via `safety.json` `memory.auto_archive_stale: false`); when entries are flipped the `systemMessage` gains an "auto-archived: N" suffix.
- Verification-coverage line — the verified-fraction of live (non-deprecated) learnings (`verified: N/total (P%)`), computed independently of the auto-archive threshold so it surfaces every session (default ON, opt-out via `safety.json` `memory.show_coverage: false`); when present the `systemMessage` gains a "memory verified: N/total (P%)" suffix.
- Memory-backend-active notice — when `.geniro/instructions/memory.md` routes the `learnings` layer to a `replace`-mode backend (no local file), the coverage line is absent, so the `systemMessage` gains a "memory backend active" suffix in its place. Detection-only; the hook is shell and never queries the backend.

`systemMessage` one-liner emitted on every source except cold startup with no active task (an auto-archive event, a coverage line, or a memory-backend notice overrides that suppression). Read-only on state.md — never writes it; the only writes are `.geniro/knowledge/learnings.jsonl` (the auto-archive flip) and `.geniro/knowledge/.archive-stale.{hash,lock}` (the hash-gate + multi-tab lock).

### security-pattern-check.sh

**Event:** PreToolUse `Edit|Write|MultiEdit|NotebookEdit` AND `Bash` (registered under both matchers in `hooks.json`). **Stdin:** `jq -r '.tool_input.file_path // .tool_input.notebook_path // ""'` and `jq -r '.tool_input.content // .tool_input.new_string // .tool_input.new_source // ([.tool_input.edits[]?.new_string] | join("\n")) // ""'` for the file tools (Write's `.content`, Edit's `.new_string`, NotebookEdit's `.new_source`, MultiEdit's joined `.edits[].new_string`); `.tool_input.command` for Bash. **Block exit:** `exit 2`.

Cheap regex scan for high-signal, low-false-positive security anti-patterns in the content about to land in the file. Catches the obvious string-level wins at edit time without the LLM-cost of an ambient Stop-hook review.

Each pattern is scoped to applicable file extensions — Python's `pickle.loads` won't fire on `.js` files, JavaScript's `innerHTML=` won't fire on `.py` files. On match the hook prints to stderr (pattern ID, file, matched line, two remediation paths — rewrite the edit so the flagged construct is gone, OR add the pattern ID to `allow_patterns` in `.geniro/safety.json`) and exits 2. The scan reads content only, so an inline code comment justifying the pattern does not clear the block.

**Test files and scratch trees are out of scope (2026-08-13).** Skipped for every pattern: paths under `__tests__/`, `__mocks__/`, `test(s)/`, `spec/`, `e2e/`, `fixture(s)/`, `benchmark(s)/`; basenames matching `*.spec.*`, `*.test.*`, `*_test.*`, `test_*`, `conftest.py`; and anything under a session scratchpad. Every pattern here describes a code *shape* that is dangerous when it ships — none detects a leaked credential — and test code exercises those shapes on purpose: a jsdom spec asserts against `innerHTML`, a TLS test points at a self-signed local server, a security benchmark's whole job is to contain the unsafe construct. Measured 2026-08-13: two runs were blocked writing `.spec.tsx` files for `sec-xss-sink` and resent near-identical content, and a run authoring a security fixture was blocked writing the very construct the fixture existed to hold. The carve-out is keyed on path shape, not content, so a shipped module cannot claim it. Note it is deliberately *not* a blanket temp-directory exemption — `/tmp/x.py` is this hook's own suite's stand-in for an ordinary source file.

**Pattern IDs** (each individually bypassable):

| ID | Triggers on | Applicable extensions |
|---|---|---|
| `sec-eval-exec` | `eval(`, `exec(`, `new Function(` | `.py`, `.pyw`, `.pyx`, `.pyi` · `.js`, `.jsx`, `.ts`, `.tsx`, `.mjs`, `.cjs` |
| `sec-pickle` | `pickle.load(s)` | `.py`, `.pyw`, `.pyx`, `.pyi` |
| `sec-yaml-unsafe` | `yaml.load(` (use `yaml.safe_load`) | `.py`, `.pyw`, `.pyx`, `.pyi` |
| `sec-shell-injection` | `subprocess shell=True`, `os.system`, `os.popen` | `.py`, `.pyw`, `.pyx`, `.pyi` |
| `sec-curl-pipe-sh` | `curl … \| sh`, `wget … \| bash` | `.sh`, `.bash`, `.zsh`, Dockerfile (`Dockerfile`, `Dockerfile.*`, `*.dockerfile`) |
| `sec-tls-bypass` | `verify=False`, `rejectUnauthorized: false`, `--insecure`, `--no-check-certificate` | `.py`, `.pyw`, `.pyx`, `.pyi` · `.js`, `.jsx`, `.ts`, `.tsx`, `.mjs`, `.cjs` · `.sh`, `.bash`, `.zsh`, Dockerfile |
| `sec-xss-sink` | `.innerHTML=`, `dangerouslySetInnerHTML`, `document.write(` | `.js`, `.jsx`, `.ts`, `.tsx`, `.html`, `.mjs`, `.cjs`, `.vue`, `.svelte` |
| `sec-weak-crypto` | `createHash('md5'\|'sha1')`, `hashlib.md5/sha1` | `.js`, `.jsx`, `.ts`, `.tsx`, `.mjs`, `.cjs` · `.py`, `.pyw`, `.pyx`, `.pyi` |

**Per-project bypass:** walks up from cwd looking for `.geniro/safety.json` and reads `allow_patterns[]`. Adding any pattern ID disables that pattern entire project-wide:

```json
{"allow_patterns": ["sec-eval-exec", "sec-xss-sink"]}
```

**What this hook does NOT catch:** logic-level vulnerabilities (authorization bypass, IDOR, race conditions, mass assignment, JWT `alg: none`, business-logic flaws). Regex cannot see semantics. Run `/geniro:review` for the LLM-driven review that catches those.

**Degraded mode (no jq / no perl):** the scan is implemented in Perl (PCRE), so it depends on BOTH `jq` (to parse the tool JSON) and `perl` (to run the patterns) — either missing disables the whole hook. Unlike `file-protection.sh` and the other data-loss guards, there is no coarse raw-text fallback for either: a missing `perl` means the pattern set itself cannot run, so the hook exits 0 and emits a `systemMessage` naming which dependency is absent and that the scan is inactive. Install the missing tool to restore it.

### enforce-state-helper.sh

**Event:** PreToolUse `Edit|Write|MultiEdit|NotebookEdit`. **Block exit:** `exit 2`.

Blocks direct `Edit` / `Write` / `MultiEdit` calls against canonical state paths and suggests routing through `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` (`atomic_state_write` for plain files, `atomic_state_append` for JSONL) — direct calls truncate-and-rewrite, so a reader during the window sees a partial file. Protected prefixes: `.geniro/state/`, `.geniro/planning/`, `.geniro/knowledge/`, `.geniro/instructions/`, `.geniro/actions/`, `.geniro/workflow/` (plus `.geniro/.geniro-state.json`).

**A block is not a file-write denial:** the path stays writable — only this direct route is closed. The stderr message says so explicitly and names the required helper call, so a blocked run should route through it rather than reporting the file as unwritable or drafting a manual patch for the user to apply.

**No Bash branch — removed 2026-08-13.** This guard matches file tools only. They carry a declared `file_path`, so the target is read rather than inferred.

The removed branch had no such field: it reconstructed write targets from the command string across twelve vectors and seven shell-indirection channels, and when a target came back unresolved (`open(p,'w')`, a variable) it fell back to matching any `.geniro/` string **anywhere** in the command — justified in-code on the grounds that a path which is not the real target "costs nothing".

Measured across 1,408 sessions it was the largest single source of hook friction in the plugin: 67 blocks, compliance under a third of the time, the remainder a near-identical retry or a workaround. What it actually caught included an edit to `MIGRATION.md` whose prose mentioned `.geniro/instructions/plan.md`, and the fragment `./.geniro/planning/t` lifted out of a Python heredoc — not a path at all.

Shell-side atomicity is now a prose contract (`CLAUDE.md` §State Files) rather than an enforced one. That is a real loss of coverage, accepted deliberately: an undetected shell write is one class of corruption, while a guard that blocks the wrong writes teaches every run to route around guards in general — and the traces show it did.

**Exemptions:** `.geniro/state/tdd/` (the TDD cycle's own RED-phase state file, a documented exception written via its own mktemp + mv procedure, per `skills/_shared/tdd-cycle.md` §State file contract), coordination locks (`*.lock`), the fingerprint JSON, atomic-write temp files, editor swap/backup files, and transient T1 scratch. T1 is recognised by SHAPE — any dot-prefixed basename under `.geniro/`, plus `notes.md` and `playwright-verify.png` — not by a roster of known filenames. The roster version blocked `.review-round1.md` six times in one run, a name it never anticipated, with nothing in the deny text to reveal what the roster held. No canonical state file is dot-prefixed, so the shape cannot swallow a durable one; `.geniro/.geniro-state.json` is the sole dot-prefixed guarded path and is decided before the exemption runs. A write under `.geniro/state/` that matches no canonical layout (`state/<skill>/<slug>/state.md`, the `state/setup/state.md` singleton, `state/handoff/from-<producer>-<branch>.md`, `state/tdd/state-<slug>.md`) gets an extra hint — ad-hoc files there are invisible to the validator and session-restore.

**`.geniro/safety.json` itself is guarded**, under its own pattern ID `safety-json-edit` rather than the broad `enforce-state-helper` one. That file disables every guard by pattern ID, so an agent must not be able to self-grant a bypass in a single write. A deliberate edit still goes through — add `safety-json-edit` to `allow_patterns[]`, or edit the file outside the agent.

This guard shares the directory-targeted extraction gap documented above under `file-protection.sh` (`tar -C <dir>`, `unzip -d <dir>`): both write through it (measured rc 0) for the same reason — the vectors above resolve a FILE operand, not a directory an archive member lands in. Here that gap has a sharper blast radius than elsewhere: `tar -xf x.tar -C .geniro` can land a `safety.json` write and self-grant a bypass on every other guard in one command, the exact self-grant this pattern ID exists to close. Same accepted trade-off as `file-protection.sh`, not a separate defect.

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` `allow_patterns[]`; pattern ID `enforce-state-helper` skips the block, and `safety-json-edit` skips the safety.json guard above. When jq is missing the hook still runs a coarse raw-text scan of the payload first and blocks on a canonical state path or on `.geniro/safety.json`; only after that scan finds nothing does it emit a `systemMessage` and allow. The scan needs no jq, so the guard degrades rather than disappearing.

### geniro-check-update.js

**Event:** SessionStart. **Block exit:** never blocks. **Timeout:** 5s.

Spawns a detached child process via `spawn(..., detached: true, stdio: 'ignore')` then `child.unref()`; the parent consumes stdin and exits immediately so session start is never blocked. The child fetches GitHub `releases/latest` (10s timeout, fallback to `raw.githubusercontent.com`) and writes the result to `~/.claude/cache/geniro-update-check.json`. The status line consumes that cache to surface "update available" indicators.

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

## Testing

```bash
# Test file protection (expect exit code 2 = blocked)
echo '{"tool_input":{"file_path":"/config/credentials.json"}}' | ./hooks/file-protection.sh
echo "exit=$?"

# Test security pattern scan (expect exit code 2 = blocked)
echo '{"tool_input":{"file_path":"/tmp/x.py","content":"r = eval(s)"}}' | ./hooks/security-pattern-check.sh
echo "exit=$?"

# Full smoke-test suite
bash tests/hooks/security-pattern-check.sh
```

## Key Safety Principles

1. **Exit Code 2 for Blocking** — Never use exit 1 (which is FAIL-OPEN)
2. **Stdin Consumption** — All hooks consume stdin as first action
3. **JSON Parsing** — Use jq for safe input extraction
4. **Error Messages to Stderr** — Clear feedback redirected to user
5. **Graceful Degradation** — hooks fail open when a dependency (e.g. `jq`) is missing: safety guards loudly (a `systemMessage` says the guard is not running), convenience reminders silently (never wedge the session). The data-loss guards — `file-protection.sh`, `block-dangerous-git.sh`, `block-geniro-deletion.sh`, and `enforce-state-helper.sh` — fail open only *after* a coarse raw-text scan of the payload for their highest-signal tokens; a hit there still exits 2, because on these a false positive costs less than a clobbered credential file, a force-pushed branch, a wiped `.geniro/`, or an unrouted state-path write
6. **Case Insensitivity** — File patterns are case-insensitive

## Sources & References

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide)
- Exit code behavior: Exit 0 = allow, Exit 2 = block (PreToolUse only); PostToolUse / Stop / SessionStart always exit 0
- statusLine wiring: see [`settings.json`](settings.json) and [Claude Code statusLine docs](https://code.claude.com/docs/en/statusline)
