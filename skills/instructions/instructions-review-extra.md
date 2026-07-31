# review-extra: custom reviewer authoring and create flow

## Contents

- Custom reviewer authoring (review-extra) — body shape, severity-default, paths scoping, model choice, count caps.
- Mode: create — review-extra variant — the slug-bearing flow:
  - Step 1: Resolve the slug
  - Step 2: Validate the slug
  - Step 3: Check count caps
  - Step 4: Ensure directory exists
  - Step 5: Gather the description
  - Step 6: Gather the criteria body
  - Step 7: Propose the assembled file
  - Step 8: Write the file
  - Step 9: Confirm
- Worked example — an adversarial reviewer for high-risk paths (a complete, copy-adaptable `review-extra/adversarial.md`).

Companion file to `SKILL.md` for the `review-extra` directory-style scope. `phase-1-parse.md` keeps the scope resolution and the sibling `mode-<op>.md` files keep the list / edit / validate / delete Steps; this file holds the authoring guidance and the slug-bearing `create` flow (Steps 1-9), which replaces the singleton-file flow in `mode-create.md` for this one scope. Load this file when the resolved scope is `review-extra` and the mode is `create`, OR when the user asks for guidance on writing a custom reviewer. `PRIMARY_ROOT` in the commands below is the main repo checkout root — resolve it via the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` in each Bash call that uses it (shell state does not persist across Bash calls; custom reviewers are cross-session content that must survive worktree removal, per `${CLAUDE_PLUGIN_ROOT}/skills/instructions/phase-1-parse.md` Step 0.5).

For the load-bearing rules referenced below: the validation rules are in `${CLAUDE_PLUGIN_ROOT}/skills/instructions/mode-validate.md` §Step 2 — Lint rule set (the `review-extra/<slug>.md` row in the per-scope table); the file structure is in `SKILL.md` §File shapes (for the loaded instruction files) and §Frontmatter field reference (for this scope's own schema).

## Custom reviewer authoring (review-extra)

Custom reviewers in `.geniro/instructions/review-extra/<slug>.md` follow a different shape from the other instruction files — they declare a new code-review dimension that runs alongside the built-in reviewer-agents (bugs, security, architecture, tests, optimizations, conventions, regressions, plus design/pr-metadata/spec-compliance). Treat each file as a reviewer-agent prompt body, not a workflow rule:

- **Keep the criteria body short — 30-80 lines is the sweet spot.** Reviewer-agents do better with a focused checklist than a long prose document. If your reviewer body exceeds ~120 lines, you are probably encoding two reviewers in one — split into two files with distinct slugs.
- **Mirror the `what to flag / what NOT to flag` shape** of the canonical exemplars at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/*-criteria.md` (e.g., `bugs-criteria.md`, `security-criteria.md`). The reviewer-agent infrastructure expects this convention and pattern-matches against the "What to flag" list to extract candidate findings.
- **Cite specific code patterns or anti-patterns, not abstract principles.** "String concatenation inside a template literal that contains the keyword `SELECT`" beats "SQL safety". The reviewer-agent grounds its findings in the patterns you name — abstract principles produce abstract findings.
- **Set `severity-default` to the typical severity for THIS reviewer's findings.** The reviewer-agent can override per-finding, but the default informs its initial scoring. A SQL-injection reviewer wants HIGH; a naming-consistency reviewer wants LOW.
- **Use `paths:` to scope narrow reviewers.** A reviewer that only matters for SQL files should not run on every PR — set `paths: ["**/*.sql", "**/dao/*.{ts,py}"]` so it fires only when at least one changed file matches. An always-fires reviewer (no `paths:` field) burns reviewer-agent budget on diffs where it can never find anything.
- **Declare `requires-context:` if the reviewer needs live external data.** A reviewer that matches the diff against a Notion page, a Linear issue, or an API response can't fetch that data itself — it runs in a subagent with no MCP access. Write a natural-language `requires-context:` directive naming the source and what to extract; the orchestrator fetches it and injects it as a `CUSTOM CONTEXT:` block before the reviewer runs (fail-open if the source is unavailable). Without it, a reviewer whose criteria reference external data silently sees none and produces empty or hallucinated findings.
- **Test the reviewer on one diff before committing it.** Invoke `/geniro:review` against a known-good PR and a known-bad PR and confirm findings appear and look right. A misfiring reviewer pollutes every subsequent review with noise.
- **Omit `model:` unless this reviewer needs a deliberate tier pin.** Omitted means the reviewer inherits the orchestrator's tier (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md`), which is right for most semantic checks. Declare `haiku` only for narrow pattern matchers (regex-like checks) where speed matters; declare `opus` only for deep architectural concerns that must run strong even from a cheaper session.
- **Keep the count inside the band `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` §Step 6 defines.** That section owns both the soft-warn band and the hard cap; the create flow warns at the first file past the band and hard-refuses at the first past the cap (§Step 3 below). Too many narrow reviewers fragment attention; consolidate when two reviewers' criteria overlap.

## Mode: create — review-extra variant

When the resolved scope is `review-extra`, follow this slug-bearing flow instead of the singleton-file `create` flow in SKILL.md. The output is a single file at `"$PRIMARY_ROOT"/.geniro/instructions/review-extra/<slug>.md` declaring one custom reviewer.

### Step 1: Resolve the slug

If the slug was provided on the command line (e.g., `/geniro:instructions create review-extra sql-bindings`), use it directly. Otherwise, use `AskUserQuestion` with no options (free-form via the "Other" path):
- **Question:** "What slug for this custom reviewer? (lowercase letters, digits, hyphens — e.g., `sql-bindings`, `accessibility-aria`, `pii-logging`)"

### Step 2: Validate the slug

Refuse and re-ask if any of the following fail:

- **Regex** — must match `^[a-z][a-z0-9-]*$` (lowercase ASCII letters/digits/hyphens, starts with a letter).
- **No built-in collision** — must not match any reserved dimension name, case-insensitively. `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` §Discovery procedure Step 4 holds the list; check against that file rather than a copy, since it is what actually rejects the slug at load time. On collision, error: `Slug "{{slug}}" collides with built-in reviewer "{{built-in}}". Pick a different slug — e.g., "{{slug}}-strict" or "{{slug}}-custom".`
- **No existing file** — `"$PRIMARY_ROOT"/.geniro/instructions/review-extra/{{slug}}.md` must not already exist. If it does, report: `<resolved path>` already exists. Use `/geniro:instructions edit review-extra {{slug}}` to modify it. and stop.

On any validation failure, re-ask via `AskUserQuestion` with the error message included in the question text.

### Step 3: Check count caps

Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` §Step 6 for the soft-warn band and the hard cap — that step is the runtime enforcer and the single home of both numbers. Then count the existing files:

```bash
ls "$PRIMARY_ROOT"/.geniro/instructions/review-extra/*.md 2>/dev/null | wc -l
```

- If this file would be the first one past the soft-warn band, warn via `AskUserQuestion`:
- **Question:** "Custom reviewer count will be {{N}} — past the sweet spot of {{band}} reviewers. Proceed?"
- **Options:**
- label: "Proceed anyway" — description: "Create it despite exceeding the sweet spot"
- label: "Cancel" — description: "Don't create — consider consolidating overlapping reviewers first"

On "Cancel", stop without writing.

- If this file would be the first one past the hard cap, hard-refuse — print:
```
Hard cap reached: {{cap}} custom reviewers maximum.

Existing slugs in .geniro/instructions/review-extra/:
- {{slug-1}}
- {{slug-2}}
...

Delete one with `/geniro:instructions delete review-extra <slug>` before adding another.
```
Stop without writing.

### Step 4: Ensure directory exists

```bash
mkdir -p "$PRIMARY_ROOT"/.geniro/instructions/review-extra
```

### Step 5: Gather the description

Use `AskUserQuestion` with no options (free-form via "Other"):
- **Question:** "One-line description of what this reviewer checks (shown in review reports and used in the reviewer-agent prompt). E.g., 'All SQL queries use parameterized bindings, never string concatenation.'"

### Step 6: Gather the criteria body

Explain the body shape before asking. Use `AskUserQuestion` with no options (free-form via "Other"):
- **Question:** "Paste the criteria body. Mirror the `what to flag / what NOT to flag` shape from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/bugs-criteria.md`. Keep it 30-80 lines, focused on concrete code patterns (not abstract principles). Example structure:\n\n```\n# Criteria\n\nWhat to flag:\n- String concatenation that builds a SQL string with a runtime variable\n- ORM.raw calls passing concatenated strings instead of bind parameters\n\nWhat to NOT flag:\n- Static SQL with no variables\n- Schema-migration files that intentionally build CREATE statements\n```\n\nPaste your criteria below:"

### Step 7: Propose the assembled file

Infer the optional frontmatter from the description and criteria just gathered, applying §Custom reviewer authoring above as the rubric: omit `model:`, scope `paths:` to the file kinds the criteria name, set `severity-default:` to the severity those criteria imply, and pre-fill `requires-context:` whenever the criteria reference live external data the reviewer cannot fetch for itself. Then render the assembled file — frontmatter plus criteria — and gate it:

- **Question:** "Here's the reviewer as assembled — create it?"
- **Options:**
- label: "Create it" — description: "Write the file exactly as shown"
- label: "Change a field" — description: "Adjust the model, the file patterns, the default severity, or the external-data directive first"
- label: "Cancel" — description: "Don't create the file"

On "Change a field", ask which one and take the new value free-form, then re-render the assembled file and re-ask. On "Cancel", stop without writing.

### Step 8: Write the file

Route the approved file through `atomic_state_write` to `"$PRIMARY_ROOT"/.geniro/instructions/review-extra/{{slug}}.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` (with the caller-side optimistic mtime check T3 CRUD requires) — `.geniro/instructions/*` is a T3 persistent-CRUD path, so direct `Edit`/`Write` trips the state-helper enforcement hook.

Example output for the `sql-bindings` walk-through (`model:` omitted, so the reviewer inherits the session tier):

```yaml
---
slug: sql-bindings
description: All SQL queries use parameterized bindings, never string concatenation
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

### Step 9: Confirm

Show the created file content and report (per `${CLAUDE_PLUGIN_ROOT}/skills/instructions/phase-1-parse.md` Step 0.5: when the main repo checkout is not the current directory, show the resolved absolute path and append `— written to the main repo checkout so it survives this worktree's removal.`):

```
Created `.geniro/instructions/review-extra/{{slug}}.md`.

This reviewer will run alongside the built-in reviewers every time you invoke
/geniro:review, and during the self-review of /geniro:implement and the
verification of /geniro:refactor.

Test it: run `/geniro:review` against a PR you expect this reviewer to flag,
and confirm findings appear and look right. Edit with
`/geniro:instructions edit review-extra {{slug}}`, validate the whole directory
with `/geniro:instructions validate`, or delete with
`/geniro:instructions delete review-extra {{slug}}`.
```

## Worked example — an adversarial reviewer for high-risk paths

Use this reviewer when diffs touch domains where failure is expensive — auth, billing, data mutations, external integrations. The `paths:` globs gate it to the project's own high-risk directories, which is more accurate than any generic risk heuristic — adapt the globs below to where those domains actually live in your repo. Over-flagging is absorbed before it reaches the user: findings from this reviewer flow through the same admission gate and per-finding verification as the built-in dimensions, so a speculative attack chain that fails verification is filtered out.

Copy-adapt this as `.geniro/instructions/review-extra/adversarial.md` (`model:` is omitted, so the reviewer inherits the session tier):

```markdown
---
slug: adversarial
description: Attacks diffs in high-risk domains (auth, billing, data mutations) by hunting reachable failure paths the author did not consider. Skip for unit-level edge cases and vulnerability-checklist hits — the bugs and security reviewers own those.
paths:
- "**/auth/**"
- "**/billing/**"
- "**/api/**"
severity-default: HIGH
---

# Criteria

Attack the diff; do not evaluate it. Assume the change is wrong and hunt for the
reachable path that proves it, using three attack techniques in priority order.

What to flag:
- Assumption violations — an input or system state the changed logic does not
  handle, reachable from a real entry point (e.g., a payment-webhook retry that
  arrives after the subscription row was deleted and hits the new billing branch).
- Cross-boundary composition breaks — a changed output (return shape, status
  code, event payload, persisted row) feeding an UNCHANGED consumer that still
  assumes the old shape. Cite both sides: the changed producer and the unchanged
  consumer.
- Abuse cases — a hostile-but-authenticated caller misusing the change within
  permissions it legitimately holds (e.g., replaying a discount-application
  request to stack credits the UI would never issue).

Every finding must cite the full reachable path: entry point → concrete trigger →
outcome delta versus pre-change behavior. A hypothesis that cannot name its
trigger is not a finding — do not emit it.

Budget: cap at 6 findings per run, deepest attack chains first. For diffs under
~50 changed lines, emit only what would score CRITICAL or HIGH.

What to NOT flag:
- Unit-level boundary, null, or type-coercion cases — the bugs reviewer owns those.
- Classic vulnerability-class checklist hits (injection, XSS, hardcoded secrets) —
  the security reviewer owns those.
- Anything deterministically reproducible as a failing test today — emit it tagged
  [TESTABLE] instead of arguing it as an attack chain, so the test gate picks it up.
```
