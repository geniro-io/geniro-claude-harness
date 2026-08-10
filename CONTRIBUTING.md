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

Run these locally before you push — it's the difference between a green PR and a red one. CI does not regenerate the Cursor skill or agent copies itself (steps 1-2); it only runs `tests/run-all.sh` (step 3), which includes drift checks that fail if `cursor/skills/` or `cursor/agents/*.md` is out of sync — so steps 1-2 have to be run and their output committed locally first.

```bash
# 1. Regenerate the Cursor skill copies — REQUIRED after any skills/*/SKILL.md edit.
#    cursor/skills/geniro-<slug>/SKILL.md are generated, never hand-written. CI
#    (tests/cursor/build-skills-fresh.sh) hard-fails on drift, so commit
#    skills/*/SKILL.md and cursor/skills/ together.
bash scripts/build-cursor-skills.sh

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
- **Keep working docs local** — plans, research notes, audit reports, and other throwaway design artifacts go in `design/scratch/` (gitignored, never committed). Skills that generate such docs (e.g. `/audit-plugin`) write them there; nothing in the tracked tree should depend on them

### A recurring audit finding becomes a check, not a memo

`/audit-plugin` used to carry a suppression ledger so a finding decided in one round would not be re-raised in the next. It was removed: both halves of its key — a content fingerprint and a class slug — were produced by an LLM, and neither was stable enough to match a re-raise. Fifteen rows entered the last round it ran under and one matched.

What replaces it is the property that made the deterministic pre-pass never churn in the first place. When a finding class is decidable without taste — a reference that does not resolve, a declared tool absent from `allowed-tools`, a count contradicting the set it counts — add a hard check under `tests/authoring/` and let CI carry it. A check has a stable identity, fires identically every run, and stops firing permanently once the violation is fixed. Advisory checks do not get this property: the run that ignores a warning leaves it for the next reviewer to re-raise as prose, so make it hard or leave it out.

When a class needs taste to decide, it is not a candidate for a check and not a candidate for a memo either — prose findings from that pipeline were measured surviving at 6% against 86% for code.

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
