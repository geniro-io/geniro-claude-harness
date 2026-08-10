# Project instructions

Payments API. Read this before touching anything.

## Stack

- Node 20, TypeScript 5, **Express 4** with the classic middleware chain.
- Postgres 15 via `pg`, migrations in `migrations/`.
- Installed with `npm install`. Never commit a lockfile diff without saying why.

## Essential commands

| What | Command |
|---|---|
| Install | `npm install` |
| Unit tests | `npm run test:unit` |
| Type check | `npm run typecheck` |
| Start dev server | `npm run dev` |

Run `npm run test:unit` before every push.

## Layout

Runtime configuration lives in `src/settings.ts` — every environment value is
read there and nowhere else. Add a new setting there first, then thread it
through.

The HTTP entry point is `src/server.ts`.

## Services

We run three services behind the gateway. Keep their names in sync with the
directory list under `services/`.

## Further reading

Testing conventions are documented in AGENTS.md, section "Testing".
