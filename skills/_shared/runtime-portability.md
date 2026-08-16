# Runtime portability — running Geniro skills outside Claude Code

Applies when a skill runs under another Agent-Skills runtime (Cursor, Codex, Copilot, or any host that reads `SKILL.md` but is not Claude Code). Detection signal: `${CLAUDE_PLUGIN_ROOT}` is unset in the shell, or the tool surface lacks Claude Code tools named below. Under Claude Code, nothing here applies — skip this file.

## Contents

- Plugin-root resolution
- Hooks do not fire — self-enforce the conventions
- Subagents do not inherit the orchestrator's cwd
- Tool substitutions
- Arguments
- Session restore without the SessionStart hook
- What requires Claude Code
- Skill and agent naming

**The host changes how a step runs, never which steps run.** Everything below substitutes a mechanism; nothing below removes a gate, a question, a phase-body Read, or a state write. Read this file before deciding a step cannot run here, because the guess it replaces is usually wrong in a specific way: a tool you have not searched for is not a tool you lack (several hosts defer tool schemas), a tool you could not find under its Claude Code name is not a tool the host lacks — resolve it by name via the Tool substitutions table below before falling back — and several hosts register this plugin's own agents under their bare names. Two rationalizations recur and both look responsible from the inside — that the skill is heavier than this host warrants, so its "ceremony" can be trimmed to the engineering essentials, and that the project's own rules already cover the practices, so they can stand in for the skill. The gates ARE the essentials, and the project's rules govern how code is written while the skill governs which decisions are the user's; a run that trims either edits the user's code without ever asking them anything, and leaves no trace of the questions it skipped.

## Plugin-root resolution

Each SKILL.md preamble carries the bootstrap: when `${CLAUDE_PLUGIN_ROOT}` is unset, the plugin root is the ancestor directory of the SKILL.md that contains `.claude-plugin/plugin.json`. Resolve it once, substitute it for every `${CLAUDE_PLUGIN_ROOT}` occurrence in file references, and `export CLAUDE_PLUGIN_ROOT=<resolved-path>` in every Bash call that sources a `lib/*.sh` helper — several helpers read the variable directly. All `lib/*.sh` helpers are plain bash + jq and work unchanged once the path resolves — so "the state helpers probably assume Claude Code" is a guess this one resolution disproves, and dropping the state contract on it costs the run its only resumable record.

## Hooks do not fire — self-enforce the conventions

Claude Code wires `hooks/hooks.json` (PreToolUse guards, SessionStart restore). Other runtimes never read that file, so every guardrail becomes a binding instruction on you instead of a mechanical block. Before the corresponding action, apply the same check the hook would have applied:

| Lost hook | Self-enforce |
|---|---|
| State-helper enforcement | Write `.geniro/` state paths only via `atomic_state_write` / `atomic_state_append` — never direct Edit/Write/redirection. |
| Destructive-git guard | Do not run force-push, `reset --hard`, `branch -D`, `clean -fd`, mass-discard checkout/restore, or remote-branch deletion unless the user explicitly asked for that exact operation. |
| `.geniro/` deletion guard | No bulk `rm -rf .geniro/` or `git add -f` on `.geniro/` paths; delete only specific files you created. |
| File protection | Do not write `.env*`, `*.key`, `*.pem`, credentials, or lock files. |
| Security pattern scan | Before writing code, check it against the anti-pattern list in the Safety Hooks section of the plugin CLAUDE.md (eval/exec, unsafe yaml/pickle, shell injection, TLS bypass, XSS sinks, weak hashes). |
| TDD-order enforcement | When a TDD cycle is active (`.geniro/state/tdd/state-<slug>.md` shows RED), do not edit production files until the failing test exists. |
| Gate-render enforcement | Render the self-contained context message to chat BEFORE asking any decision question, per `gate-rendering.md` — no mechanical check will catch a blind gate for you. |
| Reporter no-Edit/no-Write contract | Hold it yourself under every host, Claude Code included — `allowed-tools` only pre-approves listed tools, it never restricted `Write`/`Edit`; Cursor subagents additionally inherit every parent tool regardless of the frontmatter list (`reporter-boundary.md` §1). |

If Cursor is the host and the plugin's Cursor hook set is installed (see `cursor/README.md` in the plugin root), the shell-side and file-side guards above fire mechanically again; the instruction layer still applies for anything the port does not cover.

## Subagents do not inherit the orchestrator's cwd

Claude Code passes the parent's working directory to a spawned subagent; other hosts start it at the workspace root. Whenever the orchestrator works in a linked worktree or on a PR head, that is a different tree on a different branch — so a spawn prompt that names its target by relative path, or that asks the subagent to confirm its inherited cwd, gets the wrong tree or a dead spawn.

Both are already handled by the spawn contract, which every codebase-work spawn carries: pass `WORKTREE` as an absolute path and have the subagent `cd` to it on each Bash call, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` § Subagent spawn anchor. Keep it when authoring a new spawn site here — the same prompt then runs correctly under either host.

## Tool substitutions

| Claude Code tool | Substitute |
|---|---|
| `AskUserQuestion` | Resolve by name before concluding absence: this host's tool surface may carry the same capability under a different name (Cursor: `AskQuestion`). Only once no such tool exists under any name, fall back to chat: render the gate message, then a lean question with lettered options (recommended one first), and record the answer in state.md `approvals: []` exactly as an AUQ answer would. The resolved tool may carry no `header` field (Cursor's does not) — drop it and keep the question, rather than reading a field's absence as the tool's. A missing facility changes how the gate renders, never whether it fires. |
| `Agent(subagent_type=...)` | Use the host's subagent/task-delegation facility with the agent's **bare** name (`reviewer-agent`) — this is the form Cursor and every other non-Claude-Code host registers, and the `geniro:` prefix a skill body may show alongside it is Claude Code's plugin namespace, which resolves nowhere else. Enter the ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` at rung 2 accordingly; spending a parallel batch on rung 1 here costs one dead spawn per agent and a wasted turn to learn what this row already told you. If the host has no delegation facility, run the agent's contract inline: read `agents/<name>.md`, strip frontmatter, follow its body against its input slots, and treat its Output Format as the result. Parallel fan-outs then run sequentially — correctness is unchanged, only wall-time. |
| `model="sonnet"` at a spawn site | `haiku`/`sonnet`/`opus` are Claude Code model ids and no other roster carries them, so translate the intent per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §Runtime resolution — under Cursor a mechanical or execution spawn passes `auto`. Judgment-grade spawns still omit the argument entirely, in every host. Never substitute a pinned model id of your own choosing. |
| `TodoWrite` | Keep the numbered todo list in the state.md body and echo progress in chat. |
| `Workflow` | Use the documented single-pass fallback at each deep-mode call site. |
| `EnterWorktree` / `ExitWorktree` | `git worktree add` / `remove` via Bash, per the skill's existing Bash path. |
| `Artifact` | Skip, per the artifact helper's skip notice. |
| `WebSearch` / `WebFetch` | The host's web-search/fetch capability. |

## Arguments

`$ARGUMENTS` is Claude Code slash-command substitution. In other runtimes, treat everything the user wrote after naming the skill as `$ARGUMENTS`, including flags like `--deep`.

## Session restore without the SessionStart hook

No context is auto-injected on resume. When asked to resume or continue a task, locate the task's `state.md` yourself, run `validate_state_file` on it, then follow the skill's own state-recovery entry (`phase:` frontmatter). Re-read the custom-instruction files and any persisted `approvals: []` before acting — nothing re-surfaces them for you.

## What requires Claude Code

`/geniro:reflect`'s past-session shapes — a search string, or an empty argument — read session transcripts from the Claude Code on-disk layout, and `/geniro:update` needs the `claude plugin` CLI and install registry. Both function only under Claude Code; when invoked elsewhere, state that plainly and exit without side effects. `/geniro:reflect --this-session` runs here — it mines the running conversation and reads no transcript file — provided the host has a delegation facility: its synthesis spawn is the isolation that shape depends on, so the inline-agent substitution above does not cover it.

## Skill and agent naming

Each skill's `name:` frontmatter is the bare slug. Claude Code prefixes it with the plugin name, so commands surface as `/geniro:<slug>`. Other runtimes register skills under whatever name their generated manifest assigns — Cursor's `cursor/skills/geniro-<slug>/` prefixes every skill (`/geniro-<slug>`) because Cursor has no plugin namespace and several bare slugs collide with its built-in skills or reserved CLI commands; `cursor/README.md` records the current collision set. Cross-references written as `/geniro:<slug>` mean "the skill in `skills/<slug>/`" — translate to the host's actual registered name (e.g. `/geniro-<slug>` for Cursor) when narrating to that host's user.
