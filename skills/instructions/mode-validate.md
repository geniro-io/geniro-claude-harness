# Instructions — `validate` mode

Mode body for `${CLAUDE_PLUGIN_ROOT}/skills/instructions/SKILL.md`. Read on Phase-1 dispatch to `validate`. The spine keeps the scope set, the file shapes, the frontmatter reference, the invariants and the tool surface — this file carries the Steps.

## Contents

- Step 1 — scan + scope, and the `--max-lines` flag
- Step 2 — the lint rule set: structural / reference / per-scope checks, plus the `## Data Sources`, `## Verification Surface`, `## Memory Backend`, description-quality and `requires-context` rule sets
- Step 3 — per-skill phase mapping
- Step 4 — custom-reviewer count caps
- Step 5 — output format, and the no-auto-fix rule

---

### Step 1 — Scan + scope

`validate` accepts `<scope>` arg (validate one file) or no arg (validate all). Read-only; never mutates.

**flag:** `--max-lines N` overrides the default 300-LOC threshold (Step 2). Use `--max-lines 0` to disable the length check entirely. Env override: `GENIRO_INSTRUCTIONS_MAX_LINES`.

### Step 2 — Lint rule set

**Structural checks (apply to all scopes):**

| Check | Severity | Example violation |
|---|---|---|
| File parses as valid Markdown | CRITICAL | Binary file masquerading as `.md` |
| `## Rules` heading present (skip for `memory.md` — it carries the `## Memory Backend` block only) | HIGH | File has body but no `## Rules` header |
| `## Constraints` heading present (skip for `review-extra/<slug>.md` — uses `# Criteria` instead; skip for `memory.md`) | HIGH | Missing `## Constraints` |
| File ≤ 300 lines (threshold env-overridable, see Step 1) | LOW | Anthropic Claude Code memory guidance: "longer files consume more context and reduce adherence". Surface suggested actions inline (split into topic-specific files OR trim redundant rules). |

**Reference checks:**

| Check | Severity |
|---|---|
| No references to dropped skills (`/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`) | HIGH |
| No references to dropped phase names (e.g., "Phase 4 (Implement)" — not a value in the current per-skill phase enums) | MEDIUM |
| `Additional Steps` subsections match per-skill phase enum (the cross-skill `### After worktree-setup` anchor in `global.md` is the one non-phase exception) | MEDIUM |

**Per-scope checks:**

| Scope | Extra checks |
|---|---|
| `review-extra/<slug>.md` | Frontmatter parses as YAML and every field satisfies `SKILL.md` §Frontmatter field reference — the single source for the value sets and the description length cap. Severity: CRITICAL when `slug` fails its regex, mismatches the filename, or collides with a built-in dimension (the loader then silently runs the built-in and the custom criteria never fire); HIGH for any other field violation. Description quality is graded separately below. |
| `code-style.md` | At least 1 rule under `## Rules` — LOW warning if empty (no-op file) |

**`## Data Sources` lint rules** (applied to `global.md` and per-skill scopes when a `## Data Sources` section is present):

| Rule | Severity |
|---|---|
| A shell-command entry fails the read-only screen in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md` §4 — it carries a mutating verb, hides its action behind command substitution / a wrapped CLI, or is a SQL command that is not SELECT-shaped (the screen's verb set is single-homed there; do not re-list it here) | HIGH — a mutating data-source command could run against production. Emit: "Data Sources entry `<label>` carries a mutating or un-screenable command — sources must be read-only (the verification step runs them automatically). Make it a read-only query or remove it (see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md` §read-only screening)." |
| A malformed entry — no source (missing the backticked command / MCP-tool name / action name), or no `(confirms: ...)` hint | MEDIUM — the entry can't be used |

The HIGH severity matches the spec `verify:` read-only doctrine: a data-source shell command runs unattended during fact verification, so a mutating one is the same prod-risk class the `/geniro:implement` side-effect screen guards. `## Data Sources` is optional — absence is not a finding.

**`## Verification Surface` lint rules** (applied to `global.md` and per-skill scopes when a `## Verification Surface` section is present):

| Rule | Severity |
|---|---|
| A command entry carrying a covers clause but no does-not-cover clause (a `MANUAL` row is exempt — it names ground no command reaches, so it has no command boundary to state) | MEDIUM — half an entry per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-surface.md` §Entry shape: it tells a run what to execute and leaves it free to overstate the result. Emit: "Verification Surface entry `<command>` names what it covers but not what it does not cover — the second clause is the boundary a claim about a green run is stated at. Add it, or remove the entry (see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-surface.md` §Entry shape)." |

`## Verification Surface` is optional — absence is not a finding (no declared mapping leaves claim-scoping unchanged).

**`## Memory Backend` lint rules** (applied to `memory.md` when a `## Memory Backend` section is present):

| Rule | Severity |
|---|---|
| A `## Memory Backend` block in any file OTHER than `memory.md` (e.g. left in `global.md` or a per-skill file — those are not loaded for the memory layer) | MEDIUM |
| `memory.md` carries `## Rules` / `## Constraints` / `## Additional Steps` (the memory scope is for the backend block only) | LOW |
| An entry missing `layer`, or `layer` not `learnings` (`learnings` is the only routed layer) | MEDIUM |
| `mode` present but not `mirror` / `replace` | MEDIUM |
| The `read` tool/command fails the read-only screen in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md` §4 (the query op must be read-only; the `write` op is the declared mutator and is exempt) | HIGH — it runs unattended during retrieval |
| An entry missing `write` or `read` | MEDIUM |

`## Memory Backend` is optional — absence is not a finding (memory uses the built-in file).

**Description quality rules** — grade the `description:` of `review-extra/<slug>.md` against the three rows in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/description-quality.md`, which owns them and their severity.

**`requires-context` lint rules** (applied to `review-extra/<slug>.md`):

| Rule | Severity |
|---|---|
| Criteria body or `description` references live external data (`mcp__`, the words "Notion" / "Linear" / "Jira", "fetch from", "the API", or an `http(s)://` URL) but no `requires-context:` is declared | MEDIUM — emit: "Criteria reference live external data, but no `requires-context:` is declared. This reviewer runs in a subagent without MCP access and will see no external data — declare `requires-context:` so the orchestrator fetches it (see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` §Hydrating requires-context)." |
| `requires-context:` present but not a non-empty string | HIGH |

This is the guard that catches the silent-empty-findings trap at authoring time: a reviewer whose criteria say "match the diff against the Notion incident report" but which never declares the dependency will spawn into a subagent that can't fetch it, producing empty or hallucinated findings with no error.

### Step 3 — Per-skill phase mapping

Read `${CLAUDE_PLUGIN_ROOT}/skills/instructions/instructions-authoring-reference.md` §5 and check every `Additional Steps` subsection in the target file against the phase enum listed there for its scope, including the severities for free-form and dropped-phase anchors. That section is the single source; the one exception it records is `### After worktree-setup`, a cross-skill event anchor valid only in `global.md`.

### Step 4 — Count caps (review-extra)

Both thresholds live in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` §Step 6 — the runtime enforcer, which is what actually aborts a review past the cap and which states that other files cite it rather than restating the figures. Read that section for the two numbers, then count the files in `.geniro/instructions/review-extra/` and report against them:

- Past the soft-warn band: `⚠ Count {N} exceeds the sweet spot — consider consolidating overlapping reviewers.`
- Past the hard cap: `✗ Count {N} exceeds the hard cap — the loader will refuse to load all reviewers.`

### Step 5 — Output format

```
$ /geniro:instructions validate

Validation results: 4 files checked, 3 issues found.

✓ global.md no issues
⚠ implement.md 1 MEDIUM
└── Line 14: "### After Phase 4 (Implement)" → should be "### After implement"
⚠ code-style.md 1 LOW
└── File is 380 lines (>300). Anthropic guidance: longer files reduce adherence.
Suggestions: split into code-style-database.md + code-style-api.md, or trim redundant rules.
⚠ review-extra/sql-bindings.md 1 LOW
└── Frontmatter description: missing "Skip for" boundary clause (LOW)

To fix: /geniro:instructions edit implement
/geniro:instructions edit code-style
/geniro:instructions edit review-extra sql-bindings
```

When any `CRITICAL` or `HIGH` is present, lead the report with a blocking verdict — `✗ Needs fixing: <N> blocking issue(s)` above the per-file lines. `MEDIUM`/`LOW` are warnings and leave the verdict clean.

### No auto-fix

`validate` reports; it does not mutate. Auto-fix would silently rewrite user-authored instruction content, which is never overwritten without explicit user action.
