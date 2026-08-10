# Safety model

Three guards run as PreToolUse hooks. Each one hard-blocks: the tool call never
reaches the runtime, and the user sees the block reason.

| Guard | Blocks |
|---|---|
| `block-state-write.sh` | Direct writes to `.plugin/state/` that bypass the atomic helper |
| `block-rm-rf.sh` | Recursive deletes outside the workspace |

**Every guard fails closed.** When the guard cannot read its allowlist — the
file is missing, unreadable, or not valid JSON — it blocks. A guard that
allowed the call on a config it could not read would be disabled by deleting
one file.

Exit codes: a hook exits `2` to block the tool call. Any other non-zero exit is
reported to the user as a hook error and the call proceeds.
