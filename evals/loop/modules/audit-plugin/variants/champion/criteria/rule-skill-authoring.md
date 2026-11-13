---
paths:
  - "skills/**/*.md"
  - "agents/**/*.md"
  - ".claude/skills/**/*.md"
---

# Skill & agent authoring — what NEVER ships to downstream consumers

Files under `skills/**/*.md` and `agents/**/*.md` are distributed to every repo that installs this plugin. The rules below apply when editing or creating them.

`.claude/skills/**/*.md` are this repo's own meta-skills and never ship. Only §6 binds there — a tool surface varies by host whether or not the file is distributed; the exclusions above it are written for a downstream reader who does not exist for those files.

## Hard exclusions (reject before commit)

Strip each of the following before the edit completes.

### 1. Non-English content

- No Cyrillic, Greek, Han, Hiragana, or other non-Latin script anywhere in a body, comment, or error message — including mixed-language phrasing.
- AskUserQuestion `question:` / `description:` / `header:` are English-only.
- Allowed: em-dash, curly quote, `→` in a diagram, mathematical symbols. Disallowed: any letter outside basic Latin.

### 2. Plugin-author-internal references

A downstream reader has zero context about this plugin's authoring history. Strip every reference that only makes sense to a contributor:

- Internal design-doc anchors ("per design §9quater"). Inline the actual rule instead.
- Commit SHAs ("restored from `f6c0632~1`"). The downstream user does not have that commit.
- Plugin-version references in a skill body ("v3.0.0 introduces this", "since M4"). Those belong in `MIGRATION.md`.
- Author memory pointers ("per memory rule `feedback_X.md`"). The author's auto-memory does not ship.

### 3. Authoring-process narration

Skills are runtime instructions, not change logs. Apply the relevance test (`.claude/rules/skill-prose.md` §Relevance) to every line: decision history ("we decided X because Y"), a comparison to a deleted prior version, and "REPLACED" / "ADDED IN" / "DEPRECATED" markers describe how the rule got here, not what to do — delete them, git keeps the history. Anti-rationalization rows stay: they address the reader's future reasoning, where narration describes the author's past reasoning.

### 4. Informational noise / hedges

Hunt no-ops sentence by sentence: an instruction the model already obeys by default pays load to say nothing. The test — does the sentence change behavior versus the default? — is model-relative, not reader-relative: two people disagreeing about a no-op disagree about the default, so settle it by running the document, not by debate. For a guard, name the case it exists for: a removal that still passes the happy path proves nothing about the guard (`.claude/rules/skill-prose.md` §Token budget awareness). When a sentence fails, delete the whole sentence rather than trim words from it. The test also grades steering words: one too weak to beat the default ("be thorough" to an already-thorough model) is a no-op, and the fix is a stronger word ("relentless"), not a different technique. Sentences that commonly fail:

- Re-explanations of standard tooling ("the Read tool reads a file").
- Over-detailed mechanics the model derives itself — platform command recipes, shell hand-holding, prescribed loop shapes where a goal + bound suffices. State goal + constraint per `.claude/rules/skill-prose.md` §"Assume a capable model"; remove such a passage when editing near it, even if your change didn't introduce it.
- Hedge clauses and restatement summaries — cut per `.claude/rules/skill-prose.md` §Token budget awareness.
- "Note:" / "Important:" / "Keep in mind:" on lines that are neither.

### 5. Out-of-scope content

A `skills/foo/SKILL.md` covers only what /foo does. Strip:

- Cross-skill commentary. Coordination contracts live in `_shared/`, not in either skill's body.
- Project-management metadata (effort estimates, file-line touch tables, sub-fix labels like "F1/F2/F3").
- Future-work TODOs / FIXME / "deferred to next version".
- Provenance ("adapted from X paper / Y blog / Z framework"). Restate the rule in your own voice.

### 6. System-tool names used as instructions

Instruct by capability, not by tool name — "keep a todo list", "read the file", "spawn the reviewer", "web search". The model already knows its own tool surface, and a host that registers the capability under another name (or omits it) still follows a capability instruction, where a named tool it does not have reads as a missing step.

Literal names belong in the four places where the name is data rather than instruction:

- `allowed-tools:` and agent `tools:` frontmatter.
- Call syntax a run copies verbatim — `Agent(subagent_type=...)`, `Workflow(...)`.
- A sentence naming a specific parameter to pass or omit (`model=`, `run_in_background`).
- A guard description quoting what a hook matcher matches, and the Tool substitutions table in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md`, whose whole job is mapping names across hosts.

`Artifact` and `Workflow` stay named as Claude Code features: each has a substitutions row and an explicit not-available-here path, and their names are also section anchors and call syntax.

### 7. Model names at spawn sites

A light spawn in a skill or agent names its class — `light (smallest)` or `light (mid)` — defined in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §Cost classes. A site that names none is `session` and omits the model. A spawn never names a model family, a model id or a version; that file's §Runtime resolution is the only place a class meets a host's models.

- Agent frontmatter is always `model: inherit`; the class lives at the spawn site.

## Soft preferences (apply where reasonable)

- Concrete examples over abstract description, capped per `.claude/rules/skill-prose.md` §"Examples — diverse and canonical".
- Sentence case headings.
- Bullet lists over prose for enumerable rules.
- ASCII / Unicode box-drawing for diagrams; never embedded images.

## User-facing strings — plain English only

Any string the orchestrator surfaces to the user must pass the **fresh-user test**: `.claude/rules/skill-prose.md` §"User-facing output uses plain English", with the translation tables, scope, and exempt cases in `.claude/authoring/user-facing-prose.md`.

## Allowed and load-bearing

Preserve these — they are not noise:

- File-path patterns the skill operates on.
- Frontmatter field schemas.
- Anti-rationalization tables (§3 above).
- Citations to other plugin files via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/<helper>.md` — these resolve in the consumer's installation.
- Cross-references to sibling skills by slug (`/geniro:plan`) — runtime invocation contracts.
