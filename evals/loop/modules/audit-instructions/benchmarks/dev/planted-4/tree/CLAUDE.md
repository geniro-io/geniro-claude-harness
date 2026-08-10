# Engineering handbook

Scheduling service. TypeScript, Node 22.

## Code style

- Maximum line length: 100 characters.
- Never write comments in code. The code should explain itself; a comment is a
  sign the code needs rewriting.
- Named exports only. No default exports.

## Commits

Conventional commits (`feat:`, `fix:`, `chore:`). Subject line under 72
characters, imperative mood, no trailing period.

## Retries

Outbound calls retry at most 3 times — beyond that the upstream rate limiter
starts shedding, so a fourth attempt makes the incident worse rather than
better.

## Review

Two approvals before merge.

NOTE: for hotfixes on `release/*` branches a single approval is enough, and the
comment rule above does not apply to generated files.

## Error handling

Follow the error-handling conventions in AGENTS.md — that file is the source
for anything this handbook does not cover.
