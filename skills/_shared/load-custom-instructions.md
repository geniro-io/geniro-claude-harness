# Load custom instructions (canonical, shared)

**Status:** Authoritative for loading and refreshing `.geniro/instructions/global.md`, `.geniro/instructions/<SKILL_SLUG>.md`, and `.geniro/instructions/code-style.md` in any Geniro skill that ingests user-authored rules. Every consumer calls this helper at Step 0 (initial load) and at each phase-boundary refresh site.

## Why this exists

Pre-helper, every consumer SKILL.md duplicated the producer-side directive prose: *"Load custom instructions from `.geniro/instructions/global.md` and `.geniro/instructions/<skill>.md`. Read any found. Apply rules as constraints, additional steps at specified phases, and hard constraints."* Across 12 skills + 13 mid-pipeline refresh sites this produced three phrasings (brace-expansion, comma-separated, hook prose) that drifted independently. Worse, the natural-language "Load X" directive empirically did NOT reliably trigger the Read tool — documented as a failure mode in Anthropic's own Memory docs and Claude Code issue #27032, and reproduced in Spec Kit issue #2459 ("`/speckit.implement` does not load constitution.md"). This helper makes the load:

- **Tool-explicit** — imperative `` Read `<path>` `` directives, not "Load X if present"
- **Observable** — a one-line echo after every Read, so the user can SEE that the read fired
- **Canonical** — defined once here; consumers reference by path, never duplicate the prose
- **Anti-rationalization-guarded** — known skip rationalizations (e.g. "I already know the rules from memory") flagged in the table below

## When to invoke

Three modes:

1. **`MODE: initial-load` — the physically-first action of every consumer skill that ingests instructions.** Runs once at skill start, BEFORE any phase work. Default label is `**Step 0 — Load custom instructions.**`. When the "Step 0" label is already used for a different purpose in the consumer (e.g. `implement`'s pre-existing "Step 0 — Complexity Gate (Lane Selection)"), use a distinct first-action label instead — e.g. `**Load custom instructions (first action — runs before any Phase 1 step).**`. The rule is "physically first action", not "labeled Step 0".
2. **`MODE: refresh` — phase-boundary re-read.** Runs at each refresh site the consumer prescribes. Compaction between the initial load and the current phase may have silently dropped the rules; the explicit re-Read is the only durable mitigation.
3. **NOT invoked by** `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md` — that helper does surgical extraction of one specific rule (branch-naming), not load-and-apply. Different contract.

## Caller contract

Callers provide three parameters in the call site:

- **`SKILL_SLUG`** — kebab-case name of the invoking skill (e.g. `implement`, `debug`, `actions`). Used to compute the per-skill file path `.geniro/instructions/<SKILL_SLUG>.md`.
- **`LOAD_TIER`** — one of:
  - `pipeline` → loads `global.md` + `<SKILL_SLUG>.md` + `code-style.md`. Applies to: `implement` (M4), `plan` (M5), `review` (M6), `debug` (M7), `refactor` (M8), `onboard` (M9), `investigate` (M9). M9 D12-fix promotes `onboard` и `investigate` from `rules-only` к `pipeline` — discovery skills emit к L2/L3 (M2 §5.3 `discovery` rows) и need code-style rules respected when their save-routing focused agents write к the user's tree (CLAUDE.md, ADR, etc.).
  - `rules-only` → loads `global.md` only. Applies to: `actions` (M10), `instructions` (M10), `setup` (M10). These are CRUD-on-meta skills — they manage rules rather than produce code или learnings, so the per-skill + code-style layers don't apply.
- **`MODE`** — `initial-load` (Step 0) or `refresh` (phase boundary).

Callers receive (on completion):

- An observable echo line printed per file (per §Echo contract)
- The loaded rules / constraints / additional-steps applied as standing context for the rest of the run

## Procedure

Compute the load set from `LOAD_TIER`:

- `pipeline` → `[global.md, <SKILL_SLUG>.md, code-style.md]` (three files, in that order)
- `rules-only` → `[global.md]` (one file)

**Resolve `PRIMARY_ROOT` once, before the load loop.** Run the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` via Bash to compute the fallback location. When cwd is the main worktree (or the project isn't a git repo), `PRIMARY_ROOT="."` and the fallback is a no-op. When cwd is a linked worktree, `PRIMARY_ROOT` is the main worktree's absolute path. This handles two real failure modes: (a) `$ARGUMENTS` runs in `.claude/worktrees/<dir>/` where the branch checkout doesn't have instructions committed; (b) the current branch was created before `.geniro/instructions/*` was added on trunk, so the cwd checkout is stale relative to the user's latest authored rules.

For each file in the load set, in order:

1. Call the **Read** tool on `.geniro/instructions/<file>` (cwd-relative).
2. **If Read succeeds:** count its `## Rules` entries (N — bullet lines under that heading) and `## Constraints` entries (M — bullet lines under that heading); record its `## Additional Steps` subsections (each named after a phase boundary). Skip step 2a.
2a. **If Read errors with file-not-found AND `PRIMARY_ROOT` differs from cwd:** retry the Read against the absolute path `<PRIMARY_ROOT>/.geniro/instructions/<file>`. If the second Read succeeds, count entries as in step 2 AND remember that the fallback fired (the §Echo contract emits a distinct line). If the second Read also fails with file-not-found, fall through to step 3.
3. **If file is still not found** (cwd missing AND fallback missing or unavailable): treat as a silent skip — no error, no warning, just the missing-file echo line.
3a. **If any Read errors with any other error** (permission denied, path-is-a-directory, encoding error): echo `Failed to load <filename>: <one-line-error-summary> — skipping.` and continue. Do not halt the consumer skill.
4. After the Read attempt(s) (success OR file-not-found), print exactly one echo line per the §Echo contract — non-negotiable.
5. Apply the loaded content:
   - `## Rules` → standing rules active in every phase of the consumer skill
   - `## Constraints` → hard gates evaluated at the phase boundary named in each subsection (or globally if not phase-scoped)
   - `## Additional Steps` → extra steps inserted at the named phase boundary (if the skill has that phase; otherwise apply where they fit and skip the rest)

## Echo contract

After each Read attempt (or sequence of attempts including the primary-worktree fallback), print exactly one line to the user — non-negotiable. The echo is the user-visible proof that the Read fired. A silent Read is indistinguishable from a skipped Read.

Three formats:

- **On Read success (cwd):** `Loaded <filename> (<N> rules, <M> constraints).`
- **On Read success (primary-worktree fallback fired):** `Loaded <filename> from primary worktree (<N> rules, <M> constraints).` — signals to the user that cwd is stale relative to the main worktree's checkout.
- **On file-not-found (both cwd and fallback, or fallback unavailable):** `No <filename> found — skipping.`

Examples (verbatim):

```
Loaded global.md (3 rules, 2 constraints).
Loaded implement.md from primary worktree (2 rules, 1 constraint).
No code-style.md found — skipping.
```

If a file has zero rules or zero constraints, still emit the line with the literal `0` count. Do NOT abbreviate to `Loaded global.md.` — always include the parenthetical.

## Mid-pipeline refresh

When a consumer reaches a phase boundary that prescribes a refresh (every refresh site in the codebase is named explicitly in the consumer's phases — typically after each major phase that consumes meaningful context), the consumer MUST re-invoke this helper with `MODE: refresh` and the same `SKILL_SLUG` and `LOAD_TIER` it used at Step 0. The refresh is procedurally identical to the initial load — every Read fires again, every echo line prints again.

Canonical refresh-site wording at consumer sites:

> **Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: <slug>`, `LOAD_TIER: <tier>`, `MODE: refresh`. Compaction since the previous load may have silently dropped the rules — re-Read all files and echo per the helper's contract.

Do NOT write "since Phase 1" at refresh sites. Some skills (e.g. `debug`) use step-numbering instead of phase-numbering, and "since Phase 1" leaks the wrong terminology into skills that don't have a Phase 1. **"Since the previous load"** is the canonical, anchor-free phrasing.

## Producer contract

The instruction files this helper loads have a fixed schema (defined authoritatively in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/SKILL.md` § File Structure):

```markdown
# Custom Instructions

## Rules
- Single-line constraints applied throughout the run

## Additional Steps
### After <phase name>
<!-- Steps to run after the named phase -->

## Constraints
- Hard limits enforced as gates
```

The loader applies these as:

- **Rules → standing constraints.** Active in every phase of the consumer skill until the run ends.
- **Constraints → hard gates.** Evaluated at the boundary of the phase named in each subsection, or globally if not phase-scoped.
- **Additional Steps → extra steps inserted at the named phase boundary.** If the per-skill file declares an Additional Step for a phase that doesn't exist in the consumer (e.g. `debug` has no PHASE 1 — it has step 1 / Observe), apply where it fits and skip the rest.

Consumer SKILL.md files MUST NOT duplicate this Rules/Steps/Constraints semantics in their own text. That phrase migrates entirely into this helper; consumer call sites say only "Apply this helper, echo per contract" — nothing more.

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I already know the rules from a previous turn — skip the Read." | Compaction may have silently dropped them. The Read survives compaction; the in-memory context doesn't. |
| "The file probably hasn't changed since the last load — skip." | The user may have edited it mid-session via `/geniro:instructions edit`. The Read is the only source of truth. |
| "I'll skip the echo to save tokens." | The echo is the user-visible proof the Read fired. A silent load is indistinguishable from a skipped load. No exceptions. |
| "This skill doesn't write code, so `code-style.md` doesn't apply — skip it even though `LOAD_TIER: pipeline`." | The `LOAD_TIER` field is the contract — `rules-only` consumers don't request `code-style.md` and the helper handles it. Do not make ad-hoc skip decisions per turn. |
| "I'll batch the three Reads into a Glob to save a tool call." | Glob doesn't ingest content. The Read content is what applies — Glob alone won't trigger application. |
| "The file doesn't exist on this project — error out." | File-not-found is the silent-skip case. Print the "No `<name>` found — skipping." echo and continue. |
| "The echo line is informational; I can drop it if the project has no instructions." | Then the user can't distinguish a missing file from a skipped Read. Always echo, even on skip. |
| "Refresh wording from old code says 'since Phase 1' — I'll keep it." | Some skills (debug) have no Phase 1. "Since the previous load" is the canonical anchor-free wording — update on contact. |
| "Cwd Read returned file-not-found — skip straight to the missing-file echo." | The user may have authored instructions on the main worktree's branch while the current cwd is a stale feature branch or a linked worktree. Always try the `PRIMARY_ROOT` fallback before echoing `No <filename> found` — that's the durability contract. |
| "I'll always read from `PRIMARY_ROOT` directly and skip the cwd Read." | The user may have edited the instruction file on the current branch mid-session via `/geniro:instructions edit`. Cwd-first respects per-branch edits; primary-only loses them. The fallback fires ONLY when cwd misses. |

## Definition of Done

- [ ] Helper is invoked at every consumer's Step 0 (initial load) — physically first, not buried mid-step
- [ ] Helper is re-invoked at every phase-boundary refresh site declared in the consumer
- [ ] `PRIMARY_ROOT` is resolved once per invocation via `primary-worktree.md` Mode A before the load loop
- [ ] When cwd Read returns file-not-found AND `PRIMARY_ROOT` differs from cwd, a fallback Read against `<PRIMARY_ROOT>/.geniro/instructions/<file>` is attempted before the "No `<name>` found" echo
- [ ] Every Read emits exactly one echo line per §Echo contract (cwd success / primary-worktree success / not-found)
- [ ] File-not-found (after fallback) triggers the "No `<name>` found — skipping." echo, not an error
- [ ] `LOAD_TIER` decides whether per-skill and `code-style.md` are part of the load set
- [ ] Consumer SKILL.md files do NOT duplicate the producer-side Rules/Constraints/Steps semantics — that lives here only
- [ ] Refresh sites use "since the previous load" wording (NOT "since Phase 1")
