# Telemetry pipeline

Rust 1.82. Ingests spans over gRPC, writes to ClickHouse.

## Commands

| What | Command |
|---|---|
| Build | `cargo build --release` |
| Test | `cargo test` |
| Lint | `cargo clippy -- -D warnings` |

## Error handling

Never use `unwrap()` or `expect()` anywhere in the codebase. Every fallible call
returns `Result` and propagates with `?`. This is the single most important rule
in this repo.

## Formatting

Four-space indentation, trailing commas in multi-line literals, imports grouped
std / external / crate with a blank line between groups.

## Conventions

- Span attributes are snake_case.
- A batch never exceeds 10,000 spans.
