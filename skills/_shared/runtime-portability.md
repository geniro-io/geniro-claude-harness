# Runtime portability — running Geniro skills outside Claude Code

Applies when a skill runs under another Agent-Skills runtime (Cursor, Codex, Copilot, or any host that reads `SKILL.md` but is not Claude Code). Detection signal: `CLAUDECODE` is absent from the environment, or the tool surface lacks Claude Code tools named below.

An empty `$CLAUDE_PLUGIN_ROOT` is not that signal. Claude Code substitutes that placeholder into file references and hook commands and never exports it to a shell, so it reads empty in a Bash call under Claude Code too — reading it as "another runtime" opens a normal run with a degradation notice the user then has to discount. Under Claude Code two sections still apply: §Plugin-root resolution, because the shell genuinely needs the path, and any Tool substitutions row for a tool this host really lacks (`TodoWrite` is absent from the SDK and desktop hosts). Skip the rest.

## Contents

- Plugin-root resolution
- When the plugin's files are genuinely unreachable
- When no user can answer
- Hooks do not fire — self-enforce the conventions
- Subagents do not inherit the orchestrator's cwd
- Tool substitutions
- Arguments
- Session restore without the SessionStart hook
- What requires Claude Code
- Skill and agent naming

**The host changes how a step runs, never which steps run.** Everything below substitutes a mechanism; nothing below removes a gate, a question, a phase-body Read, or a state write. Read this file before deciding a step cannot run here, because the guess it replaces is usually wrong in a specific way: a tool you have not searched for is not a tool you lack (several hosts defer tool schemas), a tool you could not find under its Claude Code name is not a tool the host lacks — resolve it by name via the Tool substitutions table below before falling back — and several hosts register this plugin's own agents under their bare names. Two rationalizations recur and both look responsible from the inside — that the skill is heavier than this host warrants, so its "ceremony" can be trimmed to the engineering essentials, and that the project's own rules already cover the practices, so they can stand in for the skill. The gates ARE the essentials, and the project's rules govern how code is written while the skill governs which decisions are the user's; a run that trims either edits the user's code without ever asking them anything, and leaves no trace of the questions it skipped.

## Plugin-root resolution

Each SKILL.md preamble carries the bootstrap. Work the rungs in order and stop at the first that resolves:

1. **The ancestor directory of the SKILL.md you are reading that contains `.claude-plugin/plugin.json`.** The normal answer under any plugin install, Claude Code's and Cursor's alike. There is no env-var rung above this one — the variable is a placeholder, not an export, so probing the shell for it resolves nothing anywhere.
2. **A sibling copy of the target file beside the SKILL.md you read.** The Cursor build ships each skill's own phase and reference files into its generated directory, so `${CLAUDE_PLUGIN_ROOT}/skills/<slug>/phase-1-analyze.md` is satisfied by `phase-1-analyze.md` sitting next to that copy. This rung resolves per-file and covers only a skill's own files — `skills/_shared/` and `agents/` are cross-cutting and live at the root.
3. **A plugin checkout inside the workspace** — a vendored copy, a submodule, or a sibling clone of `geniro-claude-harness`. Identify it the same way: the directory containing `.claude-plugin/plugin.json`.

Resolve once, substitute for every `${CLAUDE_PLUGIN_ROOT}` occurrence in file references, and `export CLAUDE_PLUGIN_ROOT=<resolved-path>` in every Bash call that sources a `lib/*.sh` helper — several helpers read the variable directly. All `lib/*.sh` helpers are plain bash + jq and work unchanged once the path resolves — so "the state helpers probably assume Claude Code" is a guess this one resolution disproves, and dropping the state contract on it costs the run its only resumable record.

## When the plugin's files are genuinely unreachable

Some hosts deliver a skill as text and nothing else: a cloud or background agent given the SKILL.md body inlined, with the path it came from pointing at a machine this run is not on. Every rung above then fails, and the operative half of the skill — its phase bodies, its reference procedures, this file — cannot be read at all.

**The files are missing; the contract is not.** What survives is the SKILL.md body itself, which carries the phase map, the state machine, the loop invariants, and the anti-rationalization table. Run from it:

- **Say so first.** Open the run by naming what is unavailable and which parts of the flow are therefore approximated. A degraded run that reads as a normal one is the failure mode — the user cannot audit a substitution they were never told about.
- **Every phase still runs, in order, and every gate the spine names still fires.** A phase body you cannot read is a phase whose steps you must reconstruct from the spine, not a phase to skip. Where the spine names a gate without its option list, ask the question in your own words rather than deciding it.
- **The project's own rules are not a substitute.** `CLAUDE.md`, `AGENTS.md`, `.cursor/rules/*.mdc` and their kin govern how code is written; this skill governs which decisions are the user's. Adopting the former as a stand-in for the latter produces a run that edits the user's code without ever asking them anything — see the two rationalizations named at the top of this file.
- **Prefer restoring the files over improvising without them.** A workspace with network access can fetch the plugin (`git clone https://github.com/geniro-io/geniro-claude-harness`, or a release tarball) into a scratch directory and set `CLAUDE_PLUGIN_ROOT` to it. Try this once, early; on failure say so and continue degraded rather than retrying.
- **Report the degradation at the end too**, next to the deferred decisions below. The opening notice is gone from the user's screen by then, and the PR body is read by people who never saw it.

## When no user can answer

A host with no structured-question tool AND no human in the loop — a cloud agent, a scheduled run, a batch evaluation — does not get to drop its gates. `${CLAUDE_PLUGIN_ROOT}/skills/_shared/non-interactive-host.md` owns that contract: setup gates take the most reversible option and are reported as deferred decisions; safety and anomaly gates halt and hand the question back; a floor of outward-facing actions stays closed without an explicit answer. Read it before concluding a decision is yours to make.

Note the ordering against the row below: a missing question tool is common and usually wrong (hosts rename it), while a missing *user* is a property of how the run was launched. Establish both before applying that file.

## Hooks do not fire — self-enforce the conventions

Claude Code wires `hooks/hooks.json` (PreToolUse guards, SessionStart restore). Other runtimes never read that file, so every guardrail becomes a binding instruction on you instead of a mechanical block. Before the corresponding action, apply the same check the hook would have applied:

| Lost hook | Self-enforce |
|---|---|
| State-helper enforcement | Write `.geniro/` state paths only via the `atomic-state-write` helpers — `atomic_state_write` / `atomic_state_write_cmd` for whole files, `atomic_state_edit` / `atomic_state_set_field` for in-place changes, `atomic_state_append` for JSONL — never direct Edit/Write/redirection. |
| Destructive-git guard | Do not run force-push, `reset --hard`, `branch -D`, `clean -fd`, mass-discard checkout/restore, or remote-branch deletion unless the user explicitly asked for that exact operation. |
| `.geniro/` deletion guard | No bulk `rm -rf .geniro/` or `git add -f` on `.geniro/` paths; delete only specific files you created. |
| File protection | Do not write `.env*`, `*.key`, `*.pem`, credentials, or lock files. |
| Security pattern scan | Before writing code, check it against the anti-pattern list in the Safety Hooks section of the plugin CLAUDE.md (eval/exec, unsafe yaml/pickle, shell injection, TLS bypass, XSS sinks, weak hashes). |
| Gate-render enforcement | Render the self-contained context message to chat BEFORE asking any decision question, per `gate-rendering.md` — no mechanical check will catch a blind gate for you. |
| Reporter no-Edit/no-Write contract | Hold it yourself under every host, Claude Code included — `allowed-tools` only pre-approves listed tools, it never restricted `Write`/`Edit`; Cursor subagents additionally inherit every parent tool regardless of the frontmatter list (`reporter-boundary.md` §1). |

If Cursor is the host and the plugin's Cursor hook set is installed (see `cursor/README.md` in the plugin root), the shell-side and file-side guards above fire mechanically again; the instruction layer still applies for anything the port does not cover.

## Subagents do not inherit the orchestrator's cwd

Claude Code passes the parent's working directory to a spawned subagent; other hosts start it at the workspace root. Whenever the orchestrator works in a linked worktree or on a PR head, that is a different tree on a different branch — so a spawn prompt that names its target by relative path, or that asks the subagent to confirm its inherited cwd, gets the wrong tree or a dead spawn.

Both are already handled by the spawn contract, which every codebase-work spawn carries: pass `WORKTREE` as an absolute path and have the subagent `cd` to it on each Bash call, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` § Subagent spawn anchor. Keep it when authoring a new spawn site here — the same prompt then runs correctly under either host.

## Tool substitutions

| Claude Code tool | Substitute |
|---|---|
| `AskUserQuestion` | Resolve by name before concluding absence: this host's tool surface may carry the same capability under a different name (Cursor: `AskQuestion`). Only once no such tool exists under any name, fall back to chat: render the gate message, then a lean question with lettered options (recommended one first), and record the answer in state.md `approvals: []` exactly as an AUQ answer would. The resolved tool may carry no `header` field (Cursor's does not) — drop it and keep the question, rather than reading a field's absence as the tool's. A missing facility changes how the gate renders, never whether it fires. When the chat fallback has no reader either — an unattended run — apply §When no user can answer above; the gate is deferred and reported, never dropped. |
| `Agent(subagent_type=...)` | Use the host's subagent/task-delegation facility with the agent's **bare** name (`reviewer-agent`) — this is the form Cursor and every other non-Claude-Code host registers, and the `geniro:` prefix a skill body may show alongside it is Claude Code's plugin namespace, which resolves nowhere else. Enter the ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` at rung 2 accordingly; spending a parallel batch on rung 1 here costs one dead spawn per agent and a wasted turn to learn what this row already told you. Where the host registers none of the plugin's agents but ships generic ones (`explore`, `reviewer`, `tester`), delegate to the nearest generic and carry the plugin agent's contract in the spawn prompt — its scope, its evidence standard, and its Output Format — so what comes back is still the contracted artifact; the isolation is what the spawn buys, and a generic agent provides it. If the host has no delegation facility at all, run the agent's contract inline: read `agents/<name>.md`, strip frontmatter, follow its body against its input slots, and treat its Output Format as the result. Parallel fan-outs then run sequentially — correctness is unchanged, only wall-time. |
| `model="sonnet"` at a spawn site | `haiku`/`sonnet`/`opus` are Claude Code model ids and no other roster carries them, so translate the intent per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §Runtime resolution — under Cursor a mechanical or execution spawn passes `auto`, which is that host's own version of the sizing the Claude Code orchestrator does itself. Judgment-grade spawns still omit the argument entirely, in every host. Never substitute a pinned model id of your own choosing. |
| `TodoWrite` | Resolve by name before concluding absence: hosts that omit `TodoWrite` — Claude Code's own SDK and desktop hosts among them — usually carry the same capability as a task-list tool under another name (`TaskCreate` / `TaskUpdate` / `TaskList`). Use it under the same discipline, one item in progress at a time. Only where no such tool exists under any name, keep the numbered list in the state.md body and echo each transition in chat as it happens — the per-unit progress visibility is what the tool buys, and a list posted once at the start does not provide it. |
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
