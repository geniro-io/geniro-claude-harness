# Geniro Plugin — Hooks Documentation

Production-grade hooks for the geniro plugin. All hooks follow best practices from the official Claude Code documentation and proven implementations from Citadel, Claude Forge, and claude-pipeline.

## Configuration overview

Hook configuration is **split** across two files:

| File | Purpose |
|---|---|
| [`hooks/hooks.json`](hooks/hooks.json) | Registers event-driven hooks (PreToolUse, PostToolUse, PostCompact, SessionStart). Pointed to by [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) `hooks` field. |
| [`settings.json`](settings.json) (root) | Defines plugin-wide permissions and the `statusLine` command. The status line is NOT a Claude Code hook — it's a separate display feature. |

The status messages set on each `hooks.json` entry (e.g. `"Checking for unsafe database operations..."`) appear as spinner text while the hook runs.

## Hook scripts

The plugin ships 6 safety hooks, 1 sourced utility library, and 2 Node-based feature scripts:

| Script | Event | Blocking | Description |
|---|---|---|---|
| [`file-protection.sh`](hooks/file-protection.sh) | PreToolUse `Edit\|Write` | exit 2 = block | Blocks writes to `.env`, lock files, keys, credentials |
| [`db-guard.sh`](hooks/db-guard.sh) | PreToolUse `Bash` | exit 2 = block | Blocks unsafe DB operations (DROP, TRUNCATE, unfiltered DELETE) |
| [`secret-protection-input.sh`](hooks/secret-protection-input.sh) | PreToolUse `Bash` | exit 2 = block | Blocks shell commands that read sensitive files |
| [`block-dangerous-git.sh`](hooks/block-dangerous-git.sh) | PreToolUse `Bash` | exit 2 = block | Blocks destructive git: force-push, reset --hard, branch -D, clean -fd, mass-discard checkout/restore, update-ref -d, filter-branch |
| [`secret-protection-output.sh`](hooks/secret-protection-output.sh) | PostToolUse `*` | warn-only (always exit 0) | Scans tool outputs for leaked secrets |
| [`post-compact-notification.sh`](hooks/post-compact-notification.sh) | PostCompact `*` | non-blocking | Outputs resume instructions and re-read suggestions for the active pipeline state |
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

### db-guard.sh

**Event:** PreToolUse `Bash`. **Stdin:** `jq -r '.tool_input.command // ""'`. **Block exit:** `exit 2`.

Blocks: `DROP TABLE/DATABASE/INDEX/VIEW/SCHEMA`, `TRUNCATE`, unfiltered `DELETE` (no `WHERE`), tautology `DELETE WHERE 1=1`. Allows commands that don't match these patterns. Stderr-only warning on block.

### secret-protection-input.sh

**Event:** PreToolUse `Bash`. **Stdin:** `jq -r '.tool_input.command // ""'`. **Block exit:** `exit 2`.

Blocks shell commands attempting to read: `.env`, `.pem`, `credentials`, API keys, SSH keys, AWS config, Kubernetes config, OAuth tokens, password files, openssl key inspection. Includes `cat`, `source`, redirection patterns.

### block-dangerous-git.sh

**Event:** PreToolUse `Bash`. **Stdin:** `jq -r '.tool_input.command // ""'`. **Block exit:** `exit 2`.

Blocks destructive git operations by pattern ID: `force-push`, `force-push-with-lease`, `reset-hard`, `branch-delete-force`, `clean-fd`, `checkout-mass-discard`, `restore-mass-discard`, `update-ref-delete`, `filter-branch`. Pads the command with whitespace and collapses newlines so flag matchers (e.g. `[[:space:]]-f[[:space:]]`) hit reliably even at start/end of string or inside multi-line commands.

**Per-project allowlist:** walks up from cwd looking for `.geniro/safety.json` and reads `allow_patterns[]` to opt out of specific pattern IDs. On block, the error message tells the user the exact `safety.json` snippet to add (or how to create the file if it doesn't exist).

### secret-protection-output.sh

**Event:** PostToolUse `*`. **Stdin:** `jq -r '.tool_output // ""'`. **Block exit:** never blocks (PostToolUse always exits 0).

Scans tool outputs for leaked secrets: `API_KEY`, bearer tokens, passwords, AWS secrets, GitHub/GitLab tokens, Slack webhooks, Stripe keys, OAuth tokens, PGP/SSH private keys, `BEGIN PRIVATE KEY` blocks, JWT-shaped strings. On detection, outputs a JSON `additionalContext` warning. Gracefully exits 0 if `jq` is unavailable.

### post-compact-notification.sh

**Event:** PostCompact `*`. **Block exit:** never blocks. **Timeout:** 10s.

Globs `.geniro/planning/*/state.md` (most-recently-modified) to detect an active pipeline; outputs `additionalContext` containing resume instructions, suggested re-reads (SKILL.md, state.md, spec files), and feature-anchor reminders. Gracefully handles missing state.

### geniro-check-update.js

**Event:** SessionStart. **Block exit:** never blocks. **Timeout:** 5s.

Spawns a detached child process via `spawn(..., detached: true, stdio: 'ignore')` then `child.unref()`; the parent consumes stdin and exits immediately so session start is never blocked. The child fetches GitHub `releases/latest` (10s timeout, fallback to `raw.githubusercontent.com`) and writes the result to `~/.claude/cache/geniro-update-check.json`. The status line consumes that cache to surface "update available" indicators.

### geniro-statusline.js

**Wiring:** [`settings.json`](settings.json) `statusLine.command`. Not registered in `hooks.json` — `statusLine` is a separate Claude Code display feature, not a hook event.

**Stdin (3s timeout):** JSON containing `model.display_name`, `workspace.current_dir`, `context_window.remaining_percentage`, `context_window.size`, `session_id`. Reads `~/.claude/cache/geniro-update-check.json` for the update banner and `~/.claude/todos/*.json` for the in-progress task. Renders an ANSI-colored bar:

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

Current sourcing call sites: [`skills/refactor/SKILL.md`](skills/refactor/SKILL.md), [`skills/review/SKILL.md`](skills/review/SKILL.md), [`skills/implement/implement-reference.md`](skills/implement/implement-reference.md), [`agents/refactor-agent.md`](agents/refactor-agent.md).

## Testing

```bash
# Test file protection (expect exit code 2 = blocked)
echo '{"tool_input":{"file_path":"/config/.env"}}' | ./hooks/file-protection.sh
echo "exit=$?"

# Test db-guard
echo '{"tool_input":{"command":"DROP TABLE users"}}' | ./hooks/db-guard.sh
echo "exit=$?"

# Test secret-protection-input
echo '{"tool_input":{"command":"cat ~/.aws/credentials"}}' | ./hooks/secret-protection-input.sh
echo "exit=$?"
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
- Exit code behavior: Exit 0 = allow, Exit 2 = block (PreToolUse only); PostToolUse / PostCompact / SessionStart always exit 0
- statusLine wiring: see [`settings.json`](settings.json) and [Claude Code statusLine docs](https://code.claude.com/docs/en/statusline)
