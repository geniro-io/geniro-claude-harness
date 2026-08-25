# Load custom instructions (canonical, shared)

## Contents

- §Why this exists — tool-explicit, observable, canonical load
- §When to invoke — initial-load / refresh modes
- §Caller contract — SKILL_SLUG / LOAD_TIER / MODE parameters
- §Procedure — load set, external-dir override, primary-worktree fallback, per-file reads
- §Echo contract — the one-line-per-file proof of read (incl. external-dir success + bad-pointer caveat)
- §Mid-pipeline refresh — phase-boundary re-read
- §Producer contract — instruction-file schema the loader applies
- §Anti-rationalization
- §Definition of Done

**Status:** Authoritative for loading and refreshing `global.md`, `memory.md`, `<SKILL_SLUG>.md`, and `code-style.md` — from the in-repo `.geniro/instructions/` by default, or from an external base dir when `$GENIRO_INSTRUCTIONS_DIR` / the plugin's `instructions_dir` install option is configured.

## Why this exists

A natural-language "Load X" directive does not reliably trigger an actual file read — the model often treats it as already-satisfied and skips the actual file read. Defining the load procedure once here, in tool-explicit terms, is the durable fix: consumers reference this file by path instead of each restating the directive in prose that drifts apart.

## When to invoke

Three modes:

1. **`MODE: initial-load` — for a consumer whose first load site prescribes it, the first action of the skill's own work.** Runs once at skill start, BEFORE any phase work. Where the load site itself lives inside a phase body, reading that body necessarily precedes the load and does not violate this — see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`, which orders the phase Read ahead of the phase's steps and leaves this load first among them. Default label is `**Step 0 — Load custom instructions.**`. When the "Step 0" label is already used for a different purpose in the consumer (e.g. a consumer whose Step 0 is a complexity gate), use a distinct first-action label instead — e.g. `**Load custom instructions (first action — runs before any Phase 1 step).**`. The rule is "physically first action", not "labeled Step 0" — check the consumer's own load-site wording rather than assuming every skill uses `initial-load`; a consumer whose first load site instead prescribes `MODE: refresh` is invoking the phase-boundary contract below at its Phase 1 entry.
2. **`MODE: refresh` — phase-boundary re-read.** Runs at each refresh site the consumer prescribes. Compaction between the initial load and the current phase may have silently dropped the rules; the explicit re-Read is the only durable mitigation.
3. **NOT invoked for** surgical single-rule extraction — that's a different contract from load-and-apply.

## Caller contract

Callers provide three parameters in the call site:

- **`SKILL_SLUG`** — kebab-case name of the invoking skill (e.g. `implement`, `debug`, `actions`). Used to compute the per-skill file path `.geniro/instructions/<SKILL_SLUG>.md`.
- **`LOAD_TIER`** — one of:
 - `pipeline` → loads `global.md` + `memory.md` + `<SKILL_SLUG>.md` + `code-style.md`. For any skill whose agents read, write, or save to the user's tree (code, CLAUDE.md, ADRs) — the per-skill and code-style layers apply because their output has to honor project rules. A discovery skill (no code writes) still takes `pipeline` when it writes to the user's tree or emits a learning from it, e.g. `onboard` / `investigate`. The skill's own load site declares its tier — grep `LOAD_TIER: pipeline` across `skills/**/*.md` for the current membership rather than reading it off this list (several skills declare it only in a phase body file, not `SKILL.md`).
 - `rules-only` → loads `global.md` + `memory.md`. For operational/CRUD-on-meta skills that manage rules or plugin state rather than produce code, so the per-skill + code-style layers don't apply; `memory.md` still loads because some of them emit L2 learnings and must honor a declared memory backend. The skill's own load site declares its tier — grep `LOAD_TIER: rules-only` across `skills/**/*.md` for the current membership rather than reading it off this list (several skills declare it only in a phase body file, not `SKILL.md`).
- **`MODE`** — `initial-load` (Step 0) or `refresh` (phase boundary).

Callers receive (on completion):

- An observable echo line printed per file (per §Echo contract)
- The loaded rules / constraints / additional-steps applied as standing context for the rest of the run

## Procedure

Compute the load set from `LOAD_TIER`:

- `pipeline` → `[global.md, memory.md, <SKILL_SLUG>.md, code-style.md]` (four files, in that order)
- `rules-only` → `[global.md, memory.md]` (two files)

**Resolve the instructions base directory once, before the load loop.** An external override lets the instruction files live OUTSIDE the repo (e.g. a clean fresh-clone environment where `.geniro/instructions/` is not committed). In a shell call, resolve `EXTERNAL_DIR` with precedence `$GENIRO_INSTRUCTIONS_DIR` (manual/automation override), then `$CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR` (set by Claude Code from the plugin's `instructions_dir` install option), expanding a leading `~` to `$HOME` — empty when neither is set, meaning the in-repo default applies. A configured-but-missing directory fails open: emit `External instructions dir <path> not found — using in-repo instructions.` (the §Echo contract caveat) and fall back to the in-repo default.

This inline resolution mirrors `_geniro_instructions_dir()` in `lib/repo-root.sh` — the two live in different execution worlds (orchestrator-Bash here, hook-shell there) but must stay in lockstep, the same rationale as the primary-worktree Mode A snippet inlined below vs `repo-root.sh`. Inlining the logic here (rather than sourcing a `lib/` helper) keeps the loader self-contained for vendored installs that lack `lib/`.

When `EXTERNAL_DIR` is non-empty, the load set reads from it as a flat layout — `<EXTERNAL_DIR>/<file>`, with no `.geniro/instructions/` suffix — and the `PRIMARY_ROOT` resolution + cwd-first fallback below are skipped entirely (the external dir is an explicit override, not a merge). Resolve `PRIMARY_ROOT` and use the cwd-first fallback ONLY when `EXTERNAL_DIR` is empty (no external dir active, or a configured one was missing and already failed open).

**Resolve `PRIMARY_ROOT` once, before the load loop.** Run the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` in a shell call to compute the fallback location. When cwd is the main worktree (or the project isn't a git repo), `PRIMARY_ROOT="."` and the fallback is a no-op. When cwd is a linked worktree, `PRIMARY_ROOT` is the main worktree's absolute path. This handles two real failure modes: (a) `$ARGUMENTS` runs in `.claude/worktrees/<dir>/` where the branch checkout doesn't have instructions committed; (b) the current branch was created before `.geniro/instructions/*` was added on trunk, so the cwd checkout is stale relative to the user's latest authored rules.

For each file in the load set, in order:

1. Call the **Read** tool on the file:
 - **External dir active (`EXTERNAL_DIR` non-empty):** Read `<EXTERNAL_DIR>/<file>` (flat layout per the base-dir resolution above — no fallback in external mode; step 2a does not apply).
 - **In-repo (no external dir):** Read `.geniro/instructions/<file>` (cwd-relative) — the cwd-first / `PRIMARY_ROOT`-fallback behavior. A configured-but-missing external dir already failed open (the probe emitted the caveat), so the loop runs here in in-repo mode.
2. **If Read succeeds:** run `${CLAUDE_PLUGIN_ROOT}/lib/instruction-counts.sh` in a shell call against the exact path the Read just opened — `<EXTERNAL_DIR>/<file>` in external-dir mode, `.geniro/instructions/<file>` in-repo — for its N/M/D echo counts. The helper returns a nonzero exit when it cannot open that path (a stale variable, a race since the Read succeeded); treat that as a step 3a load failure rather than echoing a zero count — a zero is a real result for a file with no bullets under a section, and echoing one for a path the helper never actually read reports a confident wrong number instead of a visible failure. On a zero exit, record its `## Data Sources` entries (each source's label and what it confirms, when the section is present); record its `## Additional Steps` subsections (each named after a phase boundary); record its `## Verification Surface` entries (per check, the covers and does-not-cover clauses, when the section is present); record its `## Memory Backend` block (the per-layer `mode`/`write`/`read` entries, when present — `memory.md` only). Skip step 2a.
2a. **If Read errors with file-not-found AND no external dir is active AND `PRIMARY_ROOT` differs from cwd:** retry the Read against the absolute path `<PRIMARY_ROOT>/.geniro/instructions/<file>`. If the second Read succeeds, run the helper against that same `<PRIMARY_ROOT>/.geniro/instructions/<file>` path and record the rest as in step 2, AND remember that the fallback fired (the §Echo contract emits a distinct line). If the second Read also fails with file-not-found, fall through to step 3.
3. **If file is still not found** (cwd missing AND fallback missing or unavailable): treat as a silent skip — no error, no warning, just the missing-file echo line.
3a. **If a Read errors with any other error** (permission denied, path-is-a-directory, encoding error) **or step 2's counting helper exits nonzero on a Read that did succeed:** echo `Failed to load <filename>: <one-line-error-summary> — skipping.` and continue. Do not halt the consumer skill.
4. After the Read attempt(s) (success OR file-not-found), print one echo line per §Echo contract.
5. Apply the loaded content:
 - `## Rules` → standing rules active in every phase of the consumer skill, binding the orchestrator's own actions there too, not only the subagent prompts it builds — a declared search policy governs every lookup for the rest of the run, not just the first
 - `## Constraints` → a flat bullet list of hard gates, evaluated globally (or at a phase boundary when a bullet's text names one) — not organized into per-phase subsections; only `## Additional Steps` uses named-phase subsections
 - `## Additional Steps` → extra steps inserted at the named phase boundary, via the `### After <phase name>` form (if the skill has that phase; otherwise apply where they fit and skip the rest)
 - `## Data Sources` → read-only sources to cross-check load-bearing facts against, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md`; absent = no declared sources
 - `## Verification Surface` → what each of the project's checks covers and leaves uncovered, consulted when the run picks which check demonstrates a criterion and when it states the result; absent = no declared mapping
 - `## Memory Backend` → routes L2 learnings through a project-declared backend at the `emit-learning` / `query-learnings` call-sites, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md`; absent = built-in `.geniro/knowledge/learnings.jsonl` file, unchanged

## Echo contract

After each Read attempt (or sequence of attempts including the primary-worktree fallback), print exactly one line to the user — non-negotiable. The echo is the user-visible proof that the Read fired, and its `<N>`/`<M>`/`<D>` counts are `lib/instruction-counts.sh`'s output for the exact path that Read opened, never tallied by eye — a silent Read is indistinguishable from a skipped one, and a miscounted echo is indistinguishable from a correct one.

Four success/skip formats plus one caveat:

- **On Read success (cwd):** `Loaded <filename> (<N> rules, <M> constraints[, <D> data sources]).`
- **On Read success (primary-worktree fallback fired):** `Loaded <filename> from primary worktree (<N> rules, <M> constraints[, <D> data sources]).` — signals to the user that cwd is stale relative to the main worktree's checkout.
- **On Read success (external instructions dir active):** `Loaded <filename> from external instructions dir (<N> rules, <M> constraints[, <D> data sources]).` — signals the file came from the configured external base dir, not the repo.
- **On file-not-found (both cwd and fallback, or fallback unavailable):** `No <filename> found — skipping.`
- **Bad-pointer caveat (emitted once, by the base-dir probe, before the in-repo fallback loop runs):** `External instructions dir <path> not found — using in-repo instructions.`

Examples (verbatim):

```
Loaded global.md (3 rules, 2 constraints).
Loaded global.md (3 rules, 2 constraints, 2 data sources).
Loaded implement.md from primary worktree (2 rules, 1 constraint).
Loaded code-style.md from external instructions dir (4 rules, 1 constraint).
Loaded memory.md (memory backend: learnings → mirror).
External instructions dir /opt/geniro-rules not found — using in-repo instructions.
No code-style.md found — skipping.
No memory.md found — skipping.
```

If a file has zero rules or zero constraints, still emit the line with the literal `0` count. Do NOT abbreviate to `Loaded global.md.` — always include the rules + constraints parenthetical. Append `, <D> data sources` to the parenthetical only when the file carries a `## Data Sources` block (it is optional, unlike rules/constraints — omit the clause entirely when the block is absent).

**`memory.md` is the exception to the rules/constraints parenthetical** — it carries the `## Memory Backend` block, not rules or constraints, so its success echo names the routed layer + mode instead: `Loaded memory.md (memory backend: <layer> → <mode>).` (the fallback / external-dir variants apply identically). When `memory.md` exists but declares no `## Memory Backend` block, echo `Loaded memory.md (no memory backend declared).`; when absent, `No memory.md found — skipping.`

## Mid-pipeline refresh

When a consumer reaches a phase boundary that prescribes a refresh (every refresh site in the codebase is named explicitly in the consumer's phases — typically after each major phase that consumes meaningful context), the consumer re-invokes this helper with `MODE: refresh` and the same `SKILL_SLUG` and `LOAD_TIER` it used at Step 0. Compaction between the initial load and that boundary may already have dropped the rules from context, so the refresh is procedurally identical to the initial load — every Read fires again, every echo line prints again.

Canonical refresh-site wording at consumer sites:

> **Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: <slug>`, `LOAD_TIER: <tier>`, `MODE: refresh`. Compaction since the previous load may have silently dropped the rules — re-Read all files and echo per the helper's contract.

Do NOT write "since Phase 1" at refresh sites. Some skills (e.g. `debug`) use step-numbering instead of phase-numbering, and "since Phase 1" leaks the wrong terminology into skills that don't have a Phase 1. **"Since the previous load"** is the canonical, anchor-free phrasing.

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

The loader applies these as:

- **Rules → standing rules.** Active in every phase of the consumer skill until the run ends, binding the orchestrator's own actions there too, not only the subagent prompts it builds — a declared search policy governs every lookup for the rest of the run, not just the first.
- **Constraints → hard gates.** A flat bullet list, evaluated globally (or at a phase boundary when a bullet names one). Only `## Additional Steps` uses named-phase subsections.
- **Additional Steps → extra steps inserted at the named phase boundary.** The `### After <phase name>` form is the only one a consumer reads — a `### Before <phase name>` subsection has no read site in any skill, which is why `/geniro:instructions` rejects it at authoring time rather than letting it parse as legal and never run. If the per-skill file declares an Additional Step for a phase that doesn't exist in the consumer (e.g. `debug` has no PHASE 1 — it has step 1 / Observe), apply where it fits and skip the rest. The one event (non-phase) anchor is `### After worktree-setup` in `global.md` — a cross-skill step run right after a new worktree is created and before subagent fan-out (execution sites: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` §3 and `/geniro:review` triage). Resolve `global.md` through the primary-worktree fallback above — a fresh linked worktree does not carry the gitignored authored file, so a cwd-only Read would miss it.
- **Data Sources → read-only fact-verification sources** consulted wherever a skill phase establishes a load-bearing fact, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md`.
- **Verification Surface → what each project check covers, and what it does not.** Consulted where a run selects the check that demonstrates a given criterion, and where it words the result — the uncovered half bounds how wide the claim may be stated, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md` §Forbidden phrases. Absent means no declared mapping and nothing changes.
- **Memory Backend → L2-learnings routing** applied at the `emit-learning` / `query-learnings` call-sites per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/memory-backend.md`.

Consumer SKILL.md files must not duplicate this Rules/Steps/Constraints semantics in their own text. That phrase migrates entirely into this helper; consumer call sites say only "Apply this helper, echo per contract" — nothing more.

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I already know the rules from a previous turn — skip the Read." | Compaction may have silently dropped them. The Read survives compaction; the in-memory context doesn't. |
| "The file probably hasn't changed since the last load — skip." | The user may have edited it mid-session via `/geniro:instructions edit`. The Read is the only source of truth. |
| "I'll skip the echo to save tokens." | The echo is the user-visible proof the Read fired. A silent load is indistinguishable from a skipped load. No exceptions. |
| "This skill doesn't write code, so `code-style.md` doesn't apply — skip it even though `LOAD_TIER: pipeline`." | The `LOAD_TIER` field is the contract — `rules-only` consumers don't request `code-style.md` and the helper handles it. Do not make ad-hoc skip decisions per turn. |
| "I'll batch the Reads into a Glob to save a tool call." | Glob doesn't ingest content. The Read content is what applies — Glob alone won't trigger application. |
| "The file doesn't exist on this project — error out." | File-not-found is the silent-skip case. Print the "No `<name>` found — skipping." echo and continue. |
| "The counting helper failed but the Read succeeded — I'll echo 0 rules, 0 constraints and move on." | A nonzero exit from `lib/instruction-counts.sh` means it couldn't open the path Read just opened, not that the file has no bullets. Echoing zero counts there reports a confident wrong number as the user's only evidence the file loaded — worse than the by-eye miscount this helper replaced. Route it through the step 3a failure echo instead. |
| "The echo line is informational; I can drop it if the project has no instructions." | Then the user can't distinguish a missing file from a skipped Read. Always echo, even on skip. |
| "Refresh wording from old code says 'since Phase 1' — I'll keep it." | Some skills (debug) have no Phase 1. "Since the previous load" is the canonical anchor-free wording — update on contact. |
| "Cwd Read returned file-not-found — skip straight to the missing-file echo." | The user may have authored instructions on the main worktree's branch while the current cwd is a stale feature branch or a linked worktree. Always try the `PRIMARY_ROOT` fallback before echoing `No <filename> found` — that's the durability contract. |
| "I'll always read from `PRIMARY_ROOT` directly and skip the cwd Read." | A cwd copy can be a committed branch-local copy — the default `.gitignore` negates `instructions/`, so instruction files may be tracked and legitimately diverge per branch. Cwd-first respects that divergence; primary-only reads lose it. The fallback fires ONLY when cwd misses. |
| "An external instructions dir is set, so I'll merge it with the cwd `.geniro/instructions/` too." | The external dir is an explicit override, not a merge. When it's active and valid, read only from it — the cwd and primary-worktree fallbacks are skipped. Merging would resurrect stale in-repo rules the user meant to replace. |
| "The configured external dir path doesn't exist, so I'll just load nothing and move on." | A bad pointer must be visible, not silent. Emit the `External instructions dir <path> not found — using in-repo instructions.` caveat and fall back to the in-repo default — silently loading zero rules hides a typo'd path. |

## Definition of Done

- [ ] The instructions base directory is resolved once per invocation before the load loop (external override `$GENIRO_INSTRUCTIONS_DIR` > `$CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR` > in-repo default), with a leading `~` expanded to an absolute path
- [ ] When an external instructions dir is configured and valid, every file loads from it and the cwd/`PRIMARY_ROOT` fallbacks are skipped; a configured-but-missing dir fails open to in-repo with the §Echo-contract caveat
- [ ] When cwd Read returns file-not-found AND `PRIMARY_ROOT` differs from cwd, a fallback Read against `<PRIMARY_ROOT>/.geniro/instructions/<file>` is attempted before the "No `<name>` found" echo
- [ ] Every Read emits exactly one echo line per §Echo contract (cwd success / primary-worktree success / not-found)
- [ ] A nonzero exit from the counting helper on a path Read just opened is echoed as a step 3a load failure, never as a zero-count success
