# Agent instructions

Scheduling service. TypeScript, Node 22.

## Code style

- Maximum line length: 120 characters.
- Named exports only. No default exports.

## Testing

Write the test first, always. An implementation lands with its test in the same
commit, never after.

## Commits

Conventional commits (`feat:`, `fix:`, `chore:`). Subject line under 72
characters, imperative mood, no trailing period.

## Error handling

Error handling is covered by the always-attached Cursor rule under
`.cursor/rules/`, which is the single source for it. Do not restate it here.
