# Instruction-file scaffolds

The empty `.geniro/instructions/<skill>.md` shapes `/geniro:setup` §3.3 writes when it has to create `plan.md` or `implement.md` before merging an `## Additional Steps` block into it. Both are the standard singleton per-skill shape: `## Rules` / `## Additional Steps` / `## Constraints`, with the phase-boundary anchors that skill accepts.

Write the scaffold first, then merge the block — merging into a file that does not exist yet drops the block silently. A file that already exists is never overwritten; the block is merged into its existing `## Additional Steps` section.

The anchors below are the ones each skill actually fires. `/geniro:instructions validate` checks an anchor against the skill's phase enum, so an invented anchor name is a step that never runs.

## `plan.md` scaffold

```markdown
# Custom Instructions

## Rules

- (none — add project-specific rules for /geniro:plan here)

## Additional Steps

### After user-approve
<!-- Steps to run once the user has approved the spec -->

## Constraints

- (none — add hard limits for /geniro:plan here)
```

## `implement.md` scaffold

```markdown
# Custom Instructions

## Rules

- (none — add project-specific rules for /geniro:implement here)

## Additional Steps

### After ship
<!-- Steps to run once the change has shipped -->

## Constraints

- (none — add hard limits for /geniro:implement here)
```
