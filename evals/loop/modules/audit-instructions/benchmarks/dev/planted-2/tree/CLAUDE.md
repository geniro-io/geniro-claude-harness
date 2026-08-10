# Contributor instructions

Internal admin console. Monorepo: `web/` (React) and `api/` (Node services).

## General engineering

Write clean, readable code. Prefer clarity over cleverness. Always read a file
before editing it, and make sure you understand the surrounding code first.
Think carefully about edge cases.

## Testing

Tests can be run with `vitest`, `npm test`, or `make test`, depending on which
part of the repo you are in and what you find most convenient.

## Web styling conventions

These apply to every React component under `web/`:

- Tailwind utility classes only. No CSS modules, no styled-components.
- Component files are PascalCase; hooks are `use*` in `web/hooks/`.
- Every interactive element carries an explicit `aria-label`.
- Colors come from the token set in `web/tokens.css` — never a raw hex value.
- Spacing uses the 4px scale (`p-1` through `p-8`); never arbitrary values.
- A component over 200 lines is split before new behavior is added to it.
- Client components declare `"use client"` on the first line.
- Server components never import from `web/hooks/`.

## API conventions

These apply to services under `api/`:

- Every route handler validates its input with a zod schema before use.
- Errors surface as `{ error: { code, message } }`; never a bare string.
- Database access goes through `api/db/client.ts`; no direct pool use.
- Every new route registers in `api/routes/index.ts`.

## Commits

Conventional commits. Subject under 72 characters.
