# Custom action template

This file is the canonical template for a `/geniro:actions create` output. The parent skill substitutes `{{placeholders}}` with values from the user interview, then writes the result to `.geniro/actions/<slug>.md`.

## Substitution variables

| Variable | Source | Example |
|---|---|---|
| `{{name}}` | user-provided action name, satisfying `${CLAUDE_PLUGIN_ROOT}/skills/actions/SKILL.md` §Name validation | `pr-notify-slack` |
| `{{description}}` | derived from interview Q1 + Q2, shaped by §Authoring rules below | `Use when a PR is opened and you want to summarize it in #eng-reviews. Skip for force-pushed branches.` |
| `{{model}}` | inferred from complexity; default `inherit` | `inherit` |
| `{{allowed_tools}}` | derived from Q3 (output/side-effects) | `[Read, Bash(gh *), AskUserQuestion]` |
| `{{argument_hint}}` | derived from interview; describe expected positional args | `[pr_number]` |
| `{{risk_class}}` | Q4's answer; one of `low` / `medium` / `high` (REQUIRED) | `medium` |
| `{{external_send}}` | optional — `true` if Q3 reports an external side-effect (Slack/GitHub/etc.), else omit the line | `true` |
| `{{created}}` | ISO date at write time | `2026-04-25` |
| `{{purpose}}` | first-paragraph prose synthesized from Q1 | one short paragraph |
| `{{when_to_use}}` | bullet list synthesized from Q2 | 2–4 bullets |
| `{{when_not_to_use}}` | optional — conditions under which to skip the action: adjacent-action collisions, or operational guards (e.g. a draft PR, a missing token) | 0–3 bullets, or "(none)" |
| `{{steps}}` | numbered list synthesized from Q1 + Q3 | 3–8 numbered items |
| `{{output_summary}}` | 1-line description of what the user sees when the action completes | one line |
| `{{test_cases}}` | synthesized from Q3 — how to confirm the action worked | 1–2 short test cases |

## Generated file template

When writing the action file, output EXACTLY this skeleton with substitutions applied (drop the optional `external-send:` frontmatter line when there is no external side-effect, and remove the optional `{{when_not_to_use}}` section when the action has no skip conditions):

```markdown
---
name: {{name}}
description: "{{description}}"
model: {{model}}
allowed-tools: {{allowed_tools}}
argument-hint: "{{argument_hint}}"
risk_class: {{risk_class}}
external-send: {{external_send}}
created: {{created}}
created-by: geniro:actions
---

# {{name}}

{{purpose}}

## When to use

{{when_to_use}}

## When NOT to use

{{when_not_to_use}}

## Steps

{{steps}}

## Output

{{output_summary}}

## Test cases

{{test_cases}}
```

## Authoring rules (applied during synthesis)

- **Description** — this bullet is the canonical rule for an action's `description:` and the single home of its length cap; every create-gate and validate check reads the cap from here rather than restating it. The description starts with "Use when …" and runs to **at most 250 characters**. A terminal "Skip for …" clause (≤4 named categorical neighbors) is **optional** — add it only when an adjacent action would create routing collisions.
- **Steps** are numbered and concrete. Each step names the tool or shell command (e.g., "Run `gh pr view {{argument}} --json title,body`"), not vague verbs ("look at the PR").
- **One-level deep**: if a step needs sub-detail, inline it; do NOT chain to another `.md` file. Claude's partial reads can miss content nested through references.
- **Secrets**: never inline tokens. Reference env vars (e.g., `$SLACK_BOT_TOKEN`). The Geniro file-protection hook blocks `.env`/`*.key`/`*.pem` writes.
- **Side effects**: if the action writes to external systems (Slack, GitHub, files outside `.geniro/`), the action's `description` SHOULD name them — a run is not re-confirmed (`/geniro:actions` Phase 4.3), so the description is where the user learns what to expect.
