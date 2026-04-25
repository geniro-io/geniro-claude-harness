# Custom Action Template

This file is the canonical template for a `/geniro:actions create` output. The parent skill substitutes `{{placeholders}}` with values from the user interview, then writes the result to `.geniro/actions/<slug>.md`.

## Substitution variables

| Variable | Source | Example |
|---|---|---|
| `{{name}}` | user-provided action name (kebab-case, ≤64 chars) | `pr-notify-slack` |
| `{{description}}` | derived from interview Q1 + Q2; MUST start with "Use when" and stay ≤250 chars | `Use when a PR is opened and you want to summarize it in #eng-reviews. Do NOT use for force-pushed branches.` |
| `{{model}}` | inferred from complexity; default `inherit` | `inherit` |
| `{{allowed_tools}}` | derived from Q3 (output/side-effects) | `[Read, Bash(gh *), AskUserQuestion]` |
| `{{argument_hint}}` | derived from interview; describe expected positional args | `[pr_number]` |
| `{{created}}` | ISO date at write time | `2026-04-25` |
| `{{purpose}}` | first-paragraph prose synthesized from Q1 | one short paragraph |
| `{{when_to_use}}` | bullet list synthesized from Q2 | 2–4 bullets |
| `{{when_not_to_use}}` | optional — list "Do NOT use for…" exclusions if Q2 surfaced any | 0–3 bullets, or "(none)" |
| `{{steps}}` | numbered list synthesized from Q1 + Q3 | 3–8 numbered items |
| `{{output_summary}}` | 1-line description of what the user sees when the action completes | one line |
| `{{test_cases}}` | optional from Q4 | 1–2 short test cases or "(skipped)" |

## Generated file template

When writing the action file, output EXACTLY this skeleton with substitutions applied (and any optional `{{when_not_to_use}}` / `{{test_cases}}` sections fully removed if the user opted out):

```markdown
---
name: {{name}}
description: "{{description}}"
model: {{model}}
allowed-tools: {{allowed_tools}}
argument-hint: "{{argument_hint}}"
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

- **Description** starts with "Use when …"; the optional "Do NOT use for …" clause is encouraged for actions that are easy to misroute. Keep total length ≤250 chars.
- **Steps** are numbered and concrete. Each step names the tool or shell command (e.g., "Run `gh pr view {{argument}} --json title,body`"), not vague verbs ("look at the PR").
- **One-level deep**: if a step needs sub-detail, inline it; do NOT chain to another `.md` file. Claude's partial reads can miss content nested through references.
- **Secrets**: never inline tokens. Reference env vars (e.g., `$SLACK_BOT_TOKEN`). The Geniro file-protection hook blocks `.env`/`*.key`/`*.pem` writes; the secret-scanning hook flags leaked tokens in output.
- **Side effects**: if the action writes to external systems (Slack, GitHub, files outside `.geniro/`), the action's `description` SHOULD mention this so the parent's confirmation gate fires before execution.

## Where the template is read from

The parent skill (`skills/actions/SKILL.md` Phase 3.4) reads this file via `Read("${CLAUDE_SKILL_DIR}/skill-template.md")` during the create flow's draft step.
