# Geniro Plugin

One `skills/` directory ships to two runtimes, Claude Code and Cursor.

## Skill routing

Each skill's frontmatter description is the routing surface, and Claude Code already loads them at discovery — don't restate them here. Three things those descriptions don't carry:

- **`/geniro:implement` and `/geniro:resolve` are the skills that ship code.** `/geniro:plan`, `/geniro:review`, and `/geniro:debug` are producers: they end at a `spec.md` and/or a handoff file that `/geniro:implement` consumes and applies. `/geniro:resolve` owns its own loop end to end — it decides which PR comments are worth doing, applies those fixes, and closes the threads.
- **Read-only means production source unchanged at exit — not an empty tool surface.** `/geniro:review`, `/geniro:debug`, and `/geniro:investigate` end every run with production source as they found it, and an elevated-effort or workflow run does not relax that; `/geniro:debug` alone gets there by reverting rather than by abstaining — its verification escape hatch edits production source when a chain cannot be mocked, then reverts every touched path before escalating. All three hold the rule as a prose contract, not a tool-level block: a skill's `allowed-tools` only pre-approves listed tools, so omitting `Write`/`Edit` skips the permission prompt for them but never blocks the call (`skills/_shared/reporter-boundary.md` §1). `/geniro:refactor` does edit production source, but never ships: the working-tree diff is its deliverable.
- **Skills have been deleted.** A name that doesn't resolve isn't necessarily a typo — check the catalogue for its replacement.

## Path Rules

Always use `${CLAUDE_PLUGIN_ROOT}` for plugin files or fully resolved absolute paths for project files, passed to Read, Write, Edit, or Glob — never `~`, which these tools don't expand and instead create as a literal `~` directory.

## Never force-add `.geniro/` paths

`git add -f` on a `.geniro/` path makes ignored files visible in IDE Source Control panels, and one "Discard All Changes" click then becomes a data-loss vector. For content that genuinely should be tracked, use `.gitignore` negation (`!.geniro/actions/` plus `!.geniro/actions/**`). A hook blocks the force-add.

## State Files

Everything under `.geniro/{state,planning,knowledge,instructions,actions,workflow}/` is a state file, and every write goes through `atomic_state_write` (or `atomic_state_append` for `knowledge/*.jsonl`) — sourced per Bash call:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
atomic_state_write "<path>" <<'EOF'
...
EOF
```

**Changing part of a file that already exists** — `atomic_state_set_field "<path>" phase ship` for a frontmatter field, `atomic_state_edit "<path>" "<old>" "<new>"` for a span of body text. Same atomic commit, without regenerating the file: a regeneration re-writes every field the transform didn't touch at its old value, and that stale value validates clean.

**Adding an entry** — `atomic_state_append_section "<path>" "## Tool log" "<entry>"` appends at the END of a body section (the heading is the wrong anchor for an edit: it inserts above the older entries and inverts the log; pass `--create` for a section the run creates on demand). `atomic_state_append_list_item "<path>" approvals "<entry>"` appends an item to a frontmatter YAML list — the multi-line mapping shape `set_field` cannot write.

**Content produced by a program** — `atomic_state_write_cmd "<path>" <cmd>`, which commits only if the producer exits 0. In `producer | atomic_state_write` the pipeline's rc is the helper's, so a producer that dies mid-stream lands a truncated payload at rc 0. Reserve the heredoc form above for content written literally in the call.

**Why.** The helper does tmp + fsync + rename; a direct write truncates-and-rewrites, so a reader hitting that window sees a partial file.

**What enforces it.** The `enforce-state-helper` PreToolUse hook hard-blocks `Edit`/`Write`/`MultiEdit`/`NotebookEdit` on a state path — it reads `file_path`, a declared target it cannot misread. Its exemptions are encoded in the hook (dot-prefixed T1 scratch, `.geniro/state/tdd/`); a path it blocks is a path that needs the helper, not one that needs a workaround.

**Shell-side writes are on you.** The hook does not match `Bash`: a redirection, `tee`, `sed -i`, or an interpreter's `open(p,'w')` into a state path is undetected, and routing it through the helper is a contract you keep rather than one a guard enforces. The Bash branch was removed 2026-08-13 — with no target field to read it guessed one out of the command string, and the guessing blocked a `MIGRATION.md` edit whose prose mentioned a state path and a heredoc fragment that was not a path at all. Across 1,408 sessions it produced compliance under a third of the time; the rest was a near-identical retry or a workaround. An undetectable write beats a guard that blocks the wrong ones.

Do not restate tier facts in this file — the copy drifts. Tier model, per-tier frontmatter, the terminal-exit cleanup contract, and the TDD carve-out are canonical in `skills/_shared/state-tier-spec.md`. Helper exit codes and the optimistic mtime-check pattern: `atomic-state-write.md`. Validator exit codes and the recovery prompt when validation fails before a resume: `validate-state-file.md`.

## Memory Layers

Every fact the plugin itself persists lives in exactly one of four layers. Writers know **what** to record and **where**; readers know **which layer** answers a question.

| Layer | Name | Lifespan | Routing rule (writer intent → layer) | Path |
|-------|------|----------|---------------------------------------|------|
| **L1** | Working | Per-task | "Right now, phase X of task Y is running." | `.geniro/planning/<task-dir>/state.md` |
| **L2** | Episodic | Append-only event log | "In this run we observed event X." | `.geniro/knowledge/learnings.jsonl` |
| **L3** | Semantic | Current-state snapshot | "In this project, fact X is currently true." | `.geniro/planning/_*.md` |
| **L4** | Procedural | Stable rules | "When doing X, always do Y." | `.geniro/instructions/*.md` |

**Not a layer — Claude Code's native auto-memory.** A fifth store exists, and `/geniro:reflect` deliberately routes collaboration preferences to it. It is not a substitute for any layer above and does not subsume them: it is per-user and orchestrator-only — never committed, never shared with teammates, and unreadable by any spawned subagent. L4 is the committed team-shared rules layer; L2/L3 are shell-queryable, so a subagent can read them.

**Cross-layer precedence (when layers disagree): L4 > L3 > L2.** L1 is task-scoped and never conflicts cross-layer.

**Within-layer:** recency wins. L2 uses the `supersedes` chain. L3 uses fingerprint refresh / file mtime. L4 uses file mtime.

Per-helper API contracts (`emit-learning`, `query-learnings`, `load-semantic`, `update-semantic`, `archive-stale`, `redact-secrets`, `emit-rejection`) each live in `skills/_shared/<helper>.md`; the loaders are `load-custom-instructions.md` and `subagent-instruction-load.md`, and the alternate L2 backend is `memory-backend.md`. When a loader detects layers disagreeing, the notice format and the halt-and-ask template are in `skills/_shared/resolve-conflicts.md`.

## Editing plugin content — full reads, not grep

When the user asks to improve, review, or modify this plugin's skills/agents/rules, load the relevant files in FULL first by running:

```bash
scripts/dump-md.sh [path ...]   # e.g. scripts/dump-md.sh skills/implement skills/_shared
```

It prints every tracked `.md` file under the given paths (whole repo when no path) as a `===== <path> =====` header followed by the file's complete content. Do this BEFORE reaching for Grep: keyword search shows matching lines only, which misses reworded coverage of the same concept and produces false "missing" findings when auditing or extending skills. Grep stays fine for pinpointing an exact known string (an edit anchor, a cross-reference check) — not for surveying what a skill covers. Subagents doing gap analysis or skill edits get the same instruction: read full files, not grep hits.

Before adding text meant to make a run catch or decide more, read `.claude/rules/skill-prose.md` §"What adding instructions buys" — measured on this repo, that lever is close to inert, and the section names what to reach for instead.

Every improvement pass also SUBTRACTS: apply `.claude/rules/skill-prose.md` §"Assume a capable model" to the sections touched — remove over-detailed mechanics the model derives itself (platform command recipes, shell hand-holding, chewed-up substeps); excess detail primes the wrong mechanism and confuses runs. Improving a module means leaving it leaner than found, not only longer. Editing a rule file itself carries the same discipline one level up — the rule ships, the case for it does not: `.claude/rules/rule-writing.md`.

## Testing & CI

```bash
bash tests/run-all.sh                 # every tests/**/*.sh suite
bash tests/authoring/lint-skills.sh   # authoring lint (hard failures + advisory warnings)
```

`.github/workflows/ci.yml` runs `tests/run-all.sh` plus ShellCheck on every pull request and on pushes to `main`.

## Where the rest lives

| Topic | File |
|---|---|
| Safety hooks — what each one blocks, every bypass pattern ID, `.geniro/safety.json` | `HOOKS.md` |
| Design decisions, subagent model tiering, optional MCP companions, the Cursor runtime port | `ARCHITECTURE.md` |
| Skill catalogue — full descriptions, every flag, the deleted skills and their replacements | `README.md` |
| Breaking changes and the per-entry upgrade walk | `MIGRATION.md` |
| Agent spawn ladder (`geniro:<agent>` → bare → `general-purpose` + inlined body) | `skills/_shared/spawn-agent.md` |
| Authoring rules for skills and agents (voice, structure, what never ships) | `.claude/rules/*.md` — path-scoped, so they load when you touch a skill or agent file |
