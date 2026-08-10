# Deploy — per-phase steps

## Phase 0 steps

1. `git status --porcelain` must be empty.
2. `git tag -l <tag>` must be empty.

## Phase 1 steps

1. Build with the project's build command.
2. Record the digest under `digest:` in the state file.

## Phase 2 steps

1. Run the smoke suite.
2. Record pass/fail under `smoke:` in the state file.

## Phase 3 steps

1. Promote the artifact.
2. Record the promoted digest and the environment.
