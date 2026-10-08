<!-- Generated from skills/setup/phase-3-generate.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Setup Phase 3 — Generate

Phase file for `/geniro:setup`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`.

**Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: setup`, `LOAD_TIER: rules-only`, `MODE: refresh`. Compaction since the previous load may have silently dropped the rules — re-Read all files and echo per the helper's contract. This is the phase that writes `CLAUDE.md` and `.gitignore` into the user's tree; the only prior load is Phase 0, before the Detect scan and the full Interview.

### 3.0 Migration sweep (re-run only)

When `mode == re-run`, Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/setup-rerun-reference.md` now — before any step of the re-run, echoing per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`, because it is the sole home of this skill's migration apply policy: which `Auto-fix:` values may reach a shell at all, the `manual-only`-tested-first ordering, and the destructive-command deferral. A run that improvises the sweep runs prose through `bash -c`, which is exactly what that policy exists to prevent. Then run its §3.0 sweep before generating content — that file carries every re-run-only procedure this run needs (§3.0 sweep, §3.1 pre-write audit, §3.4 merge rules).

**Init mode skips this step entirely** — fresh installs have no prior schema and write the current one directly.

### 3.1 Pre-write existing-content audit (re-run only)

When `mode == re-run`, run the audit in `${CLAUDE_PLUGIN_ROOT}/skills/setup/setup-rerun-reference.md` §3.1 — it merges detected updates into the existing `CLAUDE.md` instead of overwriting it. Read the file here if this phase resumed after a compaction.

If `mode == init`, skip the pre-write audit and proceed to §3.2.

### 3.2 CLAUDE.md generation — project-only content

CLAUDE.md is a **project file**, not a plugin manual. It contains ONLY information specific to THIS repository. Before generating, Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md` §Excluded content — the single enumeration of the plugin content that must not appear in the generated file — and keep every item out.

Generated CLAUDE.md sections:

| Section | Content | Source |
|---|---|---|
| Header | Project name + 1-line purpose | `README.md` / `package.json` name field |
| Project Overview | What this project does, architecture, key design decisions | `README.md`, `ARCHITECTURE.md`, `docs/` |
| Tech Stack | Languages, frameworks, databases, infra | Phase 1 Detect output |
| Commands | Build, test, lint, typecheck, dev server | `package.json` scripts / `Makefile` / `pyproject.toml` |
| Project Conventions | Naming, patterns, code style rules | `.editorconfig`, ESLint/Prettier config, `CONTRIBUTING.md` |
| Domain Context | Key entities, API patterns, business terms | Project docs, API specs, `.env.example` variable names |

### 3.3 Write targets

- `<PROJECT_ROOT>/CLAUDE.md` — project-specific content only. No section markers — CLAUDE.md is user-owned content, not plugin-managed. Re-run mode uses orchestrator-inline merge (preserve user edits + update detected facts).
- `<PRIMARY_ROOT>/.geniro/instructions/global.md` — only if user opted in.
- `<PRIMARY_ROOT>/.geniro/workflow/<tracker>.md` — per `$ISSUE_TRACKER_CHOICE` (§2.4), installed from `${CLAUDE_PLUGIN_ROOT}/skills/setup/workflow-templates/` (a stub for non-Linear). Include the AI-disclosure prefix section, a `## Searching for issues` heading, and a `## PR description` heading in every workflow file — filled in for Linear, left as an unfilled placeholder for the user to complete in the non-Linear stub. The disclosure section lets human reviewers tell an AI-authored tracker update from a teammate's; the search heading lets a consumer checking for prior tracker work read "no search capability declared" rather than mistake the blank section for an unreachable tracker. The PR-description heading lets `/geniro:implement` tell a prescribed PR-body line from an unfilled stub, which it ignores.
- `<PRIMARY_ROOT>/.geniro/instructions/{plan,implement}.md` — only when `$OPENSPEC_CHOICE` is "Yes" (§2.4b). Merge `${CLAUDE_PLUGIN_ROOT}/skills/setup/instruction-templates/openspec-plan.md`'s `## Additional Steps` → `### After user-approve` subsection into `plan.md`, and `${CLAUDE_PLUGIN_ROOT}/skills/setup/instruction-templates/openspec-implement.md`'s `### After ship` subsection into `implement.md`, creating either file from its scaffold in `${CLAUDE_PLUGIN_ROOT}/skills/setup/instruction-templates/instruction-file-scaffolds.md` first when absent.
- `<PRIMARY_ROOT>/.geniro/state/setup/state.md` — frontmatter update (`phase: generate → validate`). The singleton state file lives in `PRIMARY_ROOT`, not `PROJECT_ROOT` — when invoked from a linked worktree these differ, and rehydration + cleanup both look in the main worktree.
- `$CLAUDE_USER_DIR/hooks/geniro-statusline.js` — statusline script copy (§3.6); a user-config write outside PROJECT_ROOT.
- `$CLAUDE_USER_DIR/settings.json` — `statusLine` entry (§3.6); edited only with the user's confirmation when an entry already points elsewhere.
- `$HOME/.cursor/{skills,agents}/` and `$HOME/.cursor/hooks.json` — the Cursor profile install (§3.7): symlinks to the plugin's generated Cursor skill and subagent copies, plus its hook entries merged into an existing `hooks.json`. A user-config write outside PROJECT_ROOT, listed when `$HOME/.cursor/` exists and the plugin root carries `cursor/skills/`.
- `$CODEX_HOME/config.toml` and `$CODEX_HOME/plugins/cache/` (`CODEX_HOME` defaults to `~/.codex`) — the Codex install (§3.8): the marketplace entry the `codex` CLI records, plus a copy of the plugin. A user-config write outside PROJECT_ROOT, listed when `codex` is on PATH and the plugin isn't installed there.

Render the write plan to chat first — every §3.3 target, the generated CLAUDE.md line count, the statusline install, and the §3.7 Cursor profile and §3.8 Codex installs when Cursor or Codex is present for them to install into — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering, in the visual language of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md`. All Writes are then AUQ-gated at **batch level** (one AUQ "Generate CLAUDE.md (X lines) + .geniro/ files + install statusline? Options: yes / edit", with "+ Cursor skills" / "+ Codex plugin" added before the "?" when §3.7 / §3.8 applies). The statusline `settings.json` replacement (when an entry already points elsewhere) carries its own §3.6 confirm on top of this batch consent.

### 3.4 Conflict-resolution merge rules (re-run only)

Section merge runs **orchestrator-inline** — no subagent spawn. The four merge rules are in `${CLAUDE_PLUGIN_ROOT}/skills/setup/setup-rerun-reference.md` §3.4; Read the file here if this phase resumed after a compaction.

### 3.5 Runtime directories + gitignore

Recompute `PRIMARY_ROOT` via the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` inside this same Bash call — Mode A owns the recompute-per-call rule.

```bash
# workflow/ + instructions/ are cross-session → primary worktree. planning/ is task-local (cwd).
# knowledge/ is cross-session too, but its writers self-route to the repo root via lib/repo-root.sh — this cwd mkdir is only a convenience.
mkdir -p "$PRIMARY_ROOT"/.geniro/workflow "$PRIMARY_ROOT"/.geniro/instructions .geniro/planning .geniro/knowledge
```

#### `.gitignore` re-include procedure

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gitignore-negation.md` in the same Bash call that resolved `PRIMARY_ROOT`, with `workflow instructions` as the directories that must stay committed. It drops a bare `.geniro/` line if present (that line would ignore the whole tree and defeat every negation), then idempotently appends `.geniro/*`, `!.geniro/`, `!.geniro/<dir>/`, and `!.geniro/<dir>/**` to the primary worktree's `.gitignore`.

### 3.6 Install statusline

Copy statusline script to stable location and configure user settings:

```bash
mkdir -p "$CLAUDE_USER_DIR/hooks"
cp "${CLAUDE_PLUGIN_ROOT}/hooks/geniro-statusline.js" "$CLAUDE_USER_DIR/hooks/geniro-statusline.js"
```

Check `$CLAUDE_USER_DIR/settings.json` for a `statusLine` entry. If absent, add one pointing to `<config-dir>/hooks/geniro-statusline.js`. If present and points to something else, `AskQuestion` (header: "Statusline") quoting the existing command: "Your `settings.json` statusLine is currently `<existing command>` — replace it with the Geniro statusline?" / options "Replace with Geniro statusline" / "Keep the existing one". This confirm is separate from the §3.3 batch AUQ — it overwrites a `~/.claude/settings.json` entry outside PROJECT_ROOT, which affects every other project on the machine, not just this one.

### 3.7 Install Geniro into the Cursor profile (conditional)

Fires only when this machine has a Cursor install (`$HOME/.cursor/` exists) AND the resolved plugin root carries `cursor/skills/` AND it was not dropped at the §3.3 batch approval. Skip silently when any of these fails — there is nothing to install into, nothing to install, or the user declined it.

`cursor-agent` loads no plugin components at all, so a plugin install alone leaves every Cursor CLI and ACP session with no Geniro skills, no Geniro subagents, and none of the hooks; the IDE is unaffected. The per-component profile directories are the only route that reaches both surfaces. `${CLAUDE_PLUGIN_ROOT}/cursor/README.md` §Install carries the evidence, the source threads, and the condition for removing this step once Cursor fixes the bug.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-cursor.sh"
```

The script is idempotent and touches only what it owns in those shared destinations, so a re-run costs nothing. It also picks its own link target: invoked from a versioned install cache it links to the marketplace checkout instead, so the install survives plugin updates. Report the source line it prints, and pass on every `WARNING:` and `SKIP:` line it emits — a version-carrying link, a Cursor plugin install that will now double every skill, a `hooks.json` left untouched because `jq` is missing — rather than dropping them. Record the outcome for the §5.1 report.

### 3.8 Install Geniro into Codex (conditional)

Fires only when the `codex` CLI is on PATH AND this plugin is not already installed there AND it was not dropped at the §3.3 batch approval. Skip silently when Codex is absent or the user declined it. `<plugin>` and `<marketplace>` are the `name` fields of the `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` the plugin root carries.

Check with `codex plugin list --json -m <marketplace>` — the plain-text `codex plugin list` also pulls OpenAI's remote catalog. The plugin in `installed` means it is already installed: record "already installed" for the §5.1 report and change nothing. The plugin in `available` means the marketplace is configured; both lists empty means it is not. A non-zero exit or unparsable output is a failure to report, not an absent install.

Install from a local source: it needs no network (this phase allows no network egress), and `/geniro:update` re-copies the install from that same source on every run. Take the source from `installLocation` in `$CLAUDE_USER_DIR/plugins/known_marketplaces.json`, for the marketplace whose checkout's `.claude-plugin/plugin.json` names this plugin; otherwise use the resolved plugin root. Accept a source only when it is a checkout — never one under `plugins/cache/`: Codex records the path, and a removed versioned cache dir breaks every `codex plugin` command. With no such source, skip the install and record that for the §5.1 report, which sends the user to `${CLAUDE_PLUGIN_ROOT}/README.md` §Using with Codex to install by hand.

Run `codex plugin marketplace add "<source>"` — skipped when the marketplace is already configured — then `codex plugin add <plugin>@<marketplace>`. Report the "Installed plugin root" line it prints, and pass on any error output rather than dropping it. Record the outcome for the §5.1 report. A failed Codex install is reported and does not block the phase.

Transition to Phase 4.

