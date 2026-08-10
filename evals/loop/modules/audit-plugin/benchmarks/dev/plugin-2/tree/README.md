# Audit plugin

Runs on macOS and Linux. Requires `bash`, `jq`, and `git`.

## Settings

`.plugin/settings.json` accepts:

| Key | Default | Meaning |
|---|---|---|
| `telemetry` | `true` | Set to `false` to disable the telemetry guard |
| `retries` | `3` | How many times a failed step is retried |

A failed step is retried at most 3 times before the run aborts.
