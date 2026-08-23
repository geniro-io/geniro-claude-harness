# Dropped skills — canonical slug list

Single source of truth for the skills removed in the consolidation. Cite this file's list rather than restating the slugs — a restated copy drifts the moment another skill is dropped.

## The list

`/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`.

Their `.geniro/instructions/<scope>.md` files are no longer loaded by any skill.

## Consumers

- `${CLAUDE_PLUGIN_ROOT}/skills/instructions/mode-validate.md` §Step 2 Reference checks — flags a reference to a dropped skill inside an instruction file.
- `${CLAUDE_PLUGIN_ROOT}/skills/actions/subcommand-validate.md` §Step 2 — flags a reference to a dropped skill inside an action file's body.

A consumer adding a new dropped-skill check cites this file's list rather than re-typing it.
