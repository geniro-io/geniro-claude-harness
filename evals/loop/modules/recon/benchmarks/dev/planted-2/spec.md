---
title: NDJSON output format for the reporting CLI
task-slug: ndjson-export
branch: feat/ndjson-export
---

# NDJSON output format for the reporting CLI

## Problem

The CLI can emit CSV and a fixed-width table. Downstream jobs want newline-
delimited JSON so they can consume the report incrementally instead of waiting
for the whole file.

## Goal

Add an `ndjson` output format: one JSON object per ledger row, keyed by the
report's column headers, written as rows arrive.

## Acceptance criteria

- `--format ndjson_format` emits one JSON object per line.
- Object keys are the report's headers.
- Memory use is flat across a 1M-row report.
