# Load custom reviewers — discovery + spawn-spec helper

## Contents

- §When to invoke — the last step before the parallel reviewer batch
- §Inputs from the consumer skill — CHANGED_FILES / PRIMARY_ROOT slots
- §What this helper produces — the spawn-spec schema
- §Discovery procedure — Steps 1-7 (resolve root → glob → parse → validate → path-filter → cap → build specs)
- §Hydrating requires-context — orchestrator pre-fetch of declared external data
- §How consumers use the spawn-specs — the Agent() call template
- §Large-diff behavior — `/geniro:review` one-spawn-per-dimension rule
- §Anti-rationalization

Canonical rule for discovering and spawning user-authored custom review dimensions. Referenced from every skill that spawns the parallel reviewer batch: `/geniro:review` (parallel-reviewer-spawn phase), `/geniro:implement` (self-review), `/geniro:refactor` (verify).

## When to invoke

Invoke this helper as the LAST step BEFORE the parallel reviewer batch — after resolving the built-in criteria paths, after building the changed-files list, after detecting UI-files / PR-ref conditionals. The result is N additional `Agent(subagent_type="reviewer-agent", ...)` calls that join the SAME parallel batch as the consumer's built-in dimensions (one assistant turn, parallel execution — see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` §Parallel-spawn sites).

## Inputs from the consumer skill

The helper has no formal parameter list — it runs in the orchestrator's context and reads what's already there. The consumer skill has these two slots in scope before invoking the helper — the helper reads what is already there rather than taking parameters:

- **`CHANGED_FILES`** — a list of file paths the consumer skill pre-built for the parallel batch (the same list the built-in reviewers receive in their `CHANGED FILES:` slot). Used by Step 5's `paths:` filter.
- **`PRIMARY_ROOT`** — the primary worktree root, computed at this helper-invocation site (never relied on from a prior phase) via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A — the Mode A snippet sets a Bash shell variable, and Bash environments are reset across compaction and across phase boundaries that re-launch Bash. Used by Step 1's local + main-worktree glob.

If either slot is missing, the helper aborts (treat as a contract bug in the consumer skill, not a user error).

## What this helper produces

A list of **spawn-specs** — one dict per surviving custom reviewer — with these keys:

- `slug` (string) — the reviewer's slug from frontmatter
- `dimension-label` (string) — `custom:<slug>` — used as the DIMENSION value in the spawn prompt
- `model` (string) — one of `haiku`, `sonnet`, `opus`, or `inherit` (the value defaults to `inherit` when frontmatter omits the field; user-explicit values are honored as-is per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` user-authored carve-out)
- `criteria-content` (string) — the body of the .md file (everything after the closing `---` of the frontmatter)
- `severity-default` (string or null) — one of `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, or null when unset
- `requires-context` (string or null) — the verbatim `requires-context:` frontmatter directive (natural-language description of the live external data the reviewer needs the orchestrator to fetch), or null when unset
- `source-path` (string) — the .md file path; used in audit lines and error messages

The consumer skill takes this list and, for each spec, appends one `Agent()` call to its parallel reviewer batch using the template in §How consumers use the spawn-specs.

## Discovery procedure

### Step 1: Resolve the search root

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A to compute `PRIMARY_ROOT`. Custom reviewer files live under `.geniro/instructions/review-extra/` — this is cross-session-durable storage that mirrors the `.geniro/actions/` convention so user-authored review-extra files survive `git worktree remove` on linked worktrees.

Walk the actions-skill convention exactly: when running in a linked worktree, glob BOTH `./.geniro/instructions/review-extra/*.md` (local) and `<PRIMARY_ROOT>/.geniro/instructions/review-extra/*.md` (main). When the same slug appears in both, **local wins** — drop the main-worktree entry from the candidate list. Uncommitted local edits take precedence over the committed primary-worktree version.

If `git` is unavailable or the project has only one worktree, the registry is just `local`.

### Step 2: Glob the directory

Use the Glob tool with pattern `.geniro/instructions/review-extra/*.md` (and the primary-worktree variant per Step 1). If the directory does not exist OR the glob returns zero files after the Step 1 dedup, the helper exits immediately with an empty spawn-spec list — this is the normal case for projects that have no custom reviewers.

### Step 3: Read and parse each file

For each glob match (after Step 1 dedup):

1. `Read` the file fully.
2. Parse the YAML frontmatter — the block bounded by a leading `---\n` line and a trailing `\n---\n` line. If either delimiter is missing, treat the file as malformed and skip it with a one-line warning per Step 4.
3. Extract the body — everything after the closing `---\n` of the frontmatter.
4. Validate the parsed result per Step 4.

### Step 4: Validate each file

A file is INVALID (skip it with a one-line warning, do NOT abort the helper) if ANY of these hold:

1. The frontmatter does not parse as YAML.
2. The `slug:` field is missing OR does not match the filename without `.md`.
3. The `slug:` value matches a reserved dimension name (case-insensitive): the built-ins `bugs`, `security`, `architecture`, `tests`, `optimizations`, `conventions`, `regressions`, `design`, `pr-metadata`, `spec-compliance`, plus `guidelines` and `rules-compliance` (retired built-in names — reserved to avoid ambiguity).
4. The `slug:` value does not match the regex `^[a-z][a-z0-9-]*$`.
5. The `description:` field is missing OR empty.
6. The `model:` field is present and is not in `{haiku, sonnet, opus, inherit}`. (Explicit `model: inherit` is the canonical Anthropic-documented form and is equivalent to omitting the field entirely — both yield spec.model = `inherit`.)
7. The `severity-default:` field is present and is not in `{CRITICAL, HIGH, MEDIUM, LOW}`.
8. The `paths:` field is present and is not a non-empty list of non-empty strings.
9. The body section (after the frontmatter) is empty OR contains fewer than 5 non-blank lines.
10. The `requires-context:` field is present and is not a non-empty string.

For each invalid file, print one diagnostic line: `Skipped custom reviewer <path>: <reason>`. Continue processing the rest. One bad file does NOT kill the whole review.

### Step 5: Apply `paths:` filter

For each VALID file:

- If `paths:` is absent OR is the empty list, the reviewer fires on every run; carry it forward.
- If `paths:` is set, build the union of changed-file paths from `CHANGED_FILES` (the same list the built-in reviewers receive). The reviewer fires only if at least one changed file matches at least one of the globs in `paths:`. Use Git-style fnmatch / bash-globstar semantics (`**` for arbitrary depth, `*` for arbitrary chars within a path segment, `{a,b}` for brace alternation, `?` for single char) — matches the conventions used by `.gitignore` and `.claude/rules/<scope>.md` `paths:` frontmatter. Silently drop the reviewer when no changed file matches — this is by design, not an error.

### Step 6: Enforce caps

After Step 5 filtering, count the surviving reviewers:

- If count > 10, abort the helper with a hard error. Print: `Too many custom reviewers — <N> are active after the paths: filter, and the limit is 10. Delete or scope down some files in .geniro/instructions/review-extra/`. The consumer skill propagates this as a fatal error to the user; continuing past the cap spawns a batch whose cost the run never agreed to.
- If count > 6, print a soft warning: `<N> custom reviewers are active on top of the built-in dimensions — past about 6 custom ones the extra per-run cost outpaces the coverage they add; consider scoping some with paths: globs so each fires only on the diffs it applies to.` Continue. Both numbers on this step — the soft-warn band at 6 and the hard cap at 10 — count CUSTOM reviewers only, never the built-in dimensions, which always fire on top of them. This step is the canonical home for both; other files cite it rather than restating the figures.

### Step 7: Build spawn-specs

For each surviving (valid + path-filtered + within-cap) file, build the spawn-spec dict per the schema in §What this helper produces. Sort the list deterministically by slug (alphabetical) so spawn order is reproducible across runs.

Return the list to the consumer skill.

## Hydrating requires-context

Subagents run with a fixed tool surface declared in their frontmatter. A custom reviewer that needs live external data (a Notion page, a Linear / Jira issue, an API response) cannot be relied on to fetch it itself, and the fetch cannot be pinned at the spawn site: MCP tool names are per-install, so the specific tool to call is unknowable here. The orchestrator runs in the main context where MCP IS available, so it pre-fetches the data and injects it into the one reviewer's prompt — the same hydrate-and-inject pattern `/geniro:review` already uses for `LINEAR CONTEXT:`.

Run this once per spawn-spec whose `requires-context` is non-null, AFTER Step 7 builds the specs and BEFORE appending the `Agent()` calls:

1. **Interpret the directive.** Read the natural-language `requires-context` string and pick the available tool that satisfies it (an MCP tool, `WebFetch`, etc.). The directive names the source and what to extract — e.g. "fetch the live Notion Incident Report, latest entry, and provide its incident-pattern list".
2. **Fetch read-only.** Call the tool to retrieve only what the directive asks for. Never mutate external state — review is read-only, matching the Linear-fetch rule in `/geniro:review`.
3. **Bound the result.** Cap the fetched content at ~5K characters (truncate with an explicit `[truncated]` marker). One reviewer's injected context should not dwarf the diff it reviews.
4. **Build the `CUSTOM CONTEXT:` block.** Pass the fetched data into that reviewer's spawn prompt via the `CUSTOM CONTEXT:` slot (see the template below). Scope it to the one reviewer that declared the dependency — the other reviewers in the batch do NOT receive it.

**Fail open.** If no available tool can satisfy the directive, or the fetch errors, do NOT abort the reviewer or the batch. Inject `CUSTOM CONTEXT: unavailable — <one-line reason>` so the reviewer knows it is running without the data, and surface one line to the consumer skill's caveats channel (`/geniro:review` → `## Caveats`; `/geniro:implement` / `/geniro:refactor` → their fail-open notice) so the reader knows that dimension ran blind. This mirrors the "fail-open if MCP unregistered" rule for Linear context — one missing data source never blocks the review.

## How consumers use the spawn-specs

For each spec the helper returns, the consumer skill appends one `Agent()` call to its parallel reviewer batch. The `model=` argument is **conditionally included**:

- When `spec.model == "inherit"` (the default when the user's custom-reviewer frontmatter omits `model:`) → OMIT the `model=` argument entirely. The Agent tool's runtime resolves the model from the reviewer-agent's frontmatter `model: inherit` directive.
- When `spec.model ∈ {haiku, sonnet, opus}` (the user explicitly declared a tier in their custom-reviewer frontmatter) → PASS `model="{spec.model}"` verbatim. User-explicit override beats inherit.

Inherit form (default — user did not declare `model:`):

```
Agent(subagent_type="geniro:reviewer-agent", prompt="""
DIMENSION: {spec.dimension-label}
CRITERIA: {spec.criteria-content}
PROJECT SEARCH POLICY: [verbatim global.md rules governing how to search this codebase, or `none declared` — governs every lookup the reviewer makes, not just its first]
CHANGED FILES: [list of files with their full content — same list the built-in reviewers receive]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
WORKTREE: [from `git rev-parse --show-toplevel`]
DIFF CONTEXT: [git diff summary]
PLAN CONTEXT: [content from Phase 1, or "none"]
CUSTOM CONTEXT: [hydrated requires-context data per §Hydrating requires-context — OMIT this line entirely when spec.requires-context is null]
SEVERITY DEFAULT: {spec.severity-default | "MEDIUM"}
Review ONLY for the custom dimension '{spec.dimension-label}' as defined by the CRITERIA above. Do not cross into other dimensions. Use SEVERITY DEFAULT as your initial severity score for findings emitted under this dimension; you may up- or down-grade per-finding based on the criteria's specific guidance.
Findings that align with explicit plan decisions (e.g., "D-09: existing X are NOT backfilled") must be tagged [ALIGNS-WITH-PLAN]; findings that diverge must be tagged [DIVERGES-FROM-PLAN] — these route to INTENT-CHECK decision-type, not bug severity.
Anchor: WORKTREE is your root — run every Bash call from it (`cd <WORKTREE> && …`) and resolve every file path under it.
""")
```

User-explicit form (user declared `model: haiku|sonnet|opus` in custom-reviewer frontmatter): identical to the form above, with one extra argument `model="{spec.model}"` after `subagent_type=`.

The DIMENSION value uses the literal form `custom:<slug>` so that the reviewer-agent's output naturally carries the source — the agent emits findings under `## custom:<slug> Review — N findings` and the orchestrator's Phase 4 judge pass picks the source up directly from that header. No new finding-output fields are required.

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` at every custom-reviewer spawn site (same runtime-degradation ladder as the built-ins: prefixed → bare → general-purpose with body inlined). When the batch falls back to the next rung, all custom reviewers in that batch fall back together — do not mix ladder rungs (per `spawn-agent.md` §Parallel-spawn sites).

## Large-diff behavior (consumer: `/geniro:review` only)

Custom reviewers spawn once per review run — exactly like every built-in dimension: one spawn per dimension regardless of diff size. On large diffs (Batched payload mode) the diff is organized into ~5-file groups as a reading order inside each reviewer's one spawn; the grouping never multiplies spawns for built-ins or customs.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll skip the Step 1 main-worktree dedup since this is a non-linked-worktree project" | You can't reliably tell at runtime — `git rev-parse --show-toplevel` vs `git worktree list --porcelain` is the only ground truth. The actions skill applies the same dedup unconditionally; the helper inherits that convention so user-authored review-extra files survive worktree teardown just like actions do. |
| "I'll abort the helper on the first invalid file so the user notices" | Per Step 4, one bad file does not kill the rest. Aborting punishes users for typos — the warning is enough. The user sees the warning, fixes the file, re-runs. |
| "I'll pre-read all criteria content into orchestrator context for a summary" / "built-ins pass a path now — pass `source-path` and drop `criteria-content`" | Reading them to summarize is what inflates context; reading them to fill one spawn slot each is the helper's job and it already happened at Step 3. Custom reviewers keep the content form on purpose: the file lives under the user's `.geniro/instructions/`, the helper has already parsed its frontmatter to build the spawn-spec, and a re-Read would only reach the same bytes. Built-in criteria pass as paths for the opposite reason — they are large, fixed, plugin-owned rubrics the orchestrator has no other need to open. Each spawned agent still sees only its own criteria either way. |
| "I'll dedup main + local by union, not by 'local wins'" | Mirror the actions convention exactly: local wins. Uncommitted local edits exist for a reason — typically the user is iterating on a new reviewer. Union would re-introduce the stale committed version. |
| "Large diff — I'll spawn extra reviewer instances per file group for coverage." | No dimension fans out per file group — built-in or custom. One spawn per dimension; the file groups are a reading order inside that one spawn. Per-group fan-out multiplied a real run to 33+ spawns with no accuracy gain — concern-parallel, never chunk-parallel. |
| "If `paths:` is set and matches nothing, I'll fire anyway just to be safe" | If the user scoped a reviewer to `**/*.sql` and the diff has no SQL files, firing it wastes a Sonnet call and produces zero findings. Silently drop — the `paths:` field IS the user's opt-out for unrelated diffs. |
| "I'll cache the spawn-specs across consumer-skill invocations within the session" | Don't. The changed-files list differs per invocation, so the `paths:` filter result differs too. Re-run the helper on every consumer-skill invocation. The cost is one Glob + N small Reads — cheap relative to the parallel reviewer batch itself. |
| "Custom reviewer's frontmatter omitted `model:` — I'll default to `sonnet` at the spawn site" | When `model:` is OMITTED in the custom-reviewer frontmatter, default to `inherit`, not `sonnet`. Custom reviewers follow the same default as built-ins per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. The user opts INTO a hardcoded tier only by explicitly writing `model: haiku` / `model: sonnet` / `model: opus` — honor that declaration when present, OMIT `model=` at the spawn site when absent. |
| "The custom reviewer's criteria say to fetch from Notion — I'll add the MCP tool to its spawn so the subagent fetches it" | The `reviewer-agent` tool surface is fixed (`Read, Glob, Grep, Bash`) and can't be widened per-spawn; MCP tool names are also per-install and unknowable here. The orchestrator pre-fetches the data and injects it via `requires-context:` / `CUSTOM CONTEXT:` instead — see §Hydrating requires-context. Without a `requires-context:` declaration, the reviewer silently sees no external data; that's what the validate-lint guard in `/geniro:instructions` flags at authoring time. |
