---
paths:
  - "skills/**/*.md"
  - "agents/**/*.md"
---

# Skill & agent authoring — what NEVER ships to downstream consumers

Files under `skills/**/*.md` and `agents/**/*.md` are distributed to every repo that installs this plugin. The rules below apply when editing or creating them.

## Hard exclusions (reject before commit)

Strip each of the following before the edit completes.

### 1. Non-English content

- No Cyrillic, Greek, Han, Hiragana, or other non-Latin script anywhere in a body, comment, or error message — including mixed-language phrasing.
- AskUserQuestion `question:` / `description:` / `header:` are English-only.
- Mechanized in `tests/authoring/lint-skills.sh` as a hard failure. Allowed: em-dash, curly quote, `→` in a diagram, mathematical symbols. Disallowed: any letter outside basic Latin.

### 2. Plugin-author-internal references

A downstream reader has zero context about this plugin's authoring history. Strip every reference that only makes sense to a contributor:

- Internal design-doc anchors ("per design §9quater"). Inline the actual rule instead.
- Commit SHAs ("restored from `f6c0632~1`"). The downstream user does not have that commit.
- Plugin-version references in a skill body ("v3.0.0 introduces this", "since M4"). Those belong in `MIGRATION.md`.
- Author memory pointers ("per memory rule `feedback_X.md`"). The author's auto-memory does not ship.
- "We", "us", "our team" — the body addresses its reader, a downstream session. Use imperative voice.

### 3. Authoring-process narration

Skills are runtime instructions, not change logs. Strip:

- Decision history ("we decided to do X because Y"). The decision is the rule; the history is inert at runtime.
- Comparison to a deleted prior version ("the OLD skill did X — we now do Y"). State the current rule.
- "REPLACED" / "ADDED IN" / "DEPRECATED" markers inside a body. Those belong to git history.

Anti-rationalization rows stay: they address the reader's future reasoning, where narration describes the author's past reasoning.

### 4. Informational noise / hedges

Apply the no-op test to every sentence: does it change the model's behavior versus what it would do by default? A failing sentence is deleted whole, not trimmed to a shorter no-op — "be thorough" addressed to a model that is already thorough is paid-for silence, and the fix for a too-weak steering word is a stronger one ("relentless"), not more words. Sentences that commonly fail:

- Re-explanations of standard tooling ("the Read tool reads a file").
- Over-detailed mechanics the model derives itself — platform command recipes, shell hand-holding, prescribed loop shapes where a goal + bound suffices. State goal + constraint per `.claude/rules/skill-prose.md` §"Assume a capable model"; remove such a passage when editing near it, even if your change didn't introduce it.
- Hedge clauses and restatement summaries — both cut per `.claude/rules/skill-prose.md` §Token budget awareness, which names the shapes and the remedy.
- "Note:" / "Important:" / "Keep in mind:" on lines that are neither.

### 5. Out-of-scope content

A `skills/foo/SKILL.md` covers only what /foo does. Strip:

- Cross-skill commentary. Coordination contracts live in `_shared/`, not in either skill's body.
- Project-management metadata (effort estimates, file-line touch tables, sub-fix labels like "F1/F2/F3").
- Future-work TODOs / FIXME / "deferred to next version".
- Provenance ("adapted from X paper / Y blog / Z framework"). Restate the rule in your own voice.

## Soft preferences (apply where reasonable)

- Short imperative sentences.
- Concrete examples over abstract description, capped per rule — `.claude/rules/skill-prose.md` §"Examples — diverse and canonical" owns the count.
- Sentence case headings.
- Bullet lists over prose for enumerable rules.
- ASCII / Unicode box-drawing for diagrams; never embedded images.

## User-facing strings — plain English only

Any string the orchestrator surfaces to the user must pass the **fresh-user test**. The test itself, the translation tables, the scope, the exempt cases, and which surface to audit first: `.claude/rules/skill-prose.md` §"User-facing output uses plain English".

## Allowed and load-bearing

Preserve these — they are not noise:

- Tool-name references (Read, Write, Edit, Glob, Grep, Bash, Agent, AskUserQuestion, TodoWrite).
- File-path patterns the skill operates on.
- Frontmatter field schemas.
- Anti-rationalization tables (§3 above).
- Citations to other plugin files via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/<helper>.md` — these resolve in the consumer's installation.
- Cross-references to sibling skills by slug (`/geniro:plan`) — runtime invocation contracts.
