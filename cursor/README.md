# Using Geniro with Cursor

This repository is a dual-runtime plugin: `.claude-plugin/plugin.json` packages it for Claude Code, `.cursor-plugin/plugin.json` packages it for Cursor. Both share the same `skills/` directory; agents and hooks are runtime-specific:

| Component | Claude Code reads | Cursor reads |
|---|---|---|
| Skills | `skills/` (auto-discovered) | `skills/` (via the manifest's `"skills"` field) |
| Agents | `agents/` (Claude frontmatter: `tools`, `model`, `maxTurns`) | `cursor/agents/` (Cursor frontmatter: `model`, `readonly`) — generated from `agents/` by `scripts/build-cursor-agents.sh` |
| Hooks | `hooks/hooks.json` (PascalCase events, exit-2 blocks) | `cursor/hooks.json` (camelCase events) → `cursor/hooks/claude-hook-shim.sh` → the same scripts in `hooks/` |

## Install

**As a Cursor plugin (recommended)** — full experience: skills + subagents + safety hooks.

1. Symlink or copy this repository to `~/.cursor/plugins/local/geniro` (symlink keeps it on the latest checkout), or import the repo through **Dashboard → Plugins → Team Marketplaces**.
2. Restart Cursor. Skills appear in the `/` picker under their directory names (`plan`, `implement`, `review`, ...); subagents (`reviewer-agent`, `codebase-explorer-agent`, ...) become Task-tool targets.

**Via the Claude Code compatibility toggle** — skills only, no hooks or agents.

If the plugin is installed in Claude Code from the marketplace, enabling **Settings → Rules, Skills, Subagents → "Include third-party Plugins, Skills, and other configs"** lets the Cursor IDE pick the skills up from `~/.claude/plugins/cache/`. Safety hooks and subagents do not travel this route; prefer the Cursor plugin install above.

## What works in Cursor

- **The 12 runtime-portable skills.** Each carries a runtime-portability preamble that resolves the plugin root when `${CLAUDE_PLUGIN_ROOT}` is unset, so the shared helpers (`skills/_shared/`) and shell libraries (`lib/`) work unchanged. `/update` is the one exception, and `/reflect` is portable only in its `--this-session` shape — see the Claude-Code-only note below. Degradation contract: `skills/_shared/runtime-portability.md`.
- **Safety + enforcement hooks** for shell commands and file writes: destructive-git guard, `.geniro/` deletion guard, protected-file writes, security pattern scan, state-helper enforcement, TDD-order enforcement — adapted through `cursor/hooks/claude-hook-shim.sh` (a blocked action returns `{"permission":"deny"}` with the guardrail reason).
- **Session-start context restore.** The `sessionStart` hook re-injects the active task state and instruction-file list as `additional_context`.
- **The 7 subagents** for the parallel review/research fan-outs, registered under their bare names.

## What degrades or stays Claude-Code-only

- **Structured decision gates** (`AskUserQuestion`) become plain chat questions with lettered options.
- **`/reflect`'s past-session shapes and `/update`** require Claude Code (the session-transcript layout on disk / the `claude plugin` CLI) and exit with a notice elsewhere. `/reflect --this-session` runs here: it mines the running conversation and reads no transcript file. Update the Cursor install by pulling the repo (symlink) or re-importing the marketplace entry.
- **Model tiering, statusline, deep-mode `Workflow` fan-out, worktree tools, plan artifacts** — each has a documented fallback in the skills; nothing breaks.
- Hook events Cursor does not deliver to plugins in a compatible slot (`AskUserQuestion` gate-render, the Stop-event evidence reminder, the marketplace update check) are not wired; the corresponding conventions apply as instructions per `skills/_shared/runtime-portability.md`.

## Maintaining the Cursor port

- `cursor/agents/*.md` are **generated** — edit `agents/*.md`, run `scripts/build-cursor-agents.sh`, commit both. CI (`tests/cursor/build-agents-fresh.sh`) fails on drift.
- `cursor/hooks.json` wires the shim; add new hook scripts there only if their event maps cleanly (see the translation map at the top of `cursor/hooks/claude-hook-shim.sh`).
- `tests/cursor/hook-shim.sh` covers the adapter's translation and fail-open behavior.
