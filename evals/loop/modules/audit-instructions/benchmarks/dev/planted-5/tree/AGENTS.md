<!-- generated from CLAUDE.md by scripts/gen-agents.sh — do not edit -->

# Inventory API — working agreements

FastAPI service, Python 3.12, dependencies managed with uv.

## Layout

HTTP handlers live in `app/handlers/`. Add a new endpoint there, one module per
resource, and register it in `app/main.py`.

Background work lives in `app/workers/`.

## HTTP clients

All outbound I/O is async. Use `httpx.AsyncClient` for it; never use requests.

## Validation

FastAPI validates every request body against the Pydantic model declared on the
endpoint, so make sure the model is right — a wrong model means the wrong data
reaches the handler. Response models are declared the same way and are checked
on the way out.

## Checks

A pre-commit hook runs ruff over the staged diff and rejects the commit when it
fails, so there is no need to run the linter by hand before committing.

## Commits

Conventional commits. Subject under 72 characters.

## Release process

Tag `v*` on `main`, then run the release workflow. Cut the tag from a green
build only, and never from a feature branch.
