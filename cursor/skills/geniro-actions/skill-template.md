<!-- Generated from skills/actions/skill-template.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Custom action template

This file is the canonical template for a `/geniro:actions create` output. The parent skill substitutes `{{placeholders}}` with values from the user interview, then writes the result to `.geniro/actions/<slug>.md`.

## Substitution variables

Fill each `{{placeholder}}` from the interview and the repo: `{{name}}` per `${CLAUDE_PLUGIN_ROOT}/skills/actions/SKILL.md` §Name validation; `{{description}}` from Q1 + Q2 per §Authoring rules below; `{{risk_class}}` from Q4 (`low` / `medium` / `high`, REQUIRED); `{{external_send}}` only when Q3 reports an external side-effect, else drop the line; `{{steps}}` 3–8 numbered items; `{{test_cases}}` 1–2 checks from Q3; `{{when_not_to_use}}` 0–3 skip conditions, or drop the section; `{{model}}` defaults to `inherit`; `{{created}}` is today's ISO date.

## Generated file template

When writing the action file, output EXACTLY this skeleton with substitutions applied (drop the optional `external-send:` frontmatter line when there is no external side-effect, and remove the optional `{{when_not_to_use}}` section when the action has no skip conditions):

```markdown
---
name: {{name}}
description: "{{description}}"
model: {{model}}
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

- **Description** — this bullet is the authoring-side statement of the `description:` rule and its length cap: the description starts with "Use when …" and runs to at most the character cap `${CLAUDE_PLUGIN_ROOT}/lib/validate-action-file.sh` enforces (`_VAF_DESC_MAX_CHARS`), which is the single home for that number. A terminal "Skip for …" clause (≤4 named categorical neighbors) is **optional** — add it only when an adjacent action would create routing collisions.
- **Steps** are numbered and concrete. Each step names the tool or shell command (e.g., "Run `gh pr view <pr_number> --json title,body`", naming the positional arg the way `argument-hint:` names it). A workflow spec is done when an implementer agent could run it without asking a single question. Where you don't actually know the current UI or the exact command, say so and ask the user or check the docs: never invent steps that may not exist. An action runs without re-confirmation, so an invented step executes unattended.
- **One-level deep**: if a step needs sub-detail, inline it; do NOT chain to another `.md` file. Claude's partial reads can miss content nested through references.
- **Secrets**: never inline tokens. Reference env vars (e.g., `$SLACK_BOT_TOKEN`).
- **Side effects**: if the action writes to external systems (Slack, GitHub, files outside `.geniro/`), the action's `description` SHOULD name them — a run is not re-confirmed (`/geniro:actions` Phase 4.2), so the description is where the user learns what to expect.
