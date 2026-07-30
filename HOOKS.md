# Geniro Plugin — Hooks Documentation

Production-grade hooks for the geniro plugin. All hooks follow best practices from the official Claude Code documentation and proven implementations from Citadel, Claude Forge, and claude-pipeline.

## Configuration overview

Hook configuration is **split** across three files:

| File | Purpose |
|---|---|
| [`hooks/hooks.json`](hooks/hooks.json) | Registers event-driven hooks (PreToolUse, Stop, SessionStart) for Claude Code. Auto-discovered at the `hooks/hooks.json` convention path — deliberately NOT declared in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json), which stays metadata-only. Adding a `hooks` field there would duplicate an auto-discovered path and risk double-registration; see [`.claude-plugin/PLUGIN_SCHEMA_NOTES.md`](.claude-plugin/PLUGIN_SCHEMA_NOTES.md) §Component declaration. |
| [`settings.json`](settings.json) (root) | Defines the `statusLine` command. The status line is NOT a Claude Code hook — it's a separate display feature. Plugin-shipped `settings.json` cannot grant permissions (Claude Code ignores a `permissions` block here) — permission rules belong in the consumer's own user/project settings. |
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

Wired for Cursor: all six Bash guards on `beforeShellExecution` — the destructive-git guard, the `.geniro/` deletion guard, protected-file writes, state-helper enforcement, TDD-order enforcement, and the security pattern scan — and four of those six again on `preToolUse` file-write events (protected-file writes, TDD-order, state-helper, security pattern scan), plus session-start restore. The destructive-git and `.geniro/`-deletion guards are shell-only in BOTH runtimes: they inspect a command string, and a file-write event carries a path with no command to read — the same split `hooks/hooks.json` uses.

**Deliberately not wired for Cursor** — the runtime has no compatible slot, so the conventions apply as instructions per [`skills/_shared/runtime-portability.md`](skills/_shared/runtime-portability.md) instead: the gate-render guard (`AskUserQuestion` has no hook event), the evidence-on-completion reminder (no `Stop` event), and the marketplace update check (Claude Code's `claude plugin` registry only). Add a new hook to `cursor/hooks.json` only when its event maps cleanly onto the translation map at the top of the shim.

## Hook scripts

The plugin ships 9 safety / lifecycle hooks, 1 sourced utility library, and 2 Node-based feature scripts:

| Script | Event | Blocking | Description |
|---|---|---|---|
| [`file-protection.sh`](hooks/file-protection.sh) | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` AND `Bash` | exit 2 = block | Blocks writes to `.env`, lock files, keys, credentials. The Bash branch catches shell-side writes into the same protected paths — redirection (`>`, `>>`, `>\|`), `tee`, in-place `sed -i`, `cp`/`mv` destinations, `dd of=`, `truncate`, `shred`, `install`/`rsync` destinations, `ln -f` link targets, and interpreter-mediated writes — plus the shell-indirection channels it re-runs itself on (`sh -c`, `eval`, a pipe into a shell, a heredoc fed to one, a process substitution, an interpreter shelling out). Reads stay allowed. Bypass: `write-env`, `write-git-internal`, `write-lockfile`, `write-cert-key`, `write-credentials`, `write-tfstate`, `write-vault` |
| [`block-dangerous-git.sh`](hooks/block-dangerous-git.sh) | PreToolUse `Bash` | exit 2 = block | Blocks destructive git: force-push, reset --hard, branch -D, clean -fd, mass-discard checkout/restore, update-ref -d, filter-branch, remote-branch deletion (`git push --delete` / colon-refspec) |
| [`block-geniro-deletion.sh`](hooks/block-geniro-deletion.sh) | PreToolUse `Bash` | exit 2 = block | Blocks bulk deletion of `.geniro/` (bypass: `rm-geniro-tree`, `rm-geniro-subdir`, `rm-geniro-state-subdir`, `find-geniro-delete`, `worktree-remove-with-state`, `git-add-force-geniro`) |
| [`enforce-tdd-order.sh`](hooks/enforce-tdd-order.sh) | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` AND `Bash` | exit 2 = block | Blocks edits to non-test files when `.geniro/state/tdd/state-<slug>.md` shows `phase: RED` (bypass: `tdd-order`) |
| [`enforce-state-helper.sh`](hooks/enforce-state-helper.sh) | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` AND `Bash` | exit 2 = block | Blocks direct writes to canonical state paths under `.geniro/state/`, `.geniro/planning/`, `.geniro/knowledge/`, `.geniro/instructions/`, `.geniro/actions/`, `.geniro/workflow/`. The Bash branch catches shell-side writes into the same paths — the same vector set as `file-protection.sh` (redirection, `tee`, `sed -i`, `cp`/`mv` destinations, `dd of=`, `truncate`, `shred`, `install`/`rsync` destinations, `ln -f` link targets, interpreter-mediated writes) plus the shell-indirection channels it re-runs itself on. Reads stay allowed; commands invoking `atomic_state_write` / `atomic_state_append` pass. Suggests the helpers per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`. Bypass: `enforce-state-helper`. |
| [`enforce-gate-render.sh`](hooks/enforce-gate-render.sh) | PreToolUse `AskUserQuestion` | exit 2 = block | Blocks a gate question fired with no visible assistant message in the current turn — the user would be answering blind — on either of two triggers: it references content "above", OR it carries finding-gate evidence shorthand (a PRODUCT-DECISION tag, convergence wording, or a finding-ID like `F5`/`M1b` with finding-gate co-text). Reverse-scans the transcript to the last real user message (2000-record cap, one 0.4s retry against the transcript lazy-flush race); fails open on missing jq (loud), missing transcript, cap overflow, or garbage transcript. A block is NOT a user denial — stderr instructs render-then-re-ask (bypass: `gate-render`) |
| [`security-pattern-check.sh`](hooks/security-pattern-check.sh) | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` AND `Bash` | exit 2 = block | Cheap regex scan for high-signal security anti-patterns in file content (eval/exec, pickle, yaml.load, shell=True, curl\|sh, TLS bypass, XSS sinks, weak crypto). Per-pattern bypass: `sec-eval-exec`, `sec-pickle`, `sec-yaml-unsafe`, `sec-shell-injection`, `sec-curl-pipe-sh`, `sec-tls-bypass`, `sec-xss-sink`, `sec-weak-crypto`. Scope-limited to applicable file extensions per pattern. Logic-level issues (authz bypass, IDOR, race conditions) are not regex-detectable and require `/geniro:review`. |
| [`require-evidence-on-completion.sh`](hooks/require-evidence-on-completion.sh) | Stop `*` | warn-only (always exit 0) | Scans last assistant message for completion phrases without an Evidence Block (bypass: `evidence-stop`) |
| [`session-start-restore.sh`](hooks/session-start-restore.sh) | SessionStart `matcher: "compact\|resume\|startup"` | non-blocking | Compaction-survival. Resolves the active T1 state.md across all three layouts (planning task-dir / state-per-skill / state singleton); skips state.md candidates already in a terminal `phase:`/`status:` during resolution, so a finished task is never surfaced as resumable AND cannot shadow an in-flight task on the same branch in a later resolution tier; pre-flights `validate_state_file`; emits an `additionalContext` block-set (per-source prefix · suggested files · validation-failure recovery · helper-missing notice · non-resumable-actions warning · `## Errors` / `## Open Questions` / persisted `approvals:` from state.md frontmatter · resume protocol). Also runs L2 auto-archive. Read-only on state.md; the only writes are `learnings.jsonl` (auto-archive flip) + `.archive-stale.{hash,lock}`. |
| [`geniro-check-update.js`](hooks/geniro-check-update.js) | SessionStart | non-blocking, detached | Background-checks GitHub for plugin updates |
| [`geniro-statusline.js`](hooks/geniro-statusline.js) | `statusLine.command` (settings.json) | non-blocking | Two-row width-justified status line (model — effort · task · topic · 5h limit · cost · update / dir · context · last prompt) |
| [`backpressure.sh`](hooks/backpressure.sh) | **NOT registered** — utility library | — | Sourced by skills (e.g. /refactor, /review) to compress verbose test/build output |

### file-protection.sh

**Event:** PreToolUse `Edit|Write|MultiEdit|NotebookEdit` AND `Bash` (registered under both matchers in `hooks.json`; the script branches on `tool_name`). **Stdin:** `.tool_input.file_path` (or `.tool_input.notebook_path` for NotebookEdit) for the file tools; `.tool_input.command` for Bash. **Block exit:** `exit 2`.

**Bash branch:** extracts write targets the file-tool matcher never sees, then runs the same pattern set against each. Ten vectors:

1. Redirection targets — `>`, `>>`, `>|`.
2. `tee` arguments (every non-flag token).
3. File arguments of an in-place `sed -i` span (the sed SCRIPT token is skipped — it is code, not a path).
4. `cp`/`mv` destinations (the last non-flag token — copying FROM a protected file is a read and stays allowed).
5. `dd of=` targets.
6. `truncate` file arguments (the `-s` size operand is skipped).
7. `shred` file arguments (the `-n`/`-s` count operands are skipped).
8. `install` / `rsync` destinations — the last non-flag token, or the `-t` / `--target-directory` operand.
9. `ln -f … LINK` — the link target, when `-f`/`--force` is present (without it `ln` refuses to clobber).
10. Interpreter-mediated writes — a scripting runtime on the roster in [`lib/write-vectors.sh`](lib/write-vectors.sh) (python / node / bun / bunx / deno / tsx / perl / ruby / php / lua / tclsh / Rscript, plus awk variants) opening a file for writing, a `pathlib` write, an interpreter copy/rename destination, or an awk program redirecting `print` into a file. Fires only on the conjunction interpreter + write op + target, so a read-only interpreter call stays allowed. When the target is a variable the command text cannot resolve, every path-shaped token in the command becomes a candidate.

Heredoc bodies and quoted string literals are scrubbed before vectors 1-9 run (they are data, so `echo "see > .env"` and a doc heredoc mentioning `> .env` stay allowed); the trade-off is that a deliberately QUOTED redirect target (`> ".env"`) is a documented miss. Vector 10 scans the RAW command instead, because an interpreter's file write is not shell syntax anywhere. fd-dups (`>&2`) and `/dev/null` never match.

**Shell indirection.** A write can also reach the filesystem through a payload the guard's own scrub would destroy, so those payloads are extracted BEFORE the scrub and the guard re-runs itself on each — a block inside propagates out, and recursion terminates because a payload is always shorter than the command it came from. Six channels: the `sh -c` family (any flag cluster containing `c`), `eval`, a quoted program piped to a shell, a heredoc body fed to a shell, a process substitution a shell reads, and an interpreter's shell-out call (`os.system`, `subprocess`, `child_process.exec*`, a Ruby backtick, …). The shell word itself is matched structurally, not by name list: a path-qualified (`/bin/sh`) or quoted (`"sh"`) spelling and any wrapper prefix whose own arguments are flags, `VAR=value` assignments, durations, or `{}` placeholders (`sudo`, `nohup`, `timeout 5`, `env FOO=bar`, `setsid`, `busybox`, …) all resolve to the same shell. Canonical implementation and the single source for all of this: [`lib/write-vectors.sh`](lib/write-vectors.sh) — all six Bash guards source it, with a verbatim inline fallback so a vendored install shipping `hooks/` without `lib/` still recurses.

**Protects:**
- `.env` and `.env.*` (e.g. `.env.local`, `.env.production`)
- `.git/*` — Git internal files
- `pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `bun.lockb`, `cargo.lock`, `Gemfile.lock`, `composer.lock`, `poetry.lock`, `Pipfile.lock`, `go.sum` — lock files
- `*.pem` — PEM certificates / private keys
- `*.key` — private key files
- `credentials.*`, `secrets.*` — credential files
- `*.tfstate` — Terraform state
- `.vault` — Vault files

Implementation: case-insensitive pattern match via lowercase conversion; exit 2 to block (fail-safe).

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` and reads `allow_patterns[]` to opt out of specific pattern IDs. On block, the error message names the pattern ID and tells the user the exact `safety.json` snippet to add (or how to create the file if it doesn't exist). Pattern IDs: `write-env`, `write-git-internal`, `write-lockfile`, `write-cert-key`, `write-credentials`, `write-tfstate`, `write-vault`.

**Degraded mode (no jq):** the hook cannot parse tool input, so it first scans the raw payload for the highest-signal protected names (`.env`, `*.pem`, `*.key`, `credentials.*`, `secrets.*`) and exits 2 on a hit. Only a clean scan falls open, and it falls open loudly — a `systemMessage` names the guard as inactive.

### block-dangerous-git.sh

**Event:** PreToolUse `Bash`. **Stdin:** `jq -r '.tool_input.command // ""'`. **Block exit:** `exit 2`.

Blocks destructive git operations by pattern ID: `force-push`, `force-push-with-lease`, `reset-hard`, `branch-delete-force`, `clean-fd`, `checkout-mass-discard`, `restore-mass-discard`, `update-ref-delete`, `filter-branch`, `push-delete`. The `push-delete` pattern blocks remote-branch deletion — both `git push <remote> --delete <branch>` and the colon delete-refspec form `git push origin :branch` — which the local `branch-delete-force` matcher never saw. Pads the command with whitespace, joins backslash-newline continuations, and collapses newlines so flag matchers (e.g. `[[:space:]]-f[[:space:]]`) hit reliably even at start/end of string or inside multi-line commands. Git GLOBAL options (`git -C <path> push`, `git -c k=v push`, `--git-dir`/`--work-tree`, pager flags) are stripped before matching, so they cannot break the `git <subcommand>` adjacency the matchers rely on. Checkout/restore matchers block a standalone `.` / `./` / `*` pathspec with or without `--` (`git checkout .`, `git checkout HEAD -- .`); `git clean` dry-run spans (`-n`/`--dry-run`) are previews and stay allowed, evaluated per-span so a dry span cannot mask a destructive sibling in the same command.

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` and reads `allow_patterns[]` to opt out of specific pattern IDs. On block, the error message tells the user the exact `safety.json` snippet to add (or how to create the file if it doesn't exist).

**Degraded mode (no jq):** the guard cannot parse the command out of the tool JSON, so it first scans the raw payload for the highest-signal destructive tokens (`--force` / `--force-with-lease`, `reset --hard`, `filter-branch`) and exits 2 on a hit. Only a clean scan falls open, loudly, with a `systemMessage` naming the guard as inactive. The scan is coarse by design — it also matches a token inside a quoted string — accepted for a rarely-hit path where blocking a real force-push matters more than a false positive on prose.

### block-geniro-deletion.sh

**Event:** PreToolUse `Bash`. **Stdin:** `jq -r '.tool_input.command // ""'`. **Block exit:** `exit 2`.

Prevents bulk deletion of `.geniro/`, which holds user-authored persistent state (instructions, actions, workflow, `_FEATURES.md`, learnings, planning artifacts). A single accidental `rm -rf .geniro/` destroys all of it. Joins backslash-newline continuations, pads, and collapses newlines (mirrors `block-dangerous-git.sh`); strips git GLOBAL options so `git -C <path> worktree remove` and `git -C <path> add -f .geniro/...` cannot evade the matchers; and blanks quoted-string literals that merely MENTION `rm` (e.g. `echo "do not rm -rf .geniro/"`) so a doc reference is not mistaken for a real delete.

**Allowed by design (NOT blocked):** `rm -f <single-file>` at any depth (required by skills' state cleanup), and `rm -rf .geniro/<top>/<sub>/` with 3+ path segments (task-dir / slug-scoped trees), plus single-file deletes under `.geniro/state/` (`.geniro/state/<file>.<ext>`) and 4+ segment slug-scoped state files.

**Blocked by default** (each evaluated per-rm-span and per-arg so a deep arg cannot mask a shallow sibling):

- `rm-geniro-tree` — whole-tree `rm -rf .geniro/`, including absolute / `$PWD/` / `../`-prefixed spellings, prefix globs (`.gen*`, `.geniro*`), trailing globs (`.geniro/*`), and doubled-slash forms.
- `rm-geniro-subdir` — `rm -rf .geniro/<single-segment>/` (e.g. `.geniro/instructions/`), including `..`-escape forms.
- `rm-geniro-state-subdir` — `rm -rf .geniro/state/<skill>/` directory wipes (parallel-branch slug files still in flight).
- `find-geniro-delete` — `find … .geniro … -delete`, `-exec` with any of `rm` / `mv` / `unlink` / `shred` / `truncate`, and `| xargs rm` bulk-walk spellings.
- `worktree-remove-with-state` — `git worktree remove` (worktrees often hold un-routed `.geniro/` state).
- `git-add-force-geniro` — `git add -f` / `--force` on `.geniro/` paths (force-adding ignored files surfaces them in the IDE Source Control panel, where a single "Discard All Changes" click becomes a one-click data-loss vector; track `.geniro/` subdirs via `.gitignore` negation instead).

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` and reads `allow_patterns[]`. On block, the error message names the pattern ID and the exact `safety.json` snippet to add.

**Degraded mode (no jq):** the guard cannot parse the command out of the tool JSON, so it first scans the raw payload for a recursive `rm` naming `.geniro` and exits 2 on a hit. Only a clean scan falls open, loudly, with a `systemMessage` naming the guard as inactive. Coarse by design (it also matches the token inside a quoted string), on the same trade-off as the git guard.

### enforce-tdd-order.sh

**Event:** PreToolUse `Edit|Write|MultiEdit|NotebookEdit` AND `Bash` (registered under both matchers in `hooks.json`). **Stdin:** `jq -r '.tool_input.file_path // .tool_input.notebook_path // ""'` for the file tools; `.tool_input.command` for Bash. **Block exit:** `exit 2`.

Enforces the test-first cycle: when `.geniro/state/tdd/state-<slug>.md` shows `phase: RED`, an `Edit`/`Write` against a production-code file is blocked — author the failing test before the production code. Test files stay editable (that is the file you are supposed to be writing in RED). If the state file is absent, the skill has not opted in to TDD, so the hook exits 0 — no surprise blocks.

The branch slug is derived per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` §Slug rules, single-sourced in `lib/branch-slug.sh` with an inline fallback so the hook still works on a vendored install without `lib/`. The state lookup resolves the nearest project root (the directory holding `.geniro/`) walking up from cwd; TDD state is task-local, so a linked worktree keeps its OWN `.geniro/state/tdd/` and the lookup deliberately does NOT redirect to the primary worktree. Test-file detection matches `__tests__/`, `tests/` / `test/` directories, `*.spec.*`, `*_test.go`, and anchored filename conventions (`test_*`, `*-test.*`, `*.test.*`) — production files that merely contain the substring "test" (`contestant.ts`, `testimonials.tsx`) are not mistaken for tests.

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` `allow_patterns[]`; pattern ID `tdd-order` skips the block. Fails open loudly (emits a `systemMessage`) if jq is missing.

### session-start-restore.sh

**Event:** SessionStart `matcher: "compact|resume|startup"`. **Block exit:** never blocks. **Timeout:** 10s.

Wired as `SessionStart` with `matcher: "compact|resume|startup"` (Anthropic-canonical; `PostCompact` itself does not support `additionalContext`). `clear` is explicitly unmatched — user reset respected. Resolves the active T1 `state.md` via canonical slug match + frontmatter `branch:` fallback across all three layouts (planning task-dir / state-per-skill slug / state singleton). Candidates already in a terminal state — terminal `phase:` (`done`/`aborted`/`routed`/etc.) or terminal `status:` — are SKIPPED during resolution, so a finished task is never surfaced as resumable and cannot shadow an in-flight task on the same branch in a later tier (e.g. a done /plan task-dir next to a live /debug slug dir); a defense-in-depth gate re-checks the final pick. Pre-flights `validate_state_file` and degrades gracefully if the helper is missing.

Emits an `additionalContext` block-set:

- Per-source prefix (compact / resume / startup).
- Suggested files (L4 instructions set — `global.md` / `memory.md` / `code-style.md` / per-skill — routed through `load-custom-instructions.md` MODE: refresh; CLAUDE.md, `_FEATURES.md`, state.md, spec.md, plan.md as direct Reads).
- Validation-failure recovery directive (when `validate_state_file` reports a structural error).
- Helper-missing notice (when the validator binary itself is absent).
- Structured non-resumable-actions warning per state.md frontmatter (`git-push`, `pr-created`, `pr-comment-posted`, `pr-comment-amended`, `pr-review-comment-batch`, `git-commit`, `slack-notify-sent`, `release-tagged`, unknown-action fallback).
- Unresolved errors from state.md `## Errors`, pending `## Open Questions`, and persisted `approvals:` from state.md frontmatter.
- Resume protocol (suppressed when the resolved task is in a terminal state).
- Auto-archive of stale L2 entries (default ON, hash-gated + mkdir-locked for multi-tab safety; opt-out via `safety.json` `memory.auto_archive_stale: false`); when entries are flipped the `systemMessage` gains an "auto-archived: N" suffix.
- Verification-coverage line — the verified-fraction of live (non-deprecated) learnings (`verified: N/total (P%)`), computed independently of the auto-archive threshold so it surfaces every session (default ON, opt-out via `safety.json` `memory.show_coverage: false`); when present the `systemMessage` gains a "memory verified: N/total (P%)" suffix.
- Memory-backend-active notice — when `.geniro/instructions/memory.md` routes the `learnings` layer to a `replace`-mode backend (no local file), the coverage line is absent, so the `systemMessage` gains a "memory backend active" suffix in its place. Detection-only; the hook is shell and never queries the backend.

`systemMessage` one-liner emitted on every source except cold startup with no active task (an auto-archive event, a coverage line, or a memory-backend notice overrides that suppression). Read-only on state.md — never writes it; the only writes are `.geniro/knowledge/learnings.jsonl` (the auto-archive flip) and `.geniro/knowledge/.archive-stale.{hash,lock}` (the hash-gate + multi-tab lock).

### security-pattern-check.sh

**Event:** PreToolUse `Edit|Write|MultiEdit|NotebookEdit` AND `Bash` (registered under both matchers in `hooks.json`). **Stdin:** `jq -r '.tool_input.file_path // ""'` and `jq -r '.tool_input.content // .tool_input.new_string // ""'` for the file tools; `.tool_input.command` for Bash. **Block exit:** `exit 2`.

Cheap regex scan for high-signal, low-false-positive security anti-patterns in the content about to land in the file. Catches the obvious string-level wins at edit time without the LLM-cost of an ambient Stop-hook review.

Each pattern is scoped to applicable file extensions — Python's `pickle.loads` won't fire on `.js` files, JavaScript's `innerHTML=` won't fire on `.py` files. On match the hook prints to stderr (pattern ID, file, matched line, two remediation paths — rewrite the edit so the flagged construct is gone, OR add the pattern ID to `allow_patterns` in `.geniro/safety.json`) and exits 2. The scan reads content only, so an inline code comment justifying the pattern does not clear the block.

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

### enforce-state-helper.sh

**Event:** PreToolUse `Edit|Write|MultiEdit|NotebookEdit` AND `Bash` (registered under both matchers in `hooks.json`; the script branches on `tool_name`). **Block exit:** `exit 2`.

Blocks direct `Edit` / `Write` / `MultiEdit` calls against canonical state paths and suggests routing through `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` (`atomic_state_write` for plain files, `atomic_state_append` for JSONL) — direct calls truncate-and-rewrite, so a reader during the window sees a partial file. Protected prefixes: `.geniro/state/`, `.geniro/planning/`, `.geniro/knowledge/`, `.geniro/instructions/`, `.geniro/actions/`, `.geniro/workflow/` (plus `.geniro/.geniro-state.json`).

**Bash branch:** extracts write targets the file-tool matcher never sees, then runs the same path check against each (reads stay allowed). It carries the same ten vectors as `file-protection.sh` above — redirection, `tee`, in-place `sed -i`, `cp`/`mv` destinations, `dd of=`, `truncate`, `shred`, `install`/`rsync` destinations, `ln -f` link targets, and interpreter-mediated writes — plus the same six shell-indirection channels it re-runs itself on. One carve-out is specific to this guard: a `cp`/`mv` whose SOURCE is already under `.geniro/` is a housekeeping rename/copy of helper-written content and stays allowed. Heredoc bodies and quoted string literals are scrubbed before the syntax vectors run (they are data, not writes). Commands invoking the sanctioned helpers (`atomic_state_write` / `atomic_state_append`) pass — they write via their own mktemp + mv.

**Exemptions:** `.geniro/state/tdd/` (the TDD-order hook's state file is a documented exception written via its own mktemp + mv procedure, per `skills/_shared/tdd-cycle.md` §State file contract), coordination locks (`*.lock`), the fingerprint JSON, atomic-write temp files, editor swap/backup files, and deterministically-transient T1 subagent outputs (`.kr-out.md` and siblings, `.research-<facet>.md`, `notes.md`, `playwright-verify.png`). A write under `.geniro/state/` that matches no canonical layout (`state/<skill>/<slug>/state.md`, the `state/setup/state.md` singleton, `state/handoff/from-<producer>-<branch>.md`, `state/tdd/state-<slug>.md`) gets an extra hint — ad-hoc files there are invisible to the validator and session-restore.

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` `allow_patterns[]`; pattern ID `enforce-state-helper` skips the block. Fails open loudly (emits a `systemMessage`) if jq is missing.

### enforce-gate-render.sh

**Event:** PreToolUse `AskUserQuestion`. **Stdin:** `.tool_input.questions[]` (question text, option labels, option descriptions) and `.transcript_path`. **Block exit:** `exit 2`.

Mechanical backstop for the message-first gate contract (`skills/_shared/gate-rendering.md`): a decision question that points at content "above" must be preceded by a visible assistant message in the current turn, or the user is answering blind. Prompt-level render guards leak under drift; this hook enforces the contract at the tool boundary.

**Triggers (three branches):** branches (a) and (b) are render-dependent — they fire only when combined with no visible assistant text in the current turn. Branch (c) is render-independent — it fires on the shape of the call alone, regardless of render state.

- **(a) "above"-reference** — the standalone word "above", case-insensitive and word-bounded so "abovementioned" does not match, anywhere across every question's text, option labels, and option descriptions. Templated gate questions ("Full explanation above." / "Approve the spec summarized above?") hit this branch.
- **(b) finding-gate evidence shorthand without "above"** — a real `/review` open-decision gate can fire with finding IDs and convergence wording but no "above", which the (a)-only guard let slip (the recorded evasion: "strip the 'above' reference"). A `PRODUCT-DECISION` tag or convergence wording (`converge` / `converged` / `convergence`) fires on its own. A finding-ID token (case-sensitive uppercase F/M + digits + optional trailing lowercase letter, e.g. `F5` / `M1b`) fires only with finding-gate co-text — a severity word right after an open paren (`(MEDIUM, security)`), or the words finding / findings / reviewer / severity — because the bare token alone collides with load-balancer models, function keys, and version tags.
- **(c) finding-batching guard (render-independent)** — a single `AskUserQuestion` call whose `questions[]` holds ≥2 entries that EACH read like a product-decision gate (the same per-question shorthand the render guard uses — `PRODUCT-DECISION` / convergence, OR a finding-ID + finding-gate co-text) is the tabbed F3/F4/F5 batch, and is blocked no matter what precedes it in the turn — product-decision findings are resolved one at a time (one call per finding, each preceded by its own rendered chat block), so no single chat render can precede a multi-finding call. `/plan`'s clarifying batch (≤4 questions carrying none of that shorthand) does not match. Recovery: fire one question per finding in sequence.

**Turn detection:** reverse-scans the transcript JSONL (newest first) back to the last real user message. An assistant record with non-whitespace text (string content, or a content array with a non-whitespace text block) is a render → allow. A user record with non-whitespace text (same two shapes) marks the start of turn with no render found → block. User records that are only tool_result blocks are mid-turn tool feedback and are scanned past, as are system / summary / progress / malformed lines. Harness-injected `<task-notification>` records (a backgrounded agent or workflow coming to rest) are likewise scanned past as mid-turn feedback. The scan caps at 2000 records.

**Lazy-flush retry:** the harness writes transcript lines with a lazy flush (~100ms), so the in-flight turn's text block may not be on disk yet. Before blocking, the hook sleeps 0.4s and re-scans once; only a second no-render verdict blocks.

**Fail-open cases:** missing jq (loud — emits a `systemMessage` telling the user the guard is NOT running), missing or unreadable `transcript_path`, scan-cap overflow with no decision, garbage transcript (bad lines are skipped via `fromjson?` and never kill the stream).

**A block is NOT a user denial:** the stderr message tells the model this is an automated plugin guard — do not stop, do not treat the question as answered. Recovery: write the full gate render as an ordinary chat message, then call AskUserQuestion again with the same options.

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` `allow_patterns[]`; pattern ID `gate-render` skips the guard.

### require-evidence-on-completion.sh

**Event:** Stop `*`. **Stdin:** `.last_assistant_message` (with a `.transcript_path` fallback that reverse-scans for the last assistant record). **Block exit:** never blocks — warn-only (`exit 0` + stderr).

Scans the last assistant message for completion-claim phrases ("shipped", "all tests pass", "ready to ship", "Done!") that are not backed by an Evidence Block, and emits a stderr reminder citing `skills/_shared/evidence-standard.md`. A genuine tool-only turn (no assistant text to scan) exits silently. Stop hooks fire roughly 50-80% of the time, so this is a soft reminder layer, not enforcement — the goal is to nudge the model toward attaching evidence to completion claims, not to block.

**Fail-open cases:** missing jq, missing/unreadable transcript, or an unparseable message — all exit 0 (a convenience reminder must never wedge the session).

**Per-project allowlist:** walks up from cwd for `.geniro/safety.json` `allow_patterns[]`; pattern ID `evidence-stop` skips the warning.

### geniro-check-update.js

**Event:** SessionStart. **Block exit:** never blocks. **Timeout:** 5s.

Spawns a detached child process via `spawn(..., detached: true, stdio: 'ignore')` then `child.unref()`; the parent consumes stdin and exits immediately so session start is never blocked. The child fetches GitHub `releases/latest` (10s timeout, fallback to `raw.githubusercontent.com`) and writes the result to `~/.claude/cache/geniro-update-check.json`. The status line consumes that cache to surface "update available" indicators.

### geniro-statusline.js

**Wiring:** [`settings.json`](settings.json) `statusLine.command`. Not registered in `hooks.json` — `statusLine` is a separate Claude Code display feature, not a hook event.

**Stdin (3s timeout):** JSON containing `model.display_name`, `model.id`, `effort.level`, `workspace.current_dir`, `context_window.remaining_percentage`, `context_window.context_window_size`, `session_id`, `transcript_path`, `rate_limits.five_hour.{used_percentage,resets_at}`, `cost.total_cost_usd`. Also reads `~/.claude/cache/geniro-update-check.json` for the update banner, `~/.claude/todos/*.json` for the in-progress task, and the tail (last 256KB) of `transcript_path` for the session topic (`ai-title`) and the latest user prompt (`last-prompt`).

Renders a **two-row, width-justified** ANSI bar (uses the `COLUMNS` env var Claude Code exports, v2.1.153+):

- **Line 1:** `[model — effort · task]` left, `«session topic»` (the `ai-title`) centered, `[5h rate-limit · cost · ⬆ update]` right (update pinned rightmost).
- **Line 2:** `[dir · context bar]` left, `«latest user prompt»` (the `last-prompt`) centered.
- Model shows the full name (`display_name`, e.g. `Opus 4.8 (1M context)`; reconstructed from `model.id` when the client sends a bare family word) in a bold family colour (Opus purple / Sonnet blue / Haiku green). Reasoning effort, set off by a spaced ` — ` dash, is graded low→max (gray→orange→red). Directory is teal.
- Context %: green (<50%), yellow (50-65%), orange (65-80%), red blinking (>80%); token count rides inside the bar. 5h limit: green (<70%), yellow (<90%), red (≥90%) + reset countdown.
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

Current sourcing call sites: [`skills/refactor/SKILL.md`](skills/refactor/SKILL.md), [`skills/review/phase-2-spawns.md`](skills/review/phase-2-spawns.md), [`skills/review/phase-4-3-test-gate-reference.md`](skills/review/phase-4-3-test-gate-reference.md), [`skills/_shared/refactor-patterns.md`](skills/_shared/refactor-patterns.md).

## Testing

```bash
# Test file protection (expect exit code 2 = blocked)
echo '{"tool_input":{"file_path":"/config/.env"}}' | ./hooks/file-protection.sh
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
5. **Graceful Degradation** — hooks fail open when a dependency (e.g. `jq`) is missing: safety guards loudly (a `systemMessage` says the guard is not running), convenience reminders silently (never wedge the session). The three data-loss guards — `file-protection.sh`, `block-dangerous-git.sh`, `block-geniro-deletion.sh` — fail open only *after* a coarse raw-text scan of the payload for their highest-signal tokens; a hit there still exits 2, because on those three a false positive costs less than a clobbered credential file, a force-pushed branch, or a wiped `.geniro/`
6. **Case Insensitivity** — File patterns are case-insensitive

## Sources & References

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide)
- Exit code behavior: Exit 0 = allow, Exit 2 = block (PreToolUse only); PostToolUse / Stop / SessionStart always exit 0
- statusLine wiring: see [`settings.json`](settings.json) and [Claude Code statusLine docs](https://code.claude.com/docs/en/statusline)
