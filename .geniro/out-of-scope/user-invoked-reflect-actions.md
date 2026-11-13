# Making /geniro:reflect or /geniro:actions user-invoked

Set `disable-model-invocation: true` on `/geniro:reflect` or `/geniro:actions` so their descriptions stop loading every session.

## Why this is out of scope

Considered under the invocation rule (`.claude/rules/skill-structure.md` §Frontmatter hygiene, description rule 5) and not chosen; both stay model-invoked. Reopen with a run that shows the description load costing more than the discovery it buys.

## Prior requests

- 2026-11-13: considered; not chosen.
