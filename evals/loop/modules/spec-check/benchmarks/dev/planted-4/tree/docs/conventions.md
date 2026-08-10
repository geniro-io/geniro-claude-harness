# Service conventions

## Background jobs

Prefer running a job inline when it finishes in under a second; queue it
otherwise. Queue anything that performs network I/O, unless the call is to a
service inside the same cluster and the caller already holds a deadline.

## Logging

Log at info on entry and exit of a queued job. Inline jobs log on failure only.
