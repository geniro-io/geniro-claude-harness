# Adapter: Claude subagents (judge — primary; executor — confirmation tier)

Not a shell adapter: the orchestrating Claude Code session IS the runtime. Free on
the subscription, so it is the default judge and the confirmation-tier executor.

## Judge protocol (primary path for `score.sh --phase judge`)

After `score.sh <run> --phase prep`, each `results/<task>/trial-*/judge-prompt.txt`
is a self-contained grading prompt. The orchestrator spawns one subagent per trial,
in parallel batches, each instructed to:

1. Read exactly one `judge-prompt.txt` (nothing else from the run — blindness:
   the prompt carries no variant identity, and the subagent must not open
   `spec.json`, prompts, or other trials).
2. Follow the prompt's instructions and Write the verdict JSON to `match.json`
   in the same directory.

Then `score.sh <run> --phase finish` consumes the `match.json` files. The
`--phase judge` CLI fallback (a second cursor-agent family) exists for headless
runs; skip it when subagent judging is available — it is the paid path.

Calibration duty: judge outputs are periodically shadowed by the human —
see `../judge/README.md`.

## Executor protocol (confirmation tier)

A screen verdict earned on the cheap CLI executor is confirmed on a Claude
executor before promotion: spawn one subagent per task×facet with the exact
`prompt-<facet>.md` the driver assembled (Read tools allowed on the staged
`tree/`), capture its final text as `.result` in a `raw-<facet>.json` matching
the adapter output shape (`{"type":"result","result":"...","usage":{}}`), then
score as usual. Token usage is not metered here — leave `usage` empty rather
than inventing numbers.
