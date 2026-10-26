# Load custom instructions (canonical, shared)

## Contents

- §Why this exists — a helper call names the files, the Reads load them
- §When to invoke — initial-load / refresh modes
- §Caller contract — SKILL_SLUG / LOAD_TIER / MODE parameters
- §Procedure — run the helper, Read every listed path, apply the content
- §Echo contract — the line the helper prints per file (incl. additional-step anchor naming, external-dir success + bad-pointer caveat)
- §Mid-pipeline refresh — phase-boundary re-run
- §Producer contract — instruction-file schema the loader applies
- §Anti-rationalization
- §Definition of Done

**Status:** Authoritative for loading and refreshing `global.md`, `memory.md`, `<SKILL_SLUG>.md`, and `code-style.md` — from the in-repo `.geniro/instructions/` by default, or from an external base dir when `$GENIRO_INSTRUCTIONS_DIR` / the plugin's `instructions_dir` install option is configured.

## Why this exists

A natural-language "Load X" directive does not reliably trigger an actual file read — the model often treats it as already-satisfied and skips it — and an echo line the run must compose itself goes unwritten just as often. `lib/load-custom-instructions.sh` closes both mechanically: one shell call prints the echo lines and the exact paths to Read, so the run Reads what the output names. Consumers reference this file by path instead of each restating the directive in prose that drifts apart.

## When to invoke

Three modes:

1. **`MODE: initial-load` — the first action of the skill's own work, run once BEFORE any phase work; a skill that asks the workspace question runs it after that pick, which decides the tree it reads (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-chooser.md` §6).** Where the load site lives inside a phase body, reading that body necessarily precedes the load and does not violate this — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` orders the phase Read ahead of the phase's steps and leaves this load first among them. Default label is `**Step 0 — Load custom instructions.**`; when the consumer's Step 0 is already taken (e.g. a complexity gate), use a distinct first-action label such as `**Load custom instructions (first action — runs before any Phase 1 step).**`. The rule is "physically first action", not "labeled Step 0". A consumer whose first load site prescribes `MODE: refresh` is invoking the phase-boundary contract below at its Phase 1 entry.
2. **`MODE: refresh` — phase-boundary re-run.** Runs at each refresh site the consumer prescribes. Compaction between the initial load and the current phase may have silently dropped the rules; running the helper again is the only durable mitigation.
3. **NOT invoked for** surgical single-rule extraction — that's a different contract from load-and-apply.

## Caller contract

Callers provide three parameters in the call site:

- **`SKILL_SLUG`** — kebab-case name of the invoking skill (e.g. `implement`, `debug`, `actions`). Used to compute the per-skill file path `.geniro/instructions/<SKILL_SLUG>.md`.
- **`LOAD_TIER`** — one of (each skill's own load site declares its tier — grep `LOAD_TIER: pipeline` / `LOAD_TIER: rules-only` across `${CLAUDE_PLUGIN_ROOT}/skills/**/*.md` for the current membership rather than reading it off these lists; several skills declare it only in a phase body file, not `SKILL.md`):
 - `pipeline` → loads `global.md` + `memory.md` + `<SKILL_SLUG>.md` + `code-style.md`. For any skill whose agents read, write, or save to the user's tree (code, CLAUDE.md, ADRs) — the per-skill and code-style layers apply because their output has to honor project rules. A discovery skill (no code writes) still takes `pipeline` when it writes to the user's tree or emits a learning from it, e.g. `onboard` / `investigate`.
 - `rules-only` → loads `global.md` + `memory.md`. For operational/CRUD-on-meta skills that manage rules or plugin state rather than produce code, so the per-skill + code-style layers don't apply; `memory.md` still loads because some of them emit L2 learnings and must honor a declared memory backend.
- **`MODE`** — `initial-load` (Step 0) or `refresh` (phase boundary); it governs when a caller runs the load, and the helper takes no MODE argument.

Callers receive (on completion):

- One echo line per file in the load set, in the helper's output (per §Echo contract), and the content of every listed file, through the Reads
- The loaded rules / constraints / additional-steps applied as standing context for the rest of the run

## Procedure

Run the helper in one shell call:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/load-custom-instructions.sh" && load_custom_instructions <SKILL_SLUG> <LOAD_TIER>
```

The helper prints one echo line per file in the load set, then a `Read: <absolute path>` line per file found. Read every listed path in one response, before applying anything — the content enters context through those Reads, and a listed file never Read is not loaded. A call-site instruction to read, re-read, or echo the instruction files means this helper call plus those Reads. Leave the echo lines as printed, never retyped or recounted by hand.

The helper loads `pipeline` → `[global.md, memory.md, <SKILL_SLUG>.md, code-style.md]` in that order and `rules-only` → `[global.md, memory.md]`, from one base directory:

- **External dir.** `$GENIRO_INSTRUCTIONS_DIR`, then `$CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR` (set by Claude Code from the plugin's `instructions_dir` install option), a leading `~` expanded to `$HOME`, replaces the repo as a flat layout — `<dir>/<file>`, with no checkout lookup and no primary-worktree fallback, because the override is explicit, not a merge. A configured dir that does not exist prints the bad-pointer caveat and the in-repo default applies.
- **In-repo default.** `.geniro/instructions/<file>` under the checkout root first; only when that lacks the file, the same path under the main worktree (`PRIMARY_ROOT`, resolved once per call). The fallback covers a linked worktree whose checkout lacks the gitignored authored files, and a branch created before they were added.

A missing file is a skip and an unreadable one a reported failure (`Failed to load`); neither halts the consumer, and the helper exits 0 either way.

Apply the loaded content:

- `## Rules` → standing rules active in every phase of the consumer skill, binding the orchestrator's own actions there too, not only the subagent prompts it builds — a declared search policy governs every lookup for the rest of the run, not just the first
- `## Constraints` → a flat bullet list of hard gates, evaluated globally (or at a phase boundary when a bullet's text names one) — not organized into per-phase subsections; only `## Additional Steps` uses named-phase subsections
- `## Additional Steps` → extra steps inserted at the named phase boundary, via the `### After <phase name>` form (if the skill has that phase; otherwise apply where they fit and skip the rest). `### After <phase name>` is the only form a consumer reads — a `### Before <phase name>` subsection has no read site in any skill, which is why `/geniro:instructions` rejects it at authoring time. The one event (non-phase) anchor is `### After worktree-setup` in `global.md` — a cross-skill step run right after a new worktree is created and before subagent fan-out (execution sites: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` §3, `/geniro:debug` Step 0.2's worktree pick, and `/geniro:review` triage), and also once before the run's first subagent fan-out when the run starts inside an existing linked worktree and creates none itself (`/geniro:investigate` Phase 2; run-twice-safe per branch-freshness §3.1); resolve `global.md` through the primary-worktree fallback, because a fresh linked worktree does not carry the gitignored authored file.
- `## Data Sources` → read-only sources to cross-check load-bearing facts against, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md`; absent = no declared sources
- `## Verification Surface` → what each of the project's checks covers and leaves uncovered, consulted when the run picks which check demonstrates a criterion and when it states the result — the uncovered half bounds how wide the claim may be stated, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` §Forbidden phrases; absent = no declared mapping
- `## Memory Backend` → routes L2 learnings through a project-declared backend at the `emit-learning` / `query-learnings` call-sites, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md`; absent = built-in `.geniro/knowledge/learnings.jsonl` file, unchanged

## Echo contract

The helper prints exactly one line per file in the load set. Counts are `lib/instruction-counts.sh`'s output for the exact file listed for Reading.

Four success/skip formats, one failure, one caveat:

- **Found in the checkout root:** `Loaded <filename> (<N> rules, <M> constraints[, <A> additional step(s): <anchor1>[, <anchor2>...]][, <D> data sources]).`
- **Found via the primary-worktree fallback:** `Loaded <filename> from primary worktree (<N> rules, <M> constraints[, <A> additional step(s): <anchor1>[, ...]][, <D> data sources]).`
- **Found in the external instructions dir:** `Loaded <filename> from external instructions dir (<N> rules, <M> constraints[, <A> additional step(s): <anchor1>[, ...]][, <D> data sources]).`
- **Not found** (checkout root and fallback, or the external dir): `No <filename> found — skipping.`
- **Unreadable** (a directory, permission denied): `Failed to load <filename>: <reason> — skipping.` It is never listed.
- **Bad-pointer caveat** (printed once, before the first file): `External instructions dir <path> not found — using in-repo instructions.`

Examples (verbatim):

```
Loaded global.md (3 rules, 2 constraints).
Loaded global.md (3 rules, 2 constraints, 2 data sources).
Loaded implement.md (2 rules, 1 constraint, 1 additional step: After ship).
Loaded plan.md (1 rule, 0 constraints, 2 additional steps: After explore, After user-approve).
Loaded implement.md from primary worktree (2 rules, 1 constraint).
Loaded code-style.md from external instructions dir (4 rules, 1 constraint).
Loaded memory.md (memory backend: learnings → mirror).
External instructions dir /opt/geniro-rules not found — using in-repo instructions.
No code-style.md found — skipping.
No memory.md found — skipping.
Failed to load debug.md: permission denied — skipping.
Read: /repo/.geniro/instructions/global.md
```

A file with zero rules or constraints prints the literal `0`. `, <D> data sources` appears only when the file has `## Data Sources` entries. `, <A> additional step(s): <anchors>` appears only when `## Additional Steps` holds at least one `### After <phase>` or `### Before <phase>` subsection with content, each named as authored — a `### Before <phase>` block is parsed but never read, and a phase name no skill reads (an authoring typo, or a dropped phase) shows up here as unfamiliar instead of staying invisible until the boundary it names never fires. When the counters fail on a readable file, `counts unavailable: <reason>` replaces the counts and the file is still listed: Read it.

**`memory.md` is the exception to the rules/constraints parenthetical** — it carries the `## Memory Backend` block, not rules or constraints, so its success echo names the routed layer + mode instead: `Loaded memory.md (memory backend: <layer> → <mode>).` (the fallback / external-dir variants apply identically). When `memory.md` exists but declares no `## Memory Backend` entry, the echo is `Loaded memory.md (no memory backend declared).`; when absent, `No memory.md found — skipping.`

## Mid-pipeline refresh

At a phase boundary that prescribes a refresh, the consumer re-invokes this helper with `MODE: refresh` and the `SKILL_SLUG` and `LOAD_TIER` it used at Step 0. Compaction since the initial load may already have dropped the rules, so a refresh is procedurally identical to the initial load: run the helper again and Read every path it lists again. An earlier load never satisfies a refresh.

Canonical refresh-site wording at consumer sites:

> **Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: <slug>`, `LOAD_TIER: <tier>`, `MODE: refresh`. Compaction since the previous load may have silently dropped the rules — re-Read all files and echo per the helper's contract.

Do NOT write "since Phase 1" at refresh sites — the initial load isn't always at Phase 1, so a refresh site further into the run would state the wrong anchor. **"Since the previous load"** is the canonical, anchor-free phrasing.

## Producer contract

The four files this helper loads (`global.md`, `memory.md`, `<SKILL_SLUG>.md`, `code-style.md`) have the fixed schema below, canonical here — this is their runtime reader, so the schema the reader applies is the one that is real; an authoring-side schema the loader does not apply is dead. The `/geniro:instructions` CRUD skill authors against it. (Custom-reviewer files under `review-extra/` are a different shape with their own reader — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md`.)

```markdown
# Custom Instructions

## Rules
- Single-line constraints applied throughout the run

## Additional Steps
### After <phase name>
<!-- Steps to run after the named phase -->

## Constraints
- Hard limits enforced as gates

## Data Sources
- **label** (confirms: <fact kind>) — read-only source (shell command / MCP tool / action)

## Verification Surface
- `<check command>` — covers: <ground the check demonstrates>. Does not cover: <ground it leaves unproven>
```

`## Data Sources` and `## Verification Surface` are optional and `global.md`-or-per-skill-scoped; `## Rules` / `## Constraints` / `## Additional Steps` appear in `global.md` and per-skill files. The `## Memory Backend` block lives in its own dedicated `memory.md` file (loaded alongside `global.md` by every consumer):

```markdown
# Memory

## Memory Backend
- layer: learnings   # mode: mirror|replace; write: <mcp tool>; read: <read-only mcp tool>
```

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I already know the rules from a previous turn — skip the helper." | Compaction may have silently dropped them, and the user may have edited the file mid-session via `/geniro:instructions edit`. Only a fresh helper call and Reads reflect the files now; in-memory context does not. |
| "I'll always read from `PRIMARY_ROOT` directly and skip the checkout copy." | A checkout copy can be a committed branch-local copy — the default `.gitignore` negates `instructions/`, so instruction files may be tracked and legitimately diverge per branch. Checkout-root-first respects that divergence; primary-only reads lose it. The fallback fires ONLY when the checkout misses. |
| "I'll read the files myself and write the echo lines afterwards." | A hand-written echo is the one that goes unwritten — in two real runs it was composed only in hidden reasoning and never reached chat. The helper prints the echo lines and names the paths to Read; a read made without it has no echo. |

## Definition of Done

- [ ] The helper ran in one shell call and every path it listed was Read in one response; a refresh did both again rather than reusing an earlier load
- [ ] Its echo lines, one per file in the load set, stand unedited in the run
- [ ] Every loaded section was applied per §Procedure, `## Additional Steps` anchors included
