# Instructions — Phase 1: Parse intent

Phase body for `${CLAUDE_PLUGIN_ROOT}/skills/instructions/SKILL.md`. Read on entry to Phase 1, and again on any resumption of it, including after a compaction. The spine keeps the scope set, the file shapes, the frontmatter reference, the invariants and the tool surface — this file carries the Steps.

---

**Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: instructions`, `LOAD_TIER: rules-only`, `MODE: initial-load`. The helper's §Echo contract requires one observable line.

**Step 0.5 — Locate the instructions directory.** Compute `PRIMARY_ROOT` via the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`, re-running it in every Bash call that uses the variable (Mode A owns the recompute-per-call rule); every `.geniro/instructions/...` path in the rest of this skill is prefixed `"$PRIMARY_ROOT"/`. Instruction files are cross-session content — a cwd-relative write from a linked worktree is lost when the worktree is removed. When `PRIMARY_ROOT` is not `.`: create/edit/delete success lines show the resolved absolute path, create/edit lines append `— written to the main repo checkout so it survives this worktree's removal.`, and if a same-named file exists at the cwd-local `.geniro/instructions/` path with different content, print one notice after create/edit: `Note: this worktree has its own copy of <file>, which takes precedence here when rules load.` Notice only — no question, no block.

## Mode detection

| Mode | Aliases | Resolves to |
|--------|---------|---------|
| List | show, view, list, display, what instructions, current | `list` |
| Create | add, new, create, set up, start | `create` |
| Edit | change, modify, update, edit, tweak, adjust | `edit` |
| Validate | check, verify, validate, lint | `validate` |
| Delete | remove, delete, drop, clear | `delete` |

If no arguments: default to `list`.

## Scope detection

- Explicit names: `global`, `code-style`, `memory`, `review-extra`, or a per-skill scope (`implement`, `plan`, `review`, `resolve`, `debug`, `refactor`, `onboard`, `investigate`, `reflect`)
- Contextual: "add a rule to review" → scope=review · "create debug instructions" → scope=debug · "code-style" / "style" / "naming conventions" → scope=code-style · "custom reviewer" / "review dimension" → scope=review-extra
- Explicit slug form: `review-extra <slug>` (e.g., `review-extra sql-bindings`)
- Multi-scope: "all", "every", "global and review" → collect into list
- "all" / "every" → expand to all valid scopes that have existing files (for edit/validate/delete) or all valid scopes (for create)

## Block-type routing

A `create`/`edit` request implies WHICH block to author, not just which scope. On a resolved `create` or `edit`, Read `${CLAUDE_PLUGIN_ROOT}/skills/instructions/phase-1-block-type-reference.md` here — before resolving the block type — and follow it, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`'s echo contract; a skipped Read silently defaults every request to `## Rules`. Resolve the block type from its intent → block table before continuing. `list`, `validate`, and `delete` author no block, so they skip that file.

## Ambiguity resolution

Ask via `AskUserQuestion`, offering the candidates that survive from `SKILL.md` §Valid scope set — each option labelled with the scope name and described by what loads it. When more than four candidates survive, chain follow-up questions per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §"Cap-extension for >4 options" rather than dropping a scope from the offer. **Cap retry at 3 rounds**; after the third, abort with "Could not narrow down — try `/geniro:instructions list` for the exact set."

## Scope validation

Before proceeding, verify resolved scope(s) are valid. If any resolved scope is NOT in the stable scope set, AUQ to ask the user to pick from valid scopes. Do NOT create, edit, or delete files for invalid scopes.

For `review-extra`, slug-bearing variants of `create`/`edit`/`delete` ALSO require a `<slug>` argument. Resolve missing-slug cases:

- `create review-extra` no slug → ask via `AskUserQuestion` "Other" path (free-form text).
- `edit review-extra` / `delete review-extra` no slug AND one file exists → default to that file.
- `edit review-extra` / `delete review-extra` no slug AND multiple files exist → AUQ which slug. If >4 files, chain follow-ups per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` cap-extension rule.
- `validate review-extra` ignores slug — always validates the whole directory. Print one-line notice if a slug was passed.

## Dispatch

Single scope: **Read `${CLAUDE_PLUGIN_ROOT}/skills/instructions/mode-<op>.md`** for the resolved mode (`list` / `create` / `edit` / `validate` / `delete`) and follow its Steps. Read only that one, and Read it again on any resumption of the run — the Steps are not in this file, so a run that skips the Read has nothing to execute. This Read comes before any step of the mode and carries a one-line echo, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — for `delete`, the mode body holds the destructive-op confirmation and nothing else stops the `rm -f`. Multi-scope: run §Batch mode below, which walks the same mode file once per scope.

## Batch mode

For multi-scope (e.g., "edit global and review", "add rules to all"), process each scope sequentially through the same mode flow. Across the stable scope set the multi-scope chain stays under 4 AUQ rounds.

Print summary after all scopes complete:

```
## Batch Complete

| Scope | Action | Result |
|-------|--------|--------|
| global | edit | Updated — added 2 rules |
| review | edit | Updated — added 1 constraint |
```
