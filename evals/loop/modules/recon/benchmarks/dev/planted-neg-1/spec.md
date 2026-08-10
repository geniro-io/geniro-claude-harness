---
title: Add an `ops version` subcommand
task-slug: version-command
branch: feat/version-command
---

# Add an `ops version` subcommand

## Problem

Operators have no way to tell which build of the CLI they are running.

## Goal

`ops version` prints the version string from package.json and exits 0.

## Acceptance criteria

- `ops version` writes the version to stdout.
- The command is registered through the same path as the existing subcommand.
