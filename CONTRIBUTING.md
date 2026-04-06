# Contributing to Geniro Claude Harness

Thank you for your interest in contributing! This project aims to provide the best possible Claude Code harness template for the community.

## How to Contribute

### Reporting Issues

- Use [GitHub Issues](https://github.com/geniro-io/geniro-claude-harness/issues) to report bugs or suggest features
- Include steps to reproduce for bugs
- Describe the expected vs actual behavior

### Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-improvement`)
3. Make your changes
4. Test by installing the template into a real project and running `/setup`
5. Commit with clear messages
6. Push and open a Pull Request

### What to Contribute

We especially welcome:

- **New agents** — specialized personas for specific domains (e.g., data-agent, mobile-agent)
- **New skills** — reusable workflows that solve common development tasks
- **Hook improvements** — better safety patterns, new protection categories
- **Bug fixes** — especially in the `/setup` skill's detection and generation logic
- **Documentation** — clearer explanations, more examples, better onboarding

### Guidelines

- **Keep it universal** — agents, skills, and hooks should work across languages and frameworks. Project-specific content belongs in the generated output, not the template
- **Test with real projects** — install the template, run `/setup`, and verify the generated output makes sense
- **Follow existing patterns** — look at how existing agents/skills are structured before creating new ones
- **Update report.md** — if your change is based on research or framework analysis, document the rationale

### Code Style

- Shell scripts: POSIX-compatible where possible, Bash where necessary
- Markdown: Use ATX headers (`#`), fenced code blocks, and tables for structured data
- Agent/Skill definitions: Follow the existing frontmatter format

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).
