# Using Geniro with Cursor

This repository is a dual-runtime plugin: `.claude-plugin/plugin.json` packages it for Claude Code, `.cursor-plugin/plugin.json` packages it for Cursor. Skills, agents, and hooks are each runtime-specific ports generated from one canonical source:

| Component | Claude Code reads | Cursor reads |
|---|---|---|
| Skills | `skills/` (auto-discovered, namespaced `/geniro:<slug>`) | `cursor/skills/geniro-<slug>/` (via the manifest's `"skills"` field) — generated from `skills/<slug>/SKILL.md` by `scripts/build-cursor-skills.sh` |
| Agents | `agents/` (Claude frontmatter: `tools`, `model`, `maxTurns`) | `cursor/agents/` (Cursor frontmatter: `model`, `readonly`) — generated from `agents/` by `scripts/build-cursor-agents.sh` |
| Hooks | `hooks/hooks.json` (PascalCase events, exit-2 blocks) | `cursor/hooks.json` (camelCase events) → `cursor/hooks/claude-hook-shim.sh` → the same scripts in `hooks/` |

`cursor/skills/geniro-<slug>/` is self-contained for that skill: the `SKILL.md` (frontmatter `name:` rewritten to match the directory) plus a copy of every sibling the skill reads at runtime — its phase bodies, reference procedures, and templates, subdirectories preserved. Intra-skill references stay in the fully-qualified `${CLAUDE_PLUGIN_ROOT}/skills/<slug>/...` form and are not rewritten; the sibling copy satisfies them without any root resolution, per `skills/_shared/runtime-portability.md` §Plugin-root resolution rung 3. `skills/_shared/` and `agents/` are cross-cutting and stay at the plugin root — a per-skill copy would duplicate ~900KB fourteen times and drift.

## Install

**As a Cursor plugin (recommended)** — full experience: skills + subagents + safety hooks.

1. Symlink or copy this repository to `~/.cursor/plugins/local/geniro` (symlink keeps it on the latest checkout), or import the repo through **Dashboard → Plugins → Team Marketplaces**.
2. Restart Cursor. Skills appear in the **IDE's** `/` picker as `geniro-<slug>` (`/geniro-plan`, `/geniro-implement`, `/geniro-review`, ...) — see What degrades below for why every skill carries the prefix, not only the ones that collided; subagents (`reviewer-agent`, `codebase-explorer-agent`, ...) become Task-tool targets under their bare names. The `cursor-agent` **CLI** needs one extra step — next subsection.

**Via the Claude Code compatibility toggle** — skills only, no hooks or agents.

If the plugin is installed in Claude Code from the marketplace, enabling **Settings → Rules, Skills, Subagents → "Include third-party Plugins, Skills, and other configs"** lets the Cursor IDE pick the skills up from `~/.claude/plugins/cache/`. Safety hooks and subagents do not travel this route; prefer the Cursor plugin install above.

### Extra step for the `cursor-agent` CLI — temporary workaround for a Cursor bug

`cursor-agent` does not register skills from plugins **at all** — not from the Cursor marketplace, not from `~/.cursor/plugins/local/`, not via `--plugin-dir`, not through the compatibility toggle above ([confirmed by Cursor][cli-bug]; see also [the wider plugin-capabilities gap][caps-gap]). The IDE registers them; the CLI does not. It scans four hard-coded directories, none of which is a plugin directory: `<repo>/.claude/skills/`, `<repo>/.cursor/skills/`, `~/.cursor/skills/`, `~/.cursor/skills-cursor/`. An agent that cannot find the skill does not error — it silently proceeds on its own reasoning.

`/geniro-setup` offers this step on any machine with a Cursor install — it appears in the write plan alongside CLAUDE.md and the statusline, so approving that gate installs the links. Run it by hand if you would rather not re-run setup:

```bash
scripts/install-cursor-skills.sh              # link cursor/skills/geniro-* into ~/.cursor/skills/
scripts/install-cursor-skills.sh --uninstall  # remove exactly those links
```

Idempotent, and it never overwrites or deletes an entry it does not own (`~/.cursor/skills/` is shared with your own skills — anything under a `geniro-` name that is not one of its links is skipped and reported).

**The links carry no version, so a plugin update does not break them.** Invoked from Claude Code's versioned install cache (`~/.claude/plugins/cache/<marketplace>/geniro/<version>/`), the script does not link there — it links to the marketplace checkout beside it (`~/.claude/plugins/marketplaces/<marketplace>/`), which holds the same plugin at a path with no version in it and is refreshed in place by a plugin update. A git checkout or `~/.cursor/plugins/local/geniro` is already version-independent and is used as-is. It prints the source it resolved. Only where the script is run from the versioned cache and no marketplace checkout exists does it fall back to the versioned path — it warns then, and `/geniro:update` re-points those links in its post-check (Claude Code only, since that skill needs the `claude plugin` CLI). Do this in addition to the plugin install — the plugin is still what gives the IDE its hooks and subagents.

**This step goes away with the bug.** The check: install the plugin normally, remove every link, ask a fresh `cursor-agent` session whether it has the `geniro-implement` skill. When it says yes, delete the script, `tests/cursor/install-skills.sh`, and this subsection. Worth re-checking on each CLI update rather than assuming it is closed — the bug was already fixed once by a server-side flag (`v2026.05.05-84a231c`) and regressed by the August build.

[cli-bug]: https://forum.cursor.com/t/cursor-agent-cli-does-not-register-skills-from-plugins-ide-does-parity-gap/158947
[caps-gap]: https://forum.cursor.com/t/agent-does-not-have-access-to-plugin-capabilities-mcp-skills-commands-etc/154334

## What works in Cursor

- **The 13 runtime-portable skills**, each surfaced as `/geniro-<slug>`. Each carries a runtime-portability preamble that resolves the plugin root from the ancestor directory holding a plugin manifest, so the shared helpers (`skills/_shared/`) and shell libraries (`lib/`) work unchanged. `/geniro-update` is the one exception, and `/geniro-reflect` is portable only in its `--this-session` shape — see the Claude-Code-only note below. Degradation contract: `skills/_shared/runtime-portability.md`.
- **Safety + enforcement hooks** for shell commands and file writes: destructive-git guard, `.geniro/` deletion guard, protected-file writes, security pattern scan, state-helper enforcement — adapted through `cursor/hooks/claude-hook-shim.sh` (a blocked action returns `{"permission":"deny"}` with the guardrail reason).
- **Session-start context restore.** The `sessionStart` hook re-injects the active task state and instruction-file list as `additional_context`.
- **The subagents in `cursor/agents/`** for the parallel review/research fan-outs, registered under their bare names.

## Cloud and background agents

A Cursor cloud agent runs in a VM that has your repository and **nothing from your laptop**. Two things follow, and both have bitten a real run.

**The plugin has to exist in that VM.** Where the skill reaches the agent as inlined text — the Claude Code compatibility-toggle route syncs the definition it found under `~/.claude/plugins/cache/`, a path the VM does not have — every `${CLAUDE_PLUGIN_ROOT}` reference in it points at your local machine. The agent then has the skill's spine and none of its phase bodies, gates, or spawn templates. It will not stall: it will reconstruct a plausible flow from your repo's own rules and report success. Make the plugin present instead, by one of:

- installing Geniro as a **Cursor plugin at the team/marketplace level**, so it is provisioned into cloud environments rather than synced from a workstation;
- **vendoring** the plugin into the repository (a submodule or a checked-in copy) — rung 4 of the resolution ladder finds any directory containing `.claude-plugin/plugin.json` inside the workspace;
- adding a clone step to the environment's setup command.

Failing all three, the skill runs degraded under a defined contract rather than an improvised one (`skills/_shared/runtime-portability.md` §"When the plugin's files are genuinely unreachable"): it announces what is missing, runs every phase and gate the spine names, and never lets your repo's rules stand in for the skill's decision gates.

**Nobody is there to answer a gate.** A cloud agent has no `AskQuestion` reader — the run is one prompt in, one report out. `skills/_shared/non-interactive-host.md` owns what happens then: setup gates (workspace, depth, freshness, ship mode) take the most reversible option and are reported back as deferred decisions; safety and anomaly gates halt and hand the question back; and a floor of outward-facing actions — ready-for-review PR, merge, force-push, protected-branch push, posted comment, tracker transition — stays closed without an explicit answer. Pre-answer the setup gates through the sanctioned channels so the run does not have to default: the spec's `launch_config:` block, or launch modifiers in the invocation (`/geniro-implement <spec> worktree ship:draft`).

## What degrades or stays Claude-Code-only

- **Structured decision gates** (`AskUserQuestion`) become plain chat questions with lettered options.
- **Per-tool write restrictions** (`tools:` in Claude agent frontmatter, the field that genuinely withholds a tool) have no Cursor equivalent — Cursor's subagent frontmatter exposes no `tools` field and subagents inherit every tool from the parent regardless of that list. The generated `cursor/agents/*.md` set the coarser `readonly: true` flag instead (no file edits, no state-changing shell commands) for every read-only agent; a Reporter skill's finer no-`Edit`/no-`Write` contract is prose the model holds itself under Cursor — see `skills/_shared/reporter-boundary.md` §1.
- **Skill names are unnamespaced, so every one ships `geniro-`-prefixed.** Claude Code namespaces every skill by plugin (`/geniro:<slug>`); Cursor has no such namespace and registers each skill under its bare directory name, alongside its own built-ins and its reserved CLI slash commands, with no documented precedence or de-duplication rule for a clash. Left bare, `review` and `onboard` would collide with Cursor built-in skills and `plan`, `debug`, and `update` with reserved CLI commands — five of the fourteen. The generator prefixes all fourteen rather than only those five: a mixed scheme still needs a collision table to know which name is which, and a Cursor built-in added later could collide with a name left bare. The shared `skills/` directory itself is untouched — Claude Code keeps reading it at the original bare slugs via `/geniro:<slug>`, and that same token in skill prose (a printed next-step command, a cross-skill reference) means "the skill in `skills/<slug>/`," translated to `/geniro-<slug>` when narrating to a Cursor user, per `skills/_shared/runtime-portability.md` §Skill and agent naming.
- **`/geniro-reflect`'s past-session shapes and `/geniro-update`** require Claude Code (the session-transcript layout on disk / the `claude plugin` CLI) and exit with a notice elsewhere. `/geniro-reflect --this-session` runs here: it mines the running conversation and reads no transcript file. Update the Cursor install by pulling the repo (symlink) or re-importing the marketplace entry.
- **Model tiering, statusline, deep-mode `Workflow` fan-out, worktree tools, plan artifacts** — each has a documented fallback in the skills; nothing breaks.
- Hook events Cursor does not deliver to plugins in a compatible slot (the marketplace update check) are not wired; the corresponding conventions apply as instructions per `skills/_shared/runtime-portability.md`.

## Maintaining the Cursor port

- **Everything under `cursor/skills/` is generated** — edit `skills/<slug>/SKILL.md` or any of its siblings, run `scripts/build-cursor-skills.sh`, commit the result. The generator clears each skill's output directory first, so a deleted source file disappears from the copy. CI (`tests/cursor/build-skills-fresh.sh`) fails on drift.
- `cursor/agents/*.md` are **generated** — edit `agents/*.md`, run `scripts/build-cursor-agents.sh`, commit both. CI (`tests/cursor/build-agents-fresh.sh`) fails on drift.
- `cursor/hooks.json` wires the shim; add new hook scripts there only if their event maps cleanly (see the translation map at the top of `cursor/hooks/claude-hook-shim.sh`).
- `tests/cursor/hook-shim.sh` covers the adapter's translation and fail-open behavior.
- `scripts/install-cursor-skills.sh` links, it does not copy — a regenerated `cursor/skills/` reaches an already-linked profile with no re-run. Covered by `tests/cursor/install-skills.sh`.
