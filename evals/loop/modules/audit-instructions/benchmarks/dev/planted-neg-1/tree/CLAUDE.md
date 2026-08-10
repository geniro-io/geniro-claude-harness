# Feature-flag service

Go 1.23. Flags are read from Postgres and cached in-process.

## Essential commands

| What | Command |
|---|---|
| Test | `make test` |
| Lint | `make lint` |
| Migrate | `make migrate` |

## Conventions

- Flag keys are lowercase dot-separated (`billing.new_invoice`). The evaluator
  lowercases on read, so a mixed-case key silently never matches a stored one.
- Every migration in `db/migrations/` is forward-only. Rolling one back in
  production drops rows the previous version already wrote.
- Cache TTL is 30 seconds — long enough that a flag flip is not instant, short
  enough that a bad flag is contained within one deploy window.

## Layout

HTTP handlers live in `src/api/`. The evaluator is `src/evaluator.go`.
