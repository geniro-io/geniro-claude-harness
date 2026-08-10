# Reporting CLI — sprint 22

Four approved items for the account reporting CLI. They were scoped separately
and none of them was described as blocking another. The upstream account
payload already carries every field these items need; nothing has to change on
the fetch side.

## Todos

### todo-1 — Last-active column

The report should show when each account was last active. Add a column for it,
rendered as a plain ISO date from the payload's `last_active` field.

### todo-2 — Status column

Finance wants the account's billing status on the report — `active`, `past_due`
or `closed`, straight from the payload's `status` field. Add a column for it.

### todo-3 — Amounts to the cent

The total column rounds down to whole dollars, which finance keeps having to
reconcile by hand. Show the exact amount including cents.

### todo-4 — Log level from the environment

The CLI's diagnostics verbosity is hardcoded. Read it from `REPORT_LOG_LEVEL`
instead, defaulting to the current value when the variable is unset, and reject
a value that is not one of the standard level names.
