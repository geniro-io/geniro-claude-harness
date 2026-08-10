## D5 — Structure & scoping

**Scope:** every surface. **Method:** reviewer; the orchestrator pastes §Surface inventory into the prompt — the loading notes there are this dimension's cost model. The core question: is each piece of content on the cheapest surface its tool offers, given when that surface loads?

Checks:
1. **Oversized always-on files.** A root `CLAUDE.md`, `copilot-instructions.md`, `AGENTS.md`, or `alwaysApply` rule whose cost is paid every session, carrying content only some sessions need. Size alone is not the finding — size times always-on loading is.
2. **Scoping misuse.** A rule applying to one directory or file type living in an always-on file when the tool supports scoping — `.claude/rules` `paths:`, `.mdc` `globs`, `.instructions.md` `applyTo`, a nested `CLAUDE.md` or `AGENTS.md`. Propose the move, naming source and destination.
3. **Monolith splitting.** One very large file where the tool supports a rules directory; propose the split by concern.
4. **Missing navigation.** A very long instruction file with no contents block near the top — tools that partially read see only the head.
5. **Wrong-surface content.** Session narration, changelogs, TODO lists, or design history inside instruction files — it costs attention on every load and belongs in docs or git history.
6. **Rules that never fire.** Adjudicate the D1 reachability candidates in context: a zero-match glob may be a typo (the rule was meant to apply — T1) or a planned-but-unbuilt area (staleness — T3); a rule reachable by no tool the team actually uses is dead weight (T4). Reachability intent is unreadable from the pattern alone — that is why these arrive as candidates, not machine findings.

Tier mapping: T4. A move proposal names what loads less often afterward; a move to a surface every session loads anyway saves nothing.

