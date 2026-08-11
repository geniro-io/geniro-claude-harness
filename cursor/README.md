# Using Geniro with Cursor

This repository is a dual-runtime plugin: `.claude-plugin/plugin.json` packages it for Claude Code, `.cursor-plugin/plugin.json` packages it for Cursor. Skills, agents, and hooks are each runtime-specific ports generated from one canonical source:

| Component | Claude Code reads | Cursor reads |
|---|---|---|
| Skills | `skills/` (auto-discovered, namespaced `/geniro:<slug>`) | `cursor/skills/geniro-<slug>/` (via the manifest's `"skills"` field) — generated from `skills/<slug>/SKILL.md` by `scripts/build-cursor-skills.sh` |
| Agents | `agents/` (Claude frontmatter: `tools`, `model`, `maxTurns`) | `cursor/agents/` (Cursor frontmatter: `model`, `readonly`) — generated from `agents/` by `scripts/build-cursor-agents.sh` |
| Hooks | `hooks/hooks.json` (PascalCase events, exit-2 blocks) | `cursor/hooks.json` (camelCase events) → `cursor/hooks/claude-hook-shim.sh` → the same scripts in `hooks/` |

`cursor/skills/geniro-<slug>/SKILL.md` carries only the frontmatter (`name:` rewritten to match its directory) and the body — sibling phase/reference files stay in `skills/<slug>/` and are not duplicated. Every intra-skill reference in a skill body already resolves through the fully-qualified `${CLAUDE_PLUGIN_ROOT}/skills/<slug>/...` form, and `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin root regardless of which copy of `SKILL.md` is doing the reading, so those reads land on `skills/<slug>/` either way.

## Install

**As a Cursor plugin (recommended)** — full experience: skills + subagents + safety hooks.

1. Symlink or copy this repository to `~/.cursor/plugins/local/geniro` (symlink keeps it on the latest checkout), or import the repo through **Dashboard → Plugins → Team Marketplaces**.
2. Restart Cursor. Skills appear in the `/` picker as `geniro-<slug>` (`/geniro-plan`, `/geniro-implement`, `/geniro-review`, ...) — see What degrades below for why every skill carries the prefix, not only the ones that collided; subagents (`reviewer-agent`, `codebase-explorer-agent`, ...) become Task-tool targets under their bare names.

**Via the Claude Code compatibility toggle** — skills only, no hooks or agents.

If the plugin is installed in Claude Code from the marketplace, enabling **Settings → Rules, Skills, Subagents → "Include third-party Plugins, Skills, and other configs"** lets the Cursor IDE pick the skills up from `~/.claude/plugins/cache/`. Safety hooks and subagents do not travel this route; prefer the Cursor plugin install above.

## What works in Cursor

- **The 13 runtime-portable skills**, each surfaced as `/geniro-<slug>`. Each carries a runtime-portability preamble that resolves the plugin root when `${CLAUDE_PLUGIN_ROOT}` is unset, so the shared helpers (`skills/_shared/`) and shell libraries (`lib/`) work unchanged. `/geniro-update` is the one exception, and `/geniro-reflect` is portable only in its `--this-session` shape — see the Claude-Code-only note below. Degradation contract: `skills/_shared/runtime-portability.md`.
- **Safety + enforcement hooks** for shell commands and file writes: destructive-git guard, `.geniro/` deletion guard, protected-file writes, security pattern scan, state-helper enforcement, TDD-order enforcement — adapted through `cursor/hooks/claude-hook-shim.sh` (a blocked action returns `{"permission":"deny"}` with the guardrail reason).
- **Session-start context restore.** The `sessionStart` hook re-injects the active task state and instruction-file list as `additional_context`.
- **The subagents in `cursor/agents/`** for the parallel review/research fan-outs, registered under their bare names.

## What degrades or stays Claude-Code-only

- **Structured decision gates** (`AskUserQuestion`) become plain chat questions with lettered options.
- **Per-tool write restrictions** (`tools:` in Claude agent frontmatter, the field that genuinely withholds a tool) have no Cursor equivalent — Cursor's subagent frontmatter exposes no `tools` field and subagents inherit every tool from the parent regardless of that list. The generated `cursor/agents/*.md` set the coarser `readonly: true` flag instead (no file edits, no state-changing shell commands) for every read-only agent; a Reporter skill's finer no-`Edit`/no-`Write` contract is prose the model holds itself under Cursor — see `skills/_shared/reporter-boundary.md` §1.
- **Skill names are unnamespaced, so every one ships `geniro-`-prefixed.** Claude Code namespaces every skill by plugin (`/geniro:<slug>`); Cursor has no such namespace and registers each skill under its bare directory name, alongside its own built-ins and its reserved CLI slash commands, with no documented precedence or de-duplication rule for a clash. Left bare, `review` and `onboard` would collide with Cursor built-in skills and `plan`, `debug`, and `update` with reserved CLI commands — five of the fourteen. The generator prefixes all fourteen rather than only those five: a mixed scheme still needs a collision table to know which name is which, and a Cursor built-in added later could collide with a name left bare. The shared `skills/` directory itself is untouched — Claude Code keeps reading it at the original bare slugs via `/geniro:<slug>`, and that same token in skill prose (a printed next-step command, a cross-skill reference) means "the skill in `skills/<slug>/`," translated to `/geniro-<slug>` when narrating to a Cursor user, per `skills/_shared/runtime-portability.md` §Skill and agent naming.
- **`/geniro-reflect`'s past-session shapes and `/geniro-update`** require Claude Code (the session-transcript layout on disk / the `claude plugin` CLI) and exit with a notice elsewhere. `/geniro-reflect --this-session` runs here: it mines the running conversation and reads no transcript file. Update the Cursor install by pulling the repo (symlink) or re-importing the marketplace entry.
- **Model tiering, statusline, deep-mode `Workflow` fan-out, worktree tools, plan artifacts** — each has a documented fallback in the skills; nothing breaks.
- Hook events Cursor does not deliver to plugins in a compatible slot (`AskUserQuestion` gate-render, the marketplace update check) are not wired; the corresponding conventions apply as instructions per `skills/_shared/runtime-portability.md`.

## Maintaining the Cursor port

- `cursor/skills/*/SKILL.md` are **generated** — edit `skills/<slug>/SKILL.md` (and its sibling phase/reference files, which are not duplicated), run `scripts/build-cursor-skills.sh`, commit the result. CI (`tests/cursor/build-skills-fresh.sh`) fails on drift.
- `cursor/agents/*.md` are **generated** — edit `agents/*.md`, run `scripts/build-cursor-agents.sh`, commit both. CI (`tests/cursor/build-agents-fresh.sh`) fails on drift.
- `cursor/hooks.json` wires the shim; add new hook scripts there only if their event maps cleanly (see the translation map at the top of `cursor/hooks/claude-hook-shim.sh`).
- `tests/cursor/hook-shim.sh` covers the adapter's translation and fail-open behavior.
