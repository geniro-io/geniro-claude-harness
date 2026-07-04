# Load Custom Reviewers — Discovery + Spawn-Spec Helper

## Contents

- §When to invoke — the last step before the parallel reviewer batch
- §Inputs from the consumer skill — CHANGED_FILES / PRIMARY_ROOT slots
- §What this helper produces — the spawn-spec schema
- §Discovery procedure — Steps 1-7 (resolve root → glob → parse → validate → path-filter → cap → build specs)
- §Hydrating requires-context — orchestrator pre-fetch of declared external data
- §How consumers use the spawn-specs — the Agent() call template
- §Batched-mode behavior — `/geniro:review` one-spawn-per-run rule
- §Anti-rationalization

Canonical rule for discovering and spawning user-authored custom review dimensions. Referenced from every skill that spawns the parallel reviewer batch: `/geniro:review` (parallel-reviewer-spawn phase), `/geniro:implement` (self-review), `/geniro:refactor` (verify).

## When to invoke

Invoke this helper as the LAST step BEFORE the parallel reviewer batch — after loading built-in criteria files, after building the changed-files list, after detecting UI-files / PR-ref conditionals. The result is N additional `Agent(subagent_type="reviewer-agent", ...)` calls that join the SAME parallel batch as the 7-10 built-ins (one assistant turn, parallel execution — see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` §Parallel-spawn sites).

## Inputs from the consumer skill

The helper has no formal parameter list — it runs in the orchestrator's context and reads what's already there. The consumer skill MUST have these two slots in scope before invoking the helper:

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

If `git` is unavailable or the project has only one worktree, the registry is just `local` — same as `actions/SKILL.md` §Phase 5.0 Step 1.

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

For each invalid file, print one diagnostic line: `[load-custom-reviewers] skipped <path>: <reason>`. Continue processing the rest. One bad file does NOT kill the whole review.

### Step 5: Apply `paths:` filter

For each VALID file:

- If `paths:` is absent OR is the empty list, the reviewer ALWAYS fires; carry it forward.
- If `paths:` is set, build the union of changed-file paths from `CHANGED_FILES` (the same list the built-in reviewers receive). The reviewer fires only if at least one changed file matches at least one of the globs in `paths:`. Use Git-style fnmatch / bash-globstar semantics (`**` for arbitrary depth, `*` for arbitrary chars within a path segment, `{a,b}` for brace alternation, `?` for single char) — matches the conventions used by `.gitignore` and `.claude/rules/<scope>.md` `paths:` frontmatter. Silently drop the reviewer when no changed file matches — this is by design, not an error.

### Step 6: Enforce caps

After Step 5 filtering, count the surviving reviewers:

- If count > 10, abort the helper with a hard error. Print: `[load-custom-reviewers] hard cap exceeded — <N> active reviewers after path filter; limit is 10. Delete or scope down some files in .geniro/instructions/review-extra/`. The consumer skill MUST propagate this as a fatal error to the user — no review proceeds with >10 custom reviewers active.
- If count > 6, print a soft warning: `[load-custom-reviewers] <N> custom reviewers active — 4-6 dimensions per parallel batch is the sweet spot; consider scoping some with paths: globs to reduce the per-run count.` Continue.

### Step 7: Build spawn-specs

For each surviving (valid + path-filtered + within-cap) file, build the spawn-spec dict per the schema in §What this helper produces. Sort the list deterministically by slug (alphabetical) so spawn order is reproducible across runs.

Return the list to the consumer skill.

## Hydrating requires-context

Subagents run with a fixed tool surface — `reviewer-agent` declares `tools: [Read, Glob, Grep, Bash]` — and cannot call MCP servers. A custom reviewer that needs live external data (a Notion page, a Linear / Jira issue, an API response) therefore can't fetch it itself, and the fetch can't be added at the spawn site: the tool list is fixed and MCP tool names are per-install, so they're unknowable here. The orchestrator runs in the main context where MCP IS available, so it pre-fetches the data and injects it into the one reviewer's prompt — the same hydrate-and-inject pattern `/geniro:review` already uses for `LINEAR CONTEXT:`.

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
Agent(subagent_type="reviewer-agent", prompt="""
DIMENSION: {spec.dimension-label}
CRITERIA: {spec.criteria-content}
CHANGED FILES: [list of files with their full content — same list the built-in reviewers receive]
PROJECT CONTEXT: [stack, conventions from CLAUDE.md]
WORKTREE: [from `git rev-parse --show-toplevel`]
BRANCH: [from `git branch --show-current`]
DIFF CONTEXT: [git diff summary]
PLAN CONTEXT: [content from Phase 1, or "none"]
CUSTOM CONTEXT: [hydrated requires-context data per §Hydrating requires-context — OMIT this line entirely when spec.requires-context is null]
SEVERITY DEFAULT: {spec.severity-default | "MEDIUM"}
Review ONLY for the custom dimension '{spec.dimension-label}' as defined by the CRITERIA above. Do not cross into other dimensions. Use SEVERITY DEFAULT as your initial severity score for findings emitted under this dimension; you may up- or down-grade per-finding based on the criteria's specific guidance.
Findings that align with explicit plan decisions (e.g., "D-09: existing X are NOT backfilled") must be tagged [ALIGNS-WITH-PLAN]; findings that diverge must be tagged [DIVERGES-FROM-PLAN] — these route to INTENT-CHECK decision-type, not bug severity.
Anchor: stay within WORKTREE on BRANCH — verify with `pwd && git branch --show-current` on first Bash call; abort if either differs. See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` § Subagent spawn anchor.
""")
```

User-explicit form (user declared `model: haiku|sonnet|opus` in custom-reviewer frontmatter): identical to the form above, with one extra argument `model="{spec.model}"` after `subagent_type=`.

The DIMENSION value uses the literal form `custom:<slug>` so that the reviewer-agent's output naturally carries the source — the agent emits findings under `## custom:<slug> Review — N findings` and the orchestrator's Phase 4 judge pass picks the source up directly from that header. No new finding-output fields are required.

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` at every custom-reviewer spawn site (same runtime-degradation ladder as the built-ins: prefixed → bare → general-purpose with body inlined). When the batch falls back to the next rung, all custom reviewers in that batch fall back together — do not mix ladder rungs (per `spawn-agent.md` §Parallel-spawn sites).

## Batched-mode behavior (consumer: `/geniro:review` only)

When `/geniro:review` is in Batched Mode (large diffs), the built-in reviewers fan out per-batch. Custom reviewers do NOT fan out per-batch — they spawn ONCE per review run regardless of batch count, each one seeing the full changed-files list.

Rationale: custom reviewers tend to be narrow (path-filtered), so per-batch spawning would multiply identical `Agent()` calls; one-per-run is simpler and matches the per-PR rule already used for the pr-metadata reviewer. This applies only to `/geniro:review`'s parallel-reviewer-spawn phase, Batched Mode — the other two consumer skills (`/geniro:implement` self-review, `/geniro:refactor` verify) run only the standard parallel batch.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll skip the Step 1 main-worktree dedup since this is a non-linked-worktree project" | You can't reliably tell at runtime — `git rev-parse --show-toplevel` vs `git worktree list --porcelain` is the only ground truth. The actions skill applies the same dedup unconditionally; the helper inherits that convention so user-authored review-extra files survive worktree teardown just like actions do. |
| "I'll abort the helper on the first invalid file so the user notices" | Per Step 4, one bad file does not kill the rest. Aborting punishes users for typos — the warning is enough. The user sees the warning, fixes the file, re-runs. |
| "I'll pre-read all criteria content into orchestrator context for a summary" | The consumer skill IS the orchestrator, and it pre-inlines the criteria content into the spawn prompt — exactly the same as built-in reviewers do with `bugs-criteria.md` etc. Pre-inlining N user files inflates the spawn prompt by N×criteria-length, but each spawned agent only sees its own criteria. This matches the built-in pattern verbatim. |
| "I'll dedup main + local by union, not by 'local wins'" | Mirror the actions convention exactly: local wins. Uncommitted local edits exist for a reason — typically the user is iterating on a new reviewer. Union would re-introduce the stale committed version. |
| "I'll let the per-batch case spawn custom reviewers per batch for symmetry with built-ins" | Custom reviewers are narrow by design (path-filtered). Per-batch fan-out multiplies cost with no accuracy gain. Per-PR (or here, per-review-run) matches the pr-metadata pattern. |
| "If `paths:` is set and matches nothing, I'll fire anyway just to be safe" | If the user scoped a reviewer to `**/*.sql` and the diff has no SQL files, firing it wastes a Sonnet call and produces zero findings. Silently drop — the `paths:` field IS the user's opt-out for unrelated diffs. |
| "I'll cache the spawn-specs across consumer-skill invocations within the session" | Don't. The changed-files list differs per invocation, so the `paths:` filter result differs too. Re-run the helper on every consumer-skill invocation. The cost is one Glob + N small Reads — cheap relative to the parallel reviewer batch itself. |
| "Custom reviewer's frontmatter omitted `model:` — I'll default to `sonnet` at the spawn site" | When `model:` is OMITTED in the custom-reviewer frontmatter, default to `inherit`, not `sonnet`. Custom reviewers follow the same default as built-ins per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. The user opts INTO a hardcoded tier only by explicitly writing `model: haiku` / `model: sonnet` / `model: opus` — honor that declaration when present, OMIT `model=` at the spawn site when absent. |
| "The custom reviewer's criteria say to fetch from Notion — I'll add the MCP tool to its spawn so the subagent fetches it" | The `reviewer-agent` tool surface is fixed (`Read, Glob, Grep, Bash`) and can't be widened per-spawn; MCP tool names are also per-install and unknowable here. The orchestrator pre-fetches the data and injects it via `requires-context:` / `CUSTOM CONTEXT:` instead — see §Hydrating requires-context. Without a `requires-context:` declaration, the reviewer silently sees no external data; that's what the validate-lint guard in `/geniro:instructions` flags at authoring time. |
