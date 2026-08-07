# Contributing to Geniro Plugin

Thank you for your interest in contributing! This project aims to provide the best possible Claude Code plugin for the community.

## How to Contribute

### Reporting Issues

- Use [GitHub Issues](https://github.com/geniro-io/geniro-claude-harness/issues) to report bugs or suggest features
- Include steps to reproduce for bugs
- Describe the expected vs actual behavior

### Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-improvement`)
3. Make your changes
4. Test by installing the plugin into a real project — via the marketplace (`claude plugin install geniro@geniro-claude-harness`) or a local-path marketplace add — and running `/geniro:setup`
5. Run the checks below so CI comes back green
6. Commit with clear messages
7. Push and open a Pull Request

### Before you push

Run these three locally before you push — it's the difference between a green PR and a red one. CI does not regenerate the Cursor agents itself (step 2); it only runs `tests/run-all.sh` (step 3), which includes a drift check that fails if `cursor/agents/*.md` is out of sync — so step 2 has to be run and its output committed locally first.

```bash
# 1. Fetch the pinned judge prompts. The eval suites read evals/vendor/skills;
#    without the submodule every comparison degrades to a no-winner tie.
git submodule update --init

# 2. Regenerate the Cursor agent copies — REQUIRED after any agents/*.md edit.
#    cursor/agents/*.md are generated, never hand-written. CI
#    (tests/cursor/build-agents-fresh.sh) hard-fails on drift, so commit
#    agents/*.md and cursor/agents/*.md together.
bash scripts/build-cursor-agents.sh

# 3. Run every shell test suite (helpers, safety hooks, authoring lint).
#    Exits non-zero if any suite fails — this is the CI gate.
bash tests/run-all.sh
```

`jq` is a hard dependency of the suites. CI additionally runs ShellCheck at error severity over the shell scripts in `lib`, `hooks`, `tests`, `evals`, `cursor`, and `scripts`.

### What to Contribute

We especially welcome:

- **New agents** — workflow roles the skills can spawn (in the mold of `reviewer-agent` or `codebase-explorer-agent`)
- **New skills** — reusable workflows that solve common development tasks
- **Hook improvements** — better safety patterns, new protection categories
- **Bug fixes** — especially in the `/setup` skill's detection and generation logic
- **Documentation** — clearer explanations, more examples, better onboarding

### Guidelines

- **Keep it universal** — agents, skills, and hooks should work across languages and frameworks. Project-specific content belongs in the generated output, not the plugin
- **Test with real projects** — install the plugin, run `/geniro:setup`, and verify the generated output makes sense
- **Follow existing patterns** — look at how existing agents/skills are structured before creating new ones
- **Update ARCHITECTURE.md** — if your change affects design decisions, update the consolidated architecture reference
- **Keep working docs local** — plans, research notes, audit reports, and other throwaway design artifacts go in `design/scratch/` (gitignored, never committed). Skills that generate such docs (e.g. `/audit-plugin`) write them there; nothing in the tracked tree should depend on them. The one tracked file under `design/` is `audit-ledger.tsv` — see below

### The audit ledger — `design/audit-ledger.tsv`

Tracked, and committed with whatever round wrote it. One row per finding any audit has ever raised, carrying what was decided and which runs saw it.

It exists because the audit did not converge without it. Seven whole-repo rounds produced 138, 121, 101, 87 and 130 findings, because each round began blind: the report goes to gitignored `design/scratch/` and every run gets a fresh container, so no run ever read its predecessor's decisions.

Three things bind when you touch it:

- **The key is content, not a line number.** `ledger_fingerprint` hashes 100 characters of context from the cited line, whitespace-insensitive, spanning line boundaries — the `primaryLocationLineHash` shape from GitHub's `codeql-action`. Inserting lines above a finding leaves its key alone; rewriting the passage moves it, and the finding correctly reopens. Never hand-edit a fingerprint.
- **A `rejected` row states its reason.** The helper refuses one that does not. A suppression nobody can audit is how a ledger rots into a blanket that hides real defects — the failure mode measured across suppression stores generally, where most entries are never removed and the removed ones had long since stopped mattering.
- **Prune by machine, never by argument.** `ledger_prune` drops rows whose file is gone and nothing else. Re-opening a decision means a new finding in a new run, not an edit to the old row.

### Authoring checks in `.claude/skills/analyze-thread/checks-reference.md`

Two contracts bind that file, and neither is visible from a run — they matter only when you edit it:

- **Finding IDs are stable across edits.** Number a new check within its category (`A8`, `B5`, ...) rather than renumbering the file, because `/improve-template` consumes those IDs verbatim; a renumber silently repoints every handoff that cites one.
- **A new I- or K-class check needs its own expectation-set field** in that file's expectation-set section. Without one the check has no declared side to compare against, so it either never fires or fires on everything.

### Code Style

- Shell scripts: POSIX-compatible where possible, Bash where necessary
- Markdown: Use ATX headers (`#`), fenced code blocks, and tables for structured data
- Agent/Skill definitions: Follow the existing frontmatter format

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).
