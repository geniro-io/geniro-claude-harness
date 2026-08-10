## D4 — Authoring-rules compliance

**Scope:** `skills/**/*.md`, `agents/*.md` (shipped files — the rules bind these; `.claude/skills/` is exempt from shipping rules but check it for the prose rules), plus `.claude/rules/*.md` and `CLAUDE.md` for the rule-file-rules check below, the one rule that binds those two paths. **Method:** LLM reviewer; instruct it to read every `.claude/rules/*.md` file first and apply them as the rubric.

Checks (the rules files are the source of truth — these are pointers, not restatements):
1. **Hard exclusions** (`skill-authoring.md`): plugin-author-internal references, authoring-process narration, informational noise, out-of-scope content, non-English.
2. **Prose rules** (`skill-prose.md`) — the two with a consequence a reader can name, not the style set: **load-bearing invariants placed past the compaction re-attach boundary** (§Rule placement), which silently stop binding mid-session; and the **fresh-user test on every user-facing string** (step titles, AUQ text, narration templates), where the failure lands on the user's screen. Caps emphasis, menu-of-options phrasing, restatement summaries and point-of-view are style — out of scope per §Severity tiers.
3. **Structure rules** (`skill-structure.md`): section ordering; frontmatter description format (third person, "Use when", no XML); anti-rationalization tables within the row cap with reasoning in the right cell; reference-graph depth within its hop limit and no upward links from `_shared/` into skill bodies for runtime instructions; no line-number cross-refs. Also **reference class** (§Reference classes): prose carrying taste a verifier could evaluate one criterion at a time wants to be a rubric; prose stating a condition a command could decide wants to be an executable check or a failing test; prose describing a file's conventions wants to be that file, passed as an exemplar. Flag the mismatch, not every prose reference — prose is the default, just not the only option.

4. **Rule-file rules** (`rule-writing.md`, which scopes itself to `.claude/rules/**` and `CLAUDE.md`): those files carry the instruction, the reason only where the model would rationalize around it, and exact contract values. This row is the pointer for the two paths no shipping rule reaches.

Tier mapping: hard exclusions / hard structure breaches → T2; a misplaced load-bearing invariant or a user-facing string failing the fresh-user test → T4.

