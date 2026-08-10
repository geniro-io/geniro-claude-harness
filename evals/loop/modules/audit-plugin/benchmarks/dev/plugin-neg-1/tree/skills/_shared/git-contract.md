# Git contract (shared)

## Annotated tags

A release tag is annotated, never lightweight: the annotation carries the
changelog entry, and a lightweight tag would leave the release notes reachable
only through the changelog file at that commit.

Tag body: the version line, a blank line, then the changelog entry verbatim.

## Push discipline

Push the tag alone (`git push origin <tag>`), never `--tags` — a bulk push
carries every local tag, including ones cut on a branch that was abandoned.
