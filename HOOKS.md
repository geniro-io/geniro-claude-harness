# Geniro Plugin — Hooks Documentation

Production-grade hooks for the geniro plugin. All hooks follow best practices from the official Claude Code documentation and proven implementations from Citadel, Claude Forge, and claude-pipeline.

## Configuration overview

Hook configuration is **split** across two files:

| File | Purpose |
|---|---|
| [`hooks/hooks.json`](hooks/hooks.json) | Registers event-driven hooks (PreToolUse, Stop, SessionStart). Pointed to by [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) `hooks` field. |
| [`settings.json`](settings.json) (root) | Defines plugin-wide permissions and the `statusLine` command. The status line is NOT a Claude Code hook — it's a separate display feature. |

The status messages set on each `hooks.json` entry (e.g. `"Checking for destructive git operations..."`) appear as spinner text while the hook runs.

## Hook scripts

The plugin ships 9 safety / lifecycle hooks, 1 sourced utility library, and 2 Node-based feature scripts:

| Script | Event | Blocking | Description |
|---|---|---|---|
| [`file-protection.sh`](hooks/file-protection.sh) | PreToolUse `Edit\|Write` | exit 2 = block | Blocks writes to `.env`, lock files, keys, credentials (bypass: `write-env`, `write-git-internal`, `write-lockfile`, `write-cert-key`, `write-credentials`, `write-tfstate`, `write-vault`) |
| [`block-dangerous-git.sh`](hooks/block-dangerous-git.sh) | PreToolUse `Bash` | exit 2 = block | Blocks destructive git: force-push, reset --hard, branch -D, clean -fd, mass-discard checkout/restore, update-ref -d, filter-branch |
| [`block-geniro-deletion.sh`](hooks/block-geniro-deletion.sh) | PreToolUse `Bash` | exit 2 = block | Blocks bulk deletion of `.geniro/` (bypass: `rm-geniro-tree`, `rm-geniro-subdir`, `rm-geniro-state-subdir`, `find-geniro-delete`, `worktree-remove-with-state`, `git-add-force-geniro`) |
| [`enforce-tdd-order.sh`](hooks/enforce-tdd-order.sh) | PreToolUse `Edit\|Write` | exit 2 = block | Blocks edits to non-test files when `.geniro/state/tdd/state-<slug>.md` shows `phase: RED` (bypass: `tdd-order`) |
| [`enforce-state-helper.sh`](hooks/enforce-state-helper.sh) | PreToolUse `Edit\|Write` | warn-mode (block in a future release) | Warns on direct Edit/Write to canonical state paths under `.geniro/state/`, `.geniro/planning/`, `.geniro/knowledge/`, `.geniro/instructions/`, `.geniro/actions/`, `.geniro/workflow/`; suggests `atomic_state_write` / `atomic_state_append` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`. Bypass: `enforce-state-helper`. |
| [`security-pattern-check.sh`](hooks/security-pattern-check.sh) | PreToolUse `Edit\|Write` | exit 2 = block | Cheap regex scan for high-signal security anti-patterns in file content (eval/exec, pickle, yaml.load, shell=True, curl\|sh, TLS bypass, XSS sinks, weak crypto). Per-pattern bypass: `sec-eval-exec`, `sec-pickle`, `sec-yaml-unsafe`, `sec-shell-injection`, `sec-curl-pipe-sh`, `sec-tls-bypass`, `sec-xss-sink`, `sec-weak-crypto`. Scope-limited to applicable file extensions per pattern. Logic-level issues (authz bypass, IDOR, race conditions) are not regex-detectable and require `/geniro:review`. |
| [`require-evidence-on-completion.sh`](hooks/require-evidence-on-completion.sh) | Stop `*` | warn-only (always exit 0) | Scans last assistant message for completion phrases without an Evidence Block (bypass: `evidence-stop`) |
| [`session-start-restore.sh`](hooks/session-start-restore.sh) | SessionStart `matcher: "compact\|resume\|startup"` | non-blocking | Compaction-survival. Resolves the active T1 state.md across all three layouts (planning task-dir / state-per-skill / state singleton); discards a state.md already in a terminal `phase:`/`status:` so a finished task is not surfaced as resumable; pre-flights `validate_state_file`; emits an `additionalContext` block-set (per-source prefix · suggested files · validation-failure recovery · helper-missing notice · non-resumable-actions warning · `## Errors` / `## Open Questions` / persisted `approvals:` from state.md frontmatter · resume protocol). Read-only — never writes state.md. |
| [`geniro-check-update.js`](hooks/geniro-check-update.js) | SessionStart | non-blocking, detached | Background-checks GitHub for plugin updates |
| [`geniro-statusline.js`](hooks/geniro-statusline.js) | `statusLine.command` (settings.json) | non-blocking | ANSI-colored status line (model • task • dir • context%) |
| [`backpressure.sh`](hooks/backpressure.sh) | **NOT registered** — utility library | — | Sourced by skills (e.g. /refactor, /review) to compress verbose test/build output |

### file-protection.sh

**Event:** PreToolUse `Edit|Write`. **Stdin:** `jq -r '.tool_input.file_path // "" \| ascii_downcase'`. **Block exit:** `exit 2`.

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

Blocks destructive git operations by pattern ID: `force-push`, `force-push-with-lease`, `reset-hard`, `branch-delete-force`, `clean-fd`, `checkout-mass-discard`, `restore-mass-discard`, `update-ref-delete`, `filter-branch`. Pads the command with whitespace and collapses newlines so flag matchers (e.g. `[[:space:]]-f[[:space:]]`) hit reliably even at start/end of string or inside multi-line commands.

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` and reads `allow_patterns[]` to opt out of specific pattern IDs. On block, the error message tells the user the exact `safety.json` snippet to add (or how to create the file if it doesn't exist).

### session-start-restore.sh

**Event:** SessionStart `matcher: "compact|resume|startup"`. **Block exit:** never blocks. **Timeout:** 10s.

Wired as `SessionStart` with `matcher: "compact|resume|startup"` (Anthropic-canonical; `PostCompact` itself does not support `additionalContext`). `clear` is explicitly unmatched — user reset respected. Resolves the active T1 `state.md` via canonical slug match + frontmatter `branch:` fallback across all three layouts (planning task-dir / state-per-skill slug / state singleton); a state.md already in a terminal state — terminal `phase:` (`done`/`aborted`/`routed`/etc.) or terminal `status:` — is discarded so a finished task is never surfaced as resumable; pre-flights `validate_state_file` and degrades gracefully if the helper is missing.

Emits an `additionalContext` block-set:

- Per-source prefix (compact / resume / startup).
- Suggested files (L4 instructions trio routed through `load-custom-instructions.md` MODE: refresh; CLAUDE.md, `_FEATURES.md`, state.md, spec.md, plan.md as direct Reads).
- Validation-failure recovery directive (when `validate_state_file` reports a structural error).
- Helper-missing notice (when the validator binary itself is absent).
- Structured non-resumable-actions warning per state.md frontmatter (`git-push`, `pr-comment-posted`, `slack-notify-sent`, `release-tagged`, unknown-action fallback).
- Unresolved errors from state.md `## Errors`, pending `## Open Questions`, and persisted `approvals:` from state.md frontmatter.
- Resume protocol (suppressed when the resolved task is in a terminal state).

`systemMessage` one-liner emitted on every source except cold startup with no active task. Read-only — never writes state.md.

### security-pattern-check.sh

**Event:** PreToolUse `Edit|Write`. **Stdin:** `jq -r '.tool_input.file_path // ""'` and `jq -r '.tool_input.content // .tool_input.new_string // ""'`. **Block exit:** `exit 2`.

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

**Event:** PreToolUse `Edit|Write`. **Block exit:** warn-mode initially; flips to exit-2 hard-block in a future release.

Detects direct `Edit` / `Write` calls against canonical state paths and suggests routing through `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` (`atomic_state_write` for plain files, `atomic_state_append` for JSONL). Protected prefixes: `.geniro/state/`, `.geniro/planning/`, `.geniro/knowledge/`, `.geniro/instructions/`, `.geniro/actions/`, `.geniro/workflow/`.

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` `allow_patterns[]`; pattern ID `enforce-state-helper` skips the warning (and the future hard-block).

### geniro-check-update.js

**Event:** SessionStart. **Block exit:** never blocks. **Timeout:** 5s.

Spawns a detached child process via `spawn(..., detached: true, stdio: 'ignore')` then `child.unref()`; the parent consumes stdin and exits immediately so session start is never blocked. The child fetches GitHub `releases/latest` (10s timeout, fallback to `raw.githubusercontent.com`) and writes the result to `~/.claude/cache/geniro-update-check.json`. The status line consumes that cache to surface "update available" indicators.

### geniro-statusline.js

**Wiring:** [`settings.json`](settings.json) `statusLine.command`. Not registered in `hooks.json` — `statusLine` is a separate Claude Code display feature, not a hook event.

**Stdin (3s timeout):** JSON containing `model.display_name`, `workspace.current_dir`, `context_window.remaining_percentage`, `context_window.context_window_size`, `session_id`. Reads `~/.claude/cache/geniro-update-check.json` for the update banner and `~/.claude/todos/*.json` for the in-progress task. Renders an ANSI-colored bar:

- Context %: green (<50%), yellow (50-65%), orange (65-80%), red blinking (>80%)
- Format: `model | task | dir | context%`

Always exits 0; falls back to the literal string `geniro` if JSON parse fails.

### backpressure.sh

**Event:** none — this is a utility library, not a hook. Intentionally NOT in `hooks.json`.

Skills source this file (or invoke it directly) to wrap verbose test/build/lint commands and surface only failures. Pattern:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" "Tests" "npm test"
# or
source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Tests" "npm test"
```

On success: emits `✓ Tests passed (N lines suppressed)` (~5 tokens). On failure: filters and caps output at 150 lines. Manages its own `mktemp` lifecycle; no persistence.

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
