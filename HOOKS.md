# Geniro Plugin — Hooks Documentation

Production-grade hooks for the geniro plugin. All hooks follow best practices from the official Claude Code documentation and proven implementations from Citadel, Claude Forge, and claude-pipeline.

## Configuration overview

Hook configuration is **split** across two files:

| File | Purpose |
|---|---|
| [`hooks/hooks.json`](hooks/hooks.json) | Registers event-driven hooks (PreToolUse, Stop, SessionStart). Pointed to by [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) `hooks` field. |
| [`settings.json`](settings.json) (root) | Defines the `statusLine` command. The status line is NOT a Claude Code hook — it's a separate display feature. Plugin-shipped `settings.json` cannot grant permissions (Claude Code ignores a `permissions` block here) — permission rules belong in the consumer's own user/project settings. |

The status messages set on each `hooks.json` entry (e.g. `"Checking for destructive git operations..."`) appear as spinner text while the hook runs.

## Hook scripts

The plugin ships 9 safety / lifecycle hooks, 1 sourced utility library, and 2 Node-based feature scripts:

| Script | Event | Blocking | Description |
|---|---|---|---|
| [`file-protection.sh`](hooks/file-protection.sh) | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` AND `Bash` | exit 2 = block | Blocks writes to `.env`, lock files, keys, credentials. The Bash branch catches shell-side writes into the same protected paths — redirection (`>`, `>>`, `>\|`), `tee`, in-place `sed -i`, `cp`/`mv` destinations, `dd of=` (reads stay allowed). Bypass: `write-env`, `write-git-internal`, `write-lockfile`, `write-cert-key`, `write-credentials`, `write-tfstate`, `write-vault` |
| [`block-dangerous-git.sh`](hooks/block-dangerous-git.sh) | PreToolUse `Bash` | exit 2 = block | Blocks destructive git: force-push, reset --hard, branch -D, clean -fd, mass-discard checkout/restore, update-ref -d, filter-branch, remote-branch deletion (`git push --delete` / colon-refspec) |
| [`block-geniro-deletion.sh`](hooks/block-geniro-deletion.sh) | PreToolUse `Bash` | exit 2 = block | Blocks bulk deletion of `.geniro/` (bypass: `rm-geniro-tree`, `rm-geniro-subdir`, `rm-geniro-state-subdir`, `find-geniro-delete`, `worktree-remove-with-state`, `git-add-force-geniro`) |
| [`enforce-tdd-order.sh`](hooks/enforce-tdd-order.sh) | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` | exit 2 = block | Blocks edits to non-test files when `.geniro/state/tdd/state-<slug>.md` shows `phase: RED` (bypass: `tdd-order`) |
| [`enforce-state-helper.sh`](hooks/enforce-state-helper.sh) | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` AND `Bash` | exit 2 = block | Blocks direct writes to canonical state paths under `.geniro/state/`, `.geniro/planning/`, `.geniro/knowledge/`, `.geniro/instructions/`, `.geniro/actions/`, `.geniro/workflow/`. The Bash branch catches shell-side writes into the same paths — redirection (`>`, `>>`, `>\|`), `tee`, in-place `sed -i`, `cp`/`mv` destinations, `dd of=` (reads stay allowed); commands invoking `atomic_state_write` / `atomic_state_append` pass. Suggests the helpers per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`. Bypass: `enforce-state-helper`. |
| [`enforce-gate-render.sh`](hooks/enforce-gate-render.sh) | PreToolUse `AskUserQuestion` | exit 2 = block | Blocks a gate question fired with no visible assistant message in the current turn — the user would be answering blind — on either of two triggers: it references content "above", OR it carries finding-gate evidence shorthand (a PRODUCT-DECISION tag, convergence wording, or a finding-ID like `F5`/`M1b` with finding-gate co-text). Reverse-scans the transcript to the last real user message (2000-record cap, one 0.4s retry against the transcript lazy-flush race); fails open on missing jq (loud), missing transcript, cap overflow, or garbage transcript. A block is NOT a user denial — stderr instructs render-then-re-ask (bypass: `gate-render`) |
| [`security-pattern-check.sh`](hooks/security-pattern-check.sh) | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` | exit 2 = block | Cheap regex scan for high-signal security anti-patterns in file content (eval/exec, pickle, yaml.load, shell=True, curl\|sh, TLS bypass, XSS sinks, weak crypto). Per-pattern bypass: `sec-eval-exec`, `sec-pickle`, `sec-yaml-unsafe`, `sec-shell-injection`, `sec-curl-pipe-sh`, `sec-tls-bypass`, `sec-xss-sink`, `sec-weak-crypto`. Scope-limited to applicable file extensions per pattern. Logic-level issues (authz bypass, IDOR, race conditions) are not regex-detectable and require `/geniro:review`. |
| [`require-evidence-on-completion.sh`](hooks/require-evidence-on-completion.sh) | Stop `*` | warn-only (always exit 0) | Scans last assistant message for completion phrases without an Evidence Block (bypass: `evidence-stop`) |
| [`session-start-restore.sh`](hooks/session-start-restore.sh) | SessionStart `matcher: "compact\|resume\|startup"` | non-blocking | Compaction-survival. Resolves the active T1 state.md across all three layouts (planning task-dir / state-per-skill / state singleton); skips state.md candidates already in a terminal `phase:`/`status:` during resolution, so a finished task is never surfaced as resumable AND cannot shadow an in-flight task on the same branch in a later resolution tier; pre-flights `validate_state_file`; emits an `additionalContext` block-set (per-source prefix · suggested files · validation-failure recovery · helper-missing notice · non-resumable-actions warning · `## Errors` / `## Open Questions` / persisted `approvals:` from state.md frontmatter · resume protocol). Also runs L2 auto-archive. Read-only on state.md; the only writes are `learnings.jsonl` (auto-archive flip) + `.archive-stale.{hash,lock}`. |
| [`geniro-check-update.js`](hooks/geniro-check-update.js) | SessionStart | non-blocking, detached | Background-checks GitHub for plugin updates |
| [`geniro-statusline.js`](hooks/geniro-statusline.js) | `statusLine.command` (settings.json) | non-blocking | Two-row width-justified status line (model — effort · task · topic · 5h limit · cost · update / dir · context · last prompt) |
| [`backpressure.sh`](hooks/backpressure.sh) | **NOT registered** — utility library | — | Sourced by skills (e.g. /refactor, /review) to compress verbose test/build output |

### file-protection.sh

**Event:** PreToolUse `Edit|Write|MultiEdit|NotebookEdit` AND `Bash` (registered under both matchers in `hooks.json`; the script branches on `tool_name`). **Stdin:** `.tool_input.file_path` (or `.tool_input.notebook_path` for NotebookEdit) for the file tools; `.tool_input.command` for Bash. **Block exit:** `exit 2`.

**Bash branch:** extracts write targets the file-tool matcher never sees — redirection targets (`>`, `>>`, `>|`), `tee` arguments, file arguments of an in-place `sed -i` span (the sed SCRIPT token is skipped — it is code, not a path), `cp`/`mv` destinations (the last non-flag token — copying FROM a protected file is a read and stays allowed), and `dd of=` targets — then runs the same pattern set against each. Heredoc bodies and quoted string literals are scrubbed first (they are data, so `echo "see > .env"` and a doc heredoc mentioning `> .env` stay allowed); the trade-off is that a deliberately QUOTED redirect target (`> ".env"`) is a documented miss. fd-dups (`>&2`) and `/dev/null` never match.

**Protects:**
- `.env` and `.env.*` (e.g. `.env.local`, `.env.production`)
- `.git/*` — Git internal files
- `pnpm-lock.yaml`, `package-lock.json`, `yarn.lock` — lock files
- `*.pem` — PEM certificates / private keys
- `*.key` — private key files
- `credentials.*`, `secrets.*` — credential files
- `*.tfstate` — Terraform state
- `.vault` — Vault files

Implementation: case-insensitive pattern match via lowercase conversion; exit 2 to block (fail-safe).

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` and reads `allow_patterns[]` to opt out of specific pattern IDs. On block, the error message names the pattern ID and tells the user the exact `safety.json` snippet to add (or how to create the file if it doesn't exist). Pattern IDs: `write-env`, `write-git-internal`, `write-lockfile`, `write-cert-key`, `write-credentials`, `write-tfstate`, `write-vault`.

### block-dangerous-git.sh

**Event:** PreToolUse `Bash`. **Stdin:** `jq -r '.tool_input.command // ""'`. **Block exit:** `exit 2`.

Blocks destructive git operations by pattern ID: `force-push`, `force-push-with-lease`, `reset-hard`, `branch-delete-force`, `clean-fd`, `checkout-mass-discard`, `restore-mass-discard`, `update-ref-delete`, `filter-branch`, `push-delete`. The `push-delete` pattern blocks remote-branch deletion — both `git push <remote> --delete <branch>` and the colon delete-refspec form `git push origin :branch` — which the local `branch-delete-force` matcher never saw. Pads the command with whitespace, joins backslash-newline continuations, and collapses newlines so flag matchers (e.g. `[[:space:]]-f[[:space:]]`) hit reliably even at start/end of string or inside multi-line commands. Git GLOBAL options (`git -C <path> push`, `git -c k=v push`, `--git-dir`/`--work-tree`, pager flags) are stripped before matching, so they cannot break the `git <subcommand>` adjacency the matchers rely on. Checkout/restore matchers block a standalone `.` / `./` / `*` pathspec with or without `--` (`git checkout .`, `git checkout HEAD -- .`); `git clean` dry-run spans (`-n`/`--dry-run`) are previews and stay allowed, evaluated per-span so a dry span cannot mask a destructive sibling in the same command.

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` and reads `allow_patterns[]` to opt out of specific pattern IDs. On block, the error message tells the user the exact `safety.json` snippet to add (or how to create the file if it doesn't exist).

### block-geniro-deletion.sh

**Event:** PreToolUse `Bash`. **Stdin:** `jq -r '.tool_input.command // ""'`. **Block exit:** `exit 2`.

Prevents bulk deletion of `.geniro/`, which holds user-authored persistent state (instructions, actions, workflow, `_FEATURES.md`, learnings, planning artifacts). A single accidental `rm -rf .geniro/` destroys all of it. Joins backslash-newline continuations, pads, and collapses newlines (mirrors `block-dangerous-git.sh`); strips git GLOBAL options so `git -C <path> worktree remove` and `git -C <path> add -f .geniro/...` cannot evade the matchers; and blanks quoted-string literals that merely MENTION `rm` (e.g. `echo "do not rm -rf .geniro/"`) so a doc reference is not mistaken for a real delete.

**Allowed by design (NOT blocked):** `rm -f <single-file>` at any depth (required by skills' state cleanup), and `rm -rf .geniro/<top>/<sub>/` with 3+ path segments (task-dir / slug-scoped trees), plus single-file deletes under `.geniro/state/` (`.geniro/state/<file>.<ext>`) and 4+ segment slug-scoped state files.

**Blocked by default** (each evaluated per-rm-span and per-arg so a deep arg cannot mask a shallow sibling):

- `rm-geniro-tree` — whole-tree `rm -rf .geniro/`, including absolute / `$PWD/` / `../`-prefixed spellings, prefix globs (`.gen*`, `.geniro*`), trailing globs (`.geniro/*`), and doubled-slash forms.
- `rm-geniro-subdir` — `rm -rf .geniro/<single-segment>/` (e.g. `.geniro/instructions/`), including `..`-escape forms.
- `rm-geniro-state-subdir` — `rm -rf .geniro/state/<skill>/` directory wipes (parallel-branch slug files still in flight).
- `find-geniro-delete` — `find … .geniro … -delete`, `-exec rm`, and `| xargs rm` bulk-walk spellings.
- `worktree-remove-with-state` — `git worktree remove` (worktrees often hold un-routed `.geniro/` state).
- `git-add-force-geniro` — `git add -f` / `--force` on `.geniro/` paths (force-adding ignored files surfaces them in the IDE Source Control panel, where a single "Discard All Changes" click becomes a one-click data-loss vector; track `.geniro/` subdirs via `.gitignore` negation instead).

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` and reads `allow_patterns[]`. On block, the error message names the pattern ID and the exact `safety.json` snippet to add. Fails open loudly (emits a `systemMessage`) if jq is missing.

### enforce-tdd-order.sh

**Event:** PreToolUse `Edit|Write|MultiEdit|NotebookEdit`. **Stdin:** `jq -r '.tool_input.file_path // .tool_input.notebook_path // ""'`. **Block exit:** `exit 2`.

Enforces the test-first cycle: when `.geniro/state/tdd/state-<slug>.md` shows `phase: RED`, an `Edit`/`Write` against a production-code file is blocked — author the failing test before the production code. Test files stay editable (that is the file you are supposed to be writing in RED). If the state file is absent, the skill has not opted in to TDD, so the hook exits 0 — no surprise blocks.

The branch slug is derived per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` §Slug rules, single-sourced in `lib/branch-slug.sh` with an inline fallback so the hook still works on a vendored install without `lib/`. The state lookup resolves the nearest project root (the directory holding `.geniro/`) walking up from cwd; TDD state is task-local, so a linked worktree keeps its OWN `.geniro/state/tdd/` and the lookup deliberately does NOT redirect to the primary worktree. Test-file detection matches `__tests__/`, `tests/` / `test/` directories, `*.spec.*`, `*_test.go`, and anchored filename conventions (`test_*`, `*-test.*`, `*.test.*`) — production files that merely contain the substring "test" (`contestant.ts`, `testimonials.tsx`) are not mistaken for tests.

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` `allow_patterns[]`; pattern ID `tdd-order` skips the block. Fails open loudly (emits a `systemMessage`) if jq is missing.

### session-start-restore.sh

**Event:** SessionStart `matcher: "compact|resume|startup"`. **Block exit:** never blocks. **Timeout:** 10s.

Wired as `SessionStart` with `matcher: "compact|resume|startup"` (Anthropic-canonical; `PostCompact` itself does not support `additionalContext`). `clear` is explicitly unmatched — user reset respected. Resolves the active T1 `state.md` via canonical slug match + frontmatter `branch:` fallback across all three layouts (planning task-dir / state-per-skill slug / state singleton). Candidates already in a terminal state — terminal `phase:` (`done`/`aborted`/`routed`/etc.) or terminal `status:` — are SKIPPED during resolution, so a finished task is never surfaced as resumable and cannot shadow an in-flight task on the same branch in a later tier (e.g. a done /plan task-dir next to a live /debug slug dir); a defense-in-depth gate re-checks the final pick. Pre-flights `validate_state_file` and degrades gracefully if the helper is missing.

Emits an `additionalContext` block-set:

- Per-source prefix (compact / resume / startup).
- Suggested files (L4 instructions trio routed through `load-custom-instructions.md` MODE: refresh; CLAUDE.md, `_FEATURES.md`, state.md, spec.md, plan.md as direct Reads).
- Validation-failure recovery directive (when `validate_state_file` reports a structural error).
- Helper-missing notice (when the validator binary itself is absent).
- Structured non-resumable-actions warning per state.md frontmatter (`git-push`, `pr-comment-posted`, `slack-notify-sent`, `release-tagged`, unknown-action fallback).
- Unresolved errors from state.md `## Errors`, pending `## Open Questions`, and persisted `approvals:` from state.md frontmatter.
- Resume protocol (suppressed when the resolved task is in a terminal state).
- Auto-archive of stale L2 entries (default ON, hash-gated + mkdir-locked for multi-tab safety; opt-out via `safety.json` `memory.auto_archive_stale: false`); when entries are flipped the `systemMessage` gains an "auto-archived: N" suffix.

`systemMessage` one-liner emitted on every source except cold startup with no active task. Read-only on state.md — never writes it; the only writes are `.geniro/knowledge/learnings.jsonl` (the auto-archive flip) and `.geniro/knowledge/.archive-stale.{hash,lock}` (the hash-gate + multi-tab lock).

### security-pattern-check.sh

**Event:** PreToolUse `Edit|Write|MultiEdit|NotebookEdit`. **Stdin:** `jq -r '.tool_input.file_path // ""'` and `jq -r '.tool_input.content // .tool_input.new_string // ""'`. **Block exit:** `exit 2`.

Cheap regex scan for high-signal, low-false-positive security anti-patterns in the content about to land in the file. Catches the obvious string-level wins at edit time without the LLM-cost of an ambient Stop-hook review.

Each pattern is scoped to applicable file extensions — Python's `pickle.loads` won't fire on `.js` files, JavaScript's `innerHTML=` won't fire on `.py` files. On match the hook prints to stderr (pattern ID, file, matched line, two remediation paths — inline justification + retry, OR per-project bypass) and exits 2.

**Pattern IDs** (each individually bypassable):

| ID | Triggers on | Applicable extensions |
|---|---|---|
| `sec-eval-exec` | `eval(`, `exec(`, `new Function(` | `.py`, `.js`, `.ts`, `.jsx`, `.tsx`, `.mjs`, `.cjs` |
| `sec-pickle` | `pickle.load(s)` | `.py` |
| `sec-yaml-unsafe` | `yaml.load(` (use `yaml.safe_load`) | `.py` |
| `sec-shell-injection` | `subprocess shell=True`, `os.system`, `os.popen` | `.py` |
| `sec-curl-pipe-sh` | `curl … \| sh`, `wget … \| bash` | `.sh`, `.bash`, `.zsh`, Dockerfile |
| `sec-tls-bypass` | `verify=False`, `rejectUnauthorized: false`, `--insecure`, `--no-check-certificate` | `.py`, `.js`/`.ts`, shell |
| `sec-xss-sink` | `.innerHTML=`, `dangerouslySetInnerHTML`, `document.write(` | `.js`, `.jsx`, `.ts`, `.tsx`, `.html`, `.vue`, `.svelte` |
| `sec-weak-crypto` | `createHash('md5'\|'sha1')`, `hashlib.md5/sha1` | `.py`, `.js`/`.ts` |

**Per-project bypass:** walks up from cwd looking for `.geniro/safety.json` and reads `allow_patterns[]`. Adding any pattern ID disables that pattern entire project-wide:

```json
{"allow_patterns": ["sec-eval-exec", "sec-xss-sink"]}
```

**What this hook does NOT catch:** logic-level vulnerabilities (authorization bypass, IDOR, race conditions, mass assignment, JWT `alg: none`, business-logic flaws). Regex cannot see semantics. Run `/geniro:review` for the LLM-driven review that catches those.

### enforce-state-helper.sh

**Event:** PreToolUse `Edit|Write|MultiEdit|NotebookEdit` AND `Bash` (registered under both matchers in `hooks.json`; the script branches on `tool_name`). **Block exit:** `exit 2`.

Blocks direct `Edit` / `Write` / `MultiEdit` calls against canonical state paths and suggests routing through `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` (`atomic_state_write` for plain files, `atomic_state_append` for JSONL) — direct calls truncate-and-rewrite, so a reader during the window sees a partial file. Protected prefixes: `.geniro/state/`, `.geniro/planning/`, `.geniro/knowledge/`, `.geniro/instructions/`, `.geniro/actions/`, `.geniro/workflow/` (plus `.geniro/.geniro-state.json`).

**Bash branch:** extracts write targets the file-tool matcher never sees — redirection targets (`>`, `>>`, `>|`), `tee` arguments, file arguments of an in-place `sed -i` span, `cp`/`mv` destinations (a `cp`/`mv` whose SOURCE is already under `.geniro/` is a housekeeping rename/copy of helper-written content and stays allowed), and `dd of=` targets — then runs the same path check against each (reads stay allowed). Heredoc bodies and quoted string literals are scrubbed first (they are data, not writes). Commands invoking the sanctioned helpers (`atomic_state_write` / `atomic_state_append`) pass — they write via their own mktemp + mv.

**Exemptions:** `.geniro/state/tdd/` (the TDD-order hook's state file is a documented exception written via its own mktemp + mv procedure, per `skills/_shared/tdd-cycle.md` §State file contract), coordination locks (`*.lock`), the fingerprint JSON, atomic-write temp files, editor swap/backup files, and deterministically-transient T1 subagent outputs (`.kr-out.md` and siblings, `.research-<facet>.md`, `notes.md`, `playwright-verify.png`). A write under `.geniro/state/` that matches no canonical layout (`state/<skill>/<slug>/state.md`, the `state/setup/state.md` singleton, `state/handoff/from-<producer>-<branch>.md`, `state/tdd/state-<slug>.md`) gets an extra hint — ad-hoc files there are invisible to the validator and session-restore.

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` `allow_patterns[]`; pattern ID `enforce-state-helper` skips the block. Fails open loudly (emits a `systemMessage`) if jq is missing.

### enforce-gate-render.sh

**Event:** PreToolUse `AskUserQuestion`. **Stdin:** `.tool_input.questions[]` (question text, option labels, option descriptions) and `.transcript_path`. **Block exit:** `exit 2`.

Mechanical backstop for the message-first gate contract (`skills/_shared/gate-rendering.md`): a decision question that points at content "above" must be preceded by a visible assistant message in the current turn, or the user is answering blind. Prompt-level render guards leak under drift; this hook enforces the contract at the tool boundary.

**Trigger (two branches; either, combined with no visible assistant text in the current turn):**

- **(a) "above"-reference** — the standalone word "above", case-insensitive and word-bounded so "abovementioned" does not match, anywhere across every question's text, option labels, and option descriptions. Templated gate questions ("Full explanation above." / "Approve the spec summarized above?") hit this branch.
- **(b) finding-gate evidence shorthand without "above"** — a real `/review` open-decision gate can fire with finding IDs and convergence wording but no "above", which the (a)-only guard let slip (the recorded evasion: "strip the 'above' reference"). A `PRODUCT-DECISION` tag or convergence wording (`converge` / `converged` / `convergence`) fires on its own. A finding-ID token (case-sensitive uppercase F/M + digits + optional trailing lowercase letter, e.g. `F5` / `M1b`) fires only with finding-gate co-text — a severity word right after an open paren (`(MEDIUM, security)`), or the words finding / findings / reviewer / severity — because the bare token alone collides with load-balancer models, function keys, and version tags.

**Turn detection:** reverse-scans the transcript JSONL (newest first) back to the last real user message. An assistant record with non-whitespace text (string content, or a content array with a non-whitespace text block) is a render → allow. A user record with non-whitespace text (same two shapes) marks the start of turn with no render found → block. User records that are only tool_result blocks are mid-turn tool feedback and are scanned past, as are system / summary / progress / malformed lines. The scan caps at 2000 records.

**Lazy-flush retry:** the harness writes transcript lines with a lazy flush (~100ms), so the in-flight turn's text block may not be on disk yet. Before blocking, the hook sleeps 0.4s and re-scans once; only a second no-render verdict blocks.

**Fail-open cases:** missing jq (loud — emits a `systemMessage` telling the user the guard is NOT running), missing or unreadable `transcript_path`, scan-cap overflow with no decision, garbage transcript (bad lines are skipped via `fromjson?` and never kill the stream).

**A block is NOT a user denial:** the stderr message tells the model this is an automated plugin guard — do not stop, do not treat the question as answered. Recovery: write the full gate render as an ordinary chat message, then call AskUserQuestion again with the same options.

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` `allow_patterns[]`; pattern ID `gate-render` skips the guard.

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

Current sourcing call sites: [`skills/refactor/SKILL.md`](skills/refactor/SKILL.md), [`skills/review/SKILL.md`](skills/review/SKILL.md), [`skills/review/phase-4-3-test-gate-reference.md`](skills/review/phase-4-3-test-gate-reference.md), [`skills/_shared/refactor-patterns.md`](skills/_shared/refactor-patterns.md).

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
5. **Graceful Degradation** — Auto-format fails safely if no formatter found
6. **Case Insensitivity** — File patterns are case-insensitive

## Sources & References

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide)
- Exit code behavior: Exit 0 = allow, Exit 2 = block (PreToolUse only); PostToolUse / Stop / SessionStart always exit 0
- statusLine wiring: see [`settings.json`](settings.json) and [Claude Code statusLine docs](https://code.claude.com/docs/en/statusline)
