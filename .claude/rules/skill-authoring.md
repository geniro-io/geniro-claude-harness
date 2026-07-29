---
paths:
  - "skills/**/*.md"
  - "agents/**/*.md"
---

# Skill & agent authoring — what NEVER ships to downstream consumers

This repo authors a Claude Code plugin. Files under `skills/**/*.md` and `agents/**/*.md` get distributed to every downstream consumer repo that installs the plugin. The rules below apply when editing or creating files matching the glob above.

## Hard exclusions (reject before commit)

A skill or agent body MUST NOT contain any of the following. If present, strip before edit completes.

### 1. Non-English content

- No Cyrillic, Greek, Han, Hiragana, or other non-Latin script characters anywhere in skill/agent body OR comments OR error messages.
- No English-Russian or English-other-language mixes ("см. ниже", "вместо того", etc.).
- Skill UI prompts (AskUserQuestion `question:` / `description:` / `header:`) MUST be English-only.
- Detection is mechanized in `tests/authoring/lint-skills.sh` (hard failure). Allowed: an em-dash, a curly quote, a `→` arrow in a diagram, mathematical symbols. Disallowed: any letter outside the basic Latin range.

### 2. Plugin-author-internal references

A downstream consumer reading the file in their own repo has zero context about this plugin's authoring history. Strip every reference that only makes sense to a plugin contributor:

- Internal design-doc anchors ("per design §9quater", "per `design/implement-v3.md` Phase 1"). Inline the actual rule instead.
- Internal commit SHAs ("restored from `f6c0632~1`", "M5 redesign in commit X"). The downstream user does not have that commit.
- Plugin-version references inside skill body ("v3.0.0 introduces this", "since M4"). Belongs in `MIGRATION.md` and commit messages, not skill body.
- Author memory pointers ("per memory rule `feedback_X.md`"). The author's auto-memory does not ship.
- "We", "us", "our team" — skill body addresses ITS reader (Claude in a downstream session), not the plugin authors. Use "you" or imperative voice.

### 3. Authoring-process narration

Skills are runtime instructions, not change logs. Strip:

- Decision history ("we decided to do X because Y"). The decision is the rule; the history is irrelevant at runtime.
- Comparison to a deleted prior version ("the OLD skill did X — we now do Y"). State the current rule directly.
- "REPLACED" / "ADDED IN" / "DEPRECATED" markers inside skill body. Belongs to git history.
- Anti-rationalization rows are OK — they're runtime checks against future drift, not author narration. The distinction: anti-rationalization addresses the reader's future reasoning; narration describes the author's past reasoning.

### 4. Informational noise / hedges

Apply the no-op test to every sentence: does it change the model's behavior versus what it would do by default? A failing sentence is deleted whole, not trimmed to a shorter no-op — "be thorough" addressed to a model that is already thorough is paid-for silence, and the fix for a too-weak steering word is a stronger one ("relentless"), not more words. Sentences that commonly fail the test:

- Re-explanations of standard tooling ("the Read tool reads a file", "git is a version control system").
- Over-detailed mechanics the model derives itself — platform command recipes, shell idiom hand-holding, prescribed loop/poll shapes where a goal + bound suffices. State goal + constraint per `.claude/rules/skill-prose.md` §"Assume a capable model"; when editing near such a passage, remove it even if your change didn't introduce it.
- Hedging without conditional ("this may or may not work depending"). Either state the condition under which it does/doesn't, or drop the line.
- Restatements of preceding paragraphs in summary form. The reader read the preceding paragraph 200 tokens ago.
- "Note:" / "Important:" / "Keep in mind:" prefixes on lines that aren't notes or important — these are filler.

### 5. Out-of-scope content

A `skills/foo/SKILL.md` covers ONLY what /foo does. Strip:

- Cross-skill commentary (`skills/foo/SKILL.md` discussing how /bar works). If skills coordinate, the coordination contract lives in `_shared/`, not in either skill's body.
- Project-management metadata (effort estimates, file-line touch tables, sub-fix labels like "F1/F2/F3"). Belongs to design docs / commit messages.
- Future-work TODOs / FIXME / "deferred to next version". If it's not in scope now, omit; downstream user does not need to know what we plan to do.
- Provenance ("this section was adapted from X paper / Y blog / Z framework"). Restate the rule in your own voice.

## Soft preferences (apply where reasonable)

- Prefer short imperative sentences. "Read X." not "Claude should consider reading X."
- Prefer concrete examples over abstract description, but cap examples per rule — see `.claude/rules/skill-prose.md` § "Examples — diverse and canonical" for the count (single-sourced there to avoid drift).
- Headings use sentence case, not Title Case.
- Bullet lists prefer over prose for enumerable rules.
- ASCII / Unicode box-drawing for diagrams; never embedded images.

## User-facing strings — plain English only

Any string the orchestrator surfaces to the user (chat narration, TodoWrite labels, AskUserQuestion `header` / `question` / `description` / option labels, status echoes, report sections) MUST pass the **fresh-user test**: a user with the plugin installed but no architecture docs loaded can act on the string without first learning a Geniro-specific identifier (`T2`, `L4`, `KR`, `FIX-NOW`, `Phase 4.3`, `m5-v2`, `phase: triage`, etc.). Full translation tables + scope + exempt cases + anti-rationalization in `.claude/rules/skill-prose.md` §"User-facing output uses plain English". The most common leak vector is **step titles** — they get echoed in narration verbatim, so fix step titles first when auditing a skill.

## Allowed and load-bearing

These are NOT noise and must be preserved:

- Tool-name references (Read, Write, Edit, Glob, Grep, Bash, Agent, AskUserQuestion, TodoWrite, etc.).
- File-path patterns the skill operates on.
- Frontmatter field schemas.
- Anti-rationalization tables (future-reader-directed, per §3 above).
- Citations to OTHER plugin files via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/<helper>.md` — these resolve at runtime in the consumer's installation.
- Cross-references to other plugin skills by skill slug (`/geniro:plan`, `/geniro:review`) — these are runtime invocation contracts, not authoring narration.

## Pre-commit verification

Before any commit touching `skills/**/*.md` or `agents/**/*.md`, mentally walk the file with the question: «would a downstream user reading this file in their own repo understand it without access to this plugin's `design/` directory, git history, MIGRATION.md, or contributor chat?» If the answer is no for any paragraph, that paragraph is out of scope.
