---
name: tag
description: "Use when cutting a release tag — bump the version, write the changelog entry, and push the annotated tag: 'cut a release', 'tag v2.4', 'bump and tag'. Skip for publishing an already-cut tag."
context: main
model: inherit
allowed-tools: [Read, Bash, Glob, Grep, AskUserQuestion]
argument-hint: "[version | empty to infer from the changelog]"
---

# Tag — cut a release tag

You are the release tagger. You compute the next version, write its changelog
entry, and push one annotated tag. You never publish; publishing is the CI job
the tag triggers.

## Phases overview

1. **Phase 0 — Resolve.** Determine the next version from `$ARGUMENTS` or the changelog.
2. **Phase 1 — Entry.** Write the changelog entry for the version.
3. **Phase 2 — Tag.** Create and push the annotated tag after the user approves.

## Loop invariants

1. **The tag is pushed only after an explicit approval.** A pushed tag triggers publication, which no later step can retract — so the approval gate is the last reversible point in the run.
2. **Version resolution reads the changelog, never the tag list.** A tag can exist for a version whose changelog entry was reverted; trusting the tag list would then skip a version.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The tag already exists, so the release is done — I'll skip Phase 1." | An existing tag proves a tag was pushed, not that its changelog entry survived. Invariant 2: resolve from the changelog. |
| "The user asked for a release, so pushing the tag is authorized." | NEVER push before the Phase 2 gate. Asking for a release authorizes the run, not the one irreversible step inside it — publication starts the moment the tag lands. |

## Budgets

| Budget | Value |
|---|---|
| Changelog entries read when inferring a version | 20 — deeper than any real gap between released versions, and bounded so a repo with a decade of history does not stream its whole changelog into context |

## PHASE 0 — Resolve

Read `CHANGELOG.md`. Take the version from `$ARGUMENTS` when given; otherwise increment the most recent released entry.

## PHASE 1 — Entry

Write the entry for the resolved version, grouping merged changes by type.

## PHASE 2 — Tag

Ask the user to approve the version and entry. On approval, create the annotated tag and push it. See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/git-contract.md` §Annotated tags for the exact tag body.

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/git-contract.md` — tag body format and push discipline
