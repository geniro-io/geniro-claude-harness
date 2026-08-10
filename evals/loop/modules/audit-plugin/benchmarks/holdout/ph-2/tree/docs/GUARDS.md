# Guards

## block-secret-write

Blocks any write that would put a credential into a tracked file. It covers the
`Write` and `Edit` tools **and** shell redirection, so a `cat > config.yml`
carrying a token is stopped the same way an `Edit` call is.

## block-branch-delete

Blocks a push that deletes a remote branch. A deleted remote branch takes its
open pull request with it, and nothing in the run can put either back.

## Retry budget

A guard that cannot reach its allowlist retries twice before failing closed.
