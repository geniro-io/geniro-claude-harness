# review-extra: Custom Reviewer Authoring & Create Flow

## Contents

- Custom Reviewer Authoring (review-extra) — body shape, severity-default, paths scoping, model choice, count caps.
- Mode: create — review-extra variant — the slug-bearing flow:
  - Step 1: Resolve the slug
  - Step 2: Validate the slug
  - Step 3: Check count caps
  - Step 4: Ensure directory exists
  - Step 5: Gather the description
  - Step 6: Optional model override
  - Step 7: Optional paths globs
  - Step 8: Optional severity-default
  - Step 9: Gather the criteria body
  - Step 10: Write the file
  - Step 11: Confirm

Companion file to `SKILL.md` for the `review-extra` directory-style scope. The parent SKILL.md keeps the scope-resolution, list, edit, validate, and delete logic; this file holds the authoring guidance and the slug-bearing `create` flow (Steps 1-11). Load this file when the resolved scope is `review-extra` and the action is `create`, OR when the user asks for guidance on writing a custom reviewer.

See `SKILL.md` for the load-bearing rules referenced below: validation rules (`## — Mode: validate`, `### Step 2 — Lint rule set` — the `review-extra/<slug>.md` row in the per-scope table), file structure (`## File Structure: review-extra`), count caps cross-references.

## Custom Reviewer Authoring (review-extra)

Custom reviewers in `.geniro/instructions/review-extra/<slug>.md` follow a different shape from the other instruction files — they declare a new code-review dimension that runs alongside the built-in reviewer-agents (bugs, security, architecture, tests, optimizations, guidelines, conventions, regressions, plus design/pr-metadata/spec-compliance/rules-compliance). Treat each file as a reviewer-agent prompt body, not a workflow rule:

- **Keep the criteria body short — 30-80 lines is the sweet spot.** Reviewer-agents do better with a focused checklist than a long prose document. If your reviewer body exceeds ~120 lines, you are probably encoding two reviewers in one — split into two files with distinct slugs.
- **Mirror the `what to flag / what NOT to flag` shape** of the canonical exemplars at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/*-criteria.md` (e.g., `bugs-criteria.md`, `security-criteria.md`). The reviewer-agent infrastructure expects this convention and pattern-matches against the "What to flag" list to extract candidate findings.
- **Cite specific code patterns or anti-patterns, not abstract principles.** "String concatenation inside a template literal that contains the keyword `SELECT`" beats "SQL safety". The reviewer-agent grounds its findings in the patterns you name — abstract principles produce abstract findings.
- **Set `severity-default` to the typical severity for THIS reviewer's findings.** The reviewer-agent can override per-finding, but the default informs its initial scoring. A SQL-injection reviewer wants HIGH; a naming-consistency reviewer wants LOW.
- **Use `paths:` to scope narrow reviewers.** A reviewer that only matters for SQL files should not run on every PR — set `paths: ["**/*.sql", "**/dao/*.{ts,py}"]` so it fires only when at least one changed file matches. An always-fires reviewer (no `paths:` field) burns reviewer-agent budget on diffs where it can never find anything.
- **Declare `requires-context:` if the reviewer needs live external data.** A reviewer that matches the diff against a Notion page, a Linear issue, or an API response can't fetch that data itself — it runs in a subagent with no MCP access. Write a natural-language `requires-context:` directive naming the source and what to extract; the orchestrator fetches it and injects it as a `CUSTOM CONTEXT:` block before the reviewer runs (fail-open if the source is unavailable). Without it, a reviewer whose criteria reference external data silently sees none and produces empty or hallucinated findings.
- **Test the reviewer on one diff before committing it.** Invoke `/geniro:review` against a known-good PR and a known-bad PR and confirm findings appear and look right. A misfiring reviewer pollutes every subsequent review with noise.
- **Pick `model:` to match check depth.** Use `haiku` for narrow pattern matchers (regex-like checks). Use `sonnet` (default) for most semantic checks. Reserve `opus` for deep architectural concerns where Sonnet would miss the intent.
- **Sweet-spot count is 4-6 custom reviewers.** The skill warns when you'd create the 7th (i.e., exceed the sweet spot) and hard-refuses at the 11th (see "Count caps" below). Too many narrow reviewers fragment attention; consolidate when two reviewers' criteria overlap.

## Mode: create — review-extra variant

When the resolved scope is `review-extra`, follow this slug-bearing flow instead of the singleton-file `create` flow in SKILL.md. The output is a single file at `.geniro/instructions/review-extra/<slug>.md` declaring one custom reviewer.

### Step 1: Resolve the slug

If the slug was provided on the command line (e.g., `/geniro:instructions create review-extra sql-bindings`), use it directly. Otherwise, use `AskUserQuestion` with no options (free-form via the "Other" path):
- **Question:** "What slug for this custom reviewer? (lowercase letters, digits, hyphens — e.g., `sql-bindings`, `accessibility-aria`, `pii-logging`)"

### Step 2: Validate the slug

Refuse and re-ask if any of the following fail:

- **Regex** — must match `^[a-z][a-z0-9-]*$` (lowercase ASCII letters/digits/hyphens, starts with a letter).
- **No built-in collision** — must not match any built-in dimension name (case-insensitive): `bugs`, `security`, `architecture`, `tests`, `optimizations`, `guidelines`, `conventions`, `regressions`, `design`, `pr-metadata`, `spec-compliance`, `rules-compliance`. On collision, error: `Slug "{{slug}}" collides with built-in reviewer "{{built-in}}". Pick a different slug — e.g., "{{slug}}-strict" or "{{slug}}-custom".`
- **No existing file** — `.geniro/instructions/review-extra/{{slug}}.md` must not already exist. If it does, report: `.geniro/instructions/review-extra/{{slug}}.md` already exists. Use `/geniro:instructions edit review-extra {{slug}}` to modify it. and stop.

On any validation failure, re-ask via `AskUserQuestion` with the error message included in the question text.

### Step 3: Check count caps

Count existing files in `.geniro/instructions/review-extra/`:

```bash
ls .geniro/instructions/review-extra/*.md 2>/dev/null | wc -l
```

- If creating the 7th file (existing count == 6), warn via `AskUserQuestion`:
- **Question:** "Custom reviewer count will be 7 — the sweet spot is 4-6 reviewers, so you'd be exceeding it. Proceed?"
- **Options:**
- label: "Proceed anyway" — description: "Create the 7th reviewer despite exceeding the sweet spot"
- label: "Cancel" — description: "Don't create — consider consolidating overlapping reviewers first"

On "Cancel", stop without writing.

- If creating the 11th file (existing count == 10), hard-refuse — print:
```
Hard cap reached: 10 custom reviewers maximum.

Existing slugs in .geniro/instructions/review-extra/:
- {{slug-1}}
- {{slug-2}}
...
- {{slug-10}}

Delete one with `/geniro:instructions delete review-extra <slug>` before adding another.
```
Stop without writing.

### Step 4: Ensure directory exists

```bash
mkdir -p .geniro/instructions/review-extra
```

### Step 5: Gather the description

Use `AskUserQuestion` with no options (free-form via "Other"):
- **Question:** "One-line description of what this reviewer checks (shown in review reports and used in the reviewer-agent prompt). E.g., 'All SQL queries use parameterized bindings, never string concatenation.'"

### Step 6: Optional model override

Use `AskUserQuestion`:
- **Question:** "Which model should run this reviewer? Sonnet handles most semantic checks well; Haiku is good for narrow pattern matchers; Opus is for deep architectural concerns."
- **Options:**
- label: "sonnet (Recommended)" — description: "Default — best balance of cost and depth for semantic checks"
- label: "haiku" — description: "Cheap and fast — best for narrow regex-like pattern checks"
- label: "opus" — description: "Most thorough — use for deep architectural / cross-file concerns"
- label: "Skip — use default sonnet" — description: "Omit the model field; default to sonnet"

On "Skip", omit the `model:` field from frontmatter.

### Step 7: Optional paths globs

Use `AskUserQuestion`:
- **Question:** "Should this reviewer only fire for specific file patterns? Narrow scoping prevents the reviewer from burning budget on diffs where it can never find anything."
- **Options:**
- label: "All files (always fires)" — description: "Reviewer runs on every diff. Good for project-wide concerns."
- label: "Only files matching these globs (Recommended for narrow checks)" — description: "Reviewer fires only when the diff touches matching files."

On "Only files matching these globs", chain a free-form follow-up via `AskUserQuestion` (no options — "Other" path):
- **Question:** "Enter comma-separated globs (e.g., `**/*.sql, **/dao/*.{ts,py}`)."

Parse the comma-separated input into a YAML list. Validate each entry is non-empty and a string. On invalid input, re-ask.

### Step 8: Optional severity-default

Use `AskUserQuestion`:
- **Question:** "Default severity for findings from this reviewer? The reviewer-agent may override per-finding, but this is the starting point for scoring."
- **Options:**
- label: "HIGH" — description: "Security-critical / data-integrity reviewers (e.g., SQL injection, secrets logging)"
- label: "MEDIUM (default)" — description: "Most quality / convention reviewers"
- label: "LOW" — description: "Style / nice-to-have reviewers"
- label: "Other" — description: "CRITICAL, or skip and use the default MEDIUM"

On "Other", chain `AskUserQuestion`:
- **Question:** "Pick the severity:"
- **Options:**
- label: "CRITICAL" — description: "Reserve for must-fix-before-merge findings (data loss, auth bypass)"
- label: "Skip — use default MEDIUM" — description: "Omit the severity-default field"

On any "Skip", omit the `severity-default:` field.

### Step 9: Gather the criteria body

Explain the body shape before asking. Use `AskUserQuestion` with no options (free-form via "Other"):
- **Question:** "Paste the criteria body. Mirror the `what to flag / what NOT to flag` shape from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/bugs-criteria.md`. Keep it 30-80 lines, focused on concrete code patterns (not abstract principles). Example structure:\n\n```\n# Criteria\n\nWhat to flag:\n- String concatenation that builds a SQL string with a runtime variable\n- ORM.raw calls passing concatenated strings instead of bind parameters\n\nWhat to NOT flag:\n- Static SQL with no variables\n- Schema-migration files that intentionally build CREATE statements\n```\n\nPaste your criteria below:"

### Step 9.5: Optional external-data dependency

Use `AskUserQuestion`:
- **Question:** "Does this reviewer need live external data the orchestrator should fetch for it — a Notion page, a Linear/Jira issue, an API response? Subagents can't call MCP tools directly, so the orchestrator fetches the data and hands it to the reviewer."
- **Options:**
  - label: "No external data" — description: "The reviewer works from the diff and project files alone. This covers most reviewers."
  - label: "Yes — declare what to fetch" — description: "The orchestrator pre-fetches live external data and injects it before the reviewer runs."

On "Yes — declare what to fetch", chain a free-form follow-up via `AskUserQuestion` (no options — "Other" path):
- **Question:** "Describe what to fetch in one or two sentences — name the source and what the reviewer needs from it. E.g., 'Fetch the live Notion Incident Report (the page titled \"Incident Report\", latest entry) and provide its incident-pattern list so the reviewer can match the diff against known incidents.'"

Store the answer verbatim as the `requires-context:` frontmatter value. On "No external data", omit the field.

### Step 10: Write the file

Assemble the frontmatter (omitting fields the user skipped) and route the file through `atomic_state_write` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` (with the caller-side optimistic mtime check T3 CRUD requires) — `.geniro/instructions/*` is a T3 persistent-CRUD path, so direct `Edit`/`Write` trips the state-helper enforcement hook.

Example output for the `sql-bindings` walk-through:

```yaml
---
slug: sql-bindings
description: All SQL queries use parameterized bindings, never string concatenation
model: sonnet
paths:
- "**/*.sql"
- "**/dao/*.{ts,py}"
severity-default: HIGH
---

# Criteria

What to flag:
-...

What to NOT flag:
-...
```

### Step 11: Confirm

Show the created file content and report:

```
Created `.geniro/instructions/review-extra/{{slug}}.md`.

This reviewer will run alongside the built-in reviewers every time you invoke
/geniro:review (or /geniro:implement Phase 3 self-review / /geniro:refactor Phase 3 verify).

Test it: run `/geniro:review` against a PR you expect this reviewer to flag,
and confirm findings appear and look right. Edit with
`/geniro:instructions edit review-extra {{slug}}`, validate the whole directory
with `/geniro:instructions validate`, or delete with
`/geniro:instructions delete review-extra {{slug}}`.
```
