# Design-Doc Detection

Authoritative algorithm for resolving the first non-flag token of `$ARGUMENTS` to one of: `DESIGN_DOC`, `IDEA`, `CODE_REFERENCE`. Consumers cite this file at Phase 1 entry.

This file is the single source of truth. Skills cite this file; do NOT inline-paste the detection logic. Per-skill `$ARGUMENTS` parsing rules (flag handling, sub-command keyword stripping) remain in the consuming skill.

## Detection algorithm

### Step 1 — Extract token

Take the **first non-flag token** of `$ARGUMENTS` after stripping the sub-command keyword (e.g. for `/geniro:implement path/to/file` the token is `path/to/file`). Flags are tokens starting with `-` (single or double dash); skip them and any value tokens they consume per the consuming skill's flag spec.

If `$ARGUMENTS` is empty after stripping, the consumer falls back to its own empty-argument AUQ — this algorithm returns nothing.

### Step 2 — Resolve to filesystem

Treat the token as a candidate path. Resolve relative paths against the current working directory. Test for existence with the Read tool (or `ls` via Bash for a quick existence check).

**If the token resolves to an existing file:** evaluate the three detection markers below. **Defense in depth — accept ANY of:**

1. **Path-based** — the resolved path matches the glob `.geniro/planning/**/*.md` (any depth under `.geniro/planning/`, file extension `.md`).
2. **HTML marker** — the file's first 20 lines contain the literal string `<!-- geniro:design-doc -->` (case-sensitive, exact match).
3. **YAML frontmatter** — the file begins with `---` on line 1, and within the frontmatter block (between the opening `---` and the next `---`) there is a line matching `geniro_kind: design-doc` (whitespace-tolerant around the colon, value exact match).

**If ANY marker matches** → return `mode=DESIGN_DOC, path=<resolved-absolute-path>`.

**If the file exists but NONE match** → return `mode=CODE_REFERENCE, path=<resolved-absolute-path>` (existing `/geniro:implement` behavior preserved — the file is treated as a source-code reference for the implement skill).

### Step 3 — Treat as idea

**If the token does NOT resolve to a file** → return `mode=IDEA, topic=<token-and-remaining-arguments>` (the consumer treats the full remaining `$ARGUMENTS` string as the topic description, not just the first token).

## Pseudocode

```
token = first_non_flag_token(strip_subcommand_keyword($ARGUMENTS))
if token is empty: return None # consumer handles empty-arg AUQ

path = resolve_to_cwd(token)
if file_exists(path):
 if path matches ".geniro/planning/**/*.md": return DESIGN_DOC(path)
 if read_first_n_lines(path, 20) contains "<!-- geniro:design-doc -->": return DESIGN_DOC(path)
 if has_yaml_frontmatter(path) and "geniro_kind: design-doc" in frontmatter(path): return DESIGN_DOC(path)
 return CODE_REFERENCE(path)
else:
 return IDEA(topic=remaining_arguments)
```

## Why defense in depth

Each marker fails under different reasonable user actions; ANY-OF semantics ensures at least one survives.

- **HTML comment alone fails.** Paste-as-plain-text strips it (markdown editors/issue trackers/Slack). Some Markdown editors strip HTML comments on save (notably some "clean Markdown" formatters). If the user copies the design doc body into a different file, the HTML comment can be silently lost.
- **Path placement alone fails.** Design docs imported from outside `.geniro/planning/` (e.g. copied from another project, or attached to a tracker issue and downloaded) won't match the path glob. Path is also fragile across worktree moves.
- **YAML frontmatter alone fails.** Not all Markdown editors preserve frontmatter; some strip it on auto-format. Tools that render Markdown without frontmatter awareness can silently drop it on round-trip edits.

ANY-OF semantics: at least one marker survives any single user action that strips one of the others. All three is the minimum; fewer leaves a known-failing path.

## Per-consumer behavior

| Consumer | `DESIGN_DOC` | `IDEA` | `CODE_REFERENCE` |
|---|---|---|---|
| `/geniro:plan <topic>` | AUQ "Existing design doc at `<path>`. Start fresh with this as context / Cancel". On "Start fresh" → load doc into Phase 1 explore context (NOT as section template); run full 8-phase loop from Phase 1; emit a new spec.md at a fresh task-dir. On "Cancel" → exit without writing state.md. | Run full `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` from Phase 1. | Unsupported — error: "code reference passed to /plan; pass a topic or design-doc path. Did you mean /geniro:implement <path>?". |
| `/geniro:implement <arg>` | Phase 1 analyze treats the design doc as a spec source — walks the spec-discovery list and loads it as the authoritative spec.md OR plan.md alias. | Inline-task mode — treat as a raw spec description, write a brief `## Inline Plan` to state.md, proceed to Phase 2. | Existing behavior — treat as a code reference (Phase 1 reads it as context but not as the spec source). |

AUQ shape conventions for any of the per-consumer prompts above follow the canonical pattern in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md` (single-select unless explicitly multi-select; never auto-default on empty answer; fall back to plain text on empty-answer bug).

## Marker writers

`${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` Phase 6 writes **all three markers** (path placement under `.geniro/planning/<task-slug>/spec.md` canonical + HTML comment after H1 + YAML frontmatter `geniro_kind: design-doc`). This is the canonical writer.

Other writers (manually authored design docs, docs imported from external sources, docs written by other Geniro skills that produce design content) **should write at least the YAML frontmatter** to maximize portability — frontmatter is the marker that survives copy-out-of-`.geniro/planning/` and HTML-stripping editors. Path and HTML markers are nice-to-have but not sufficient on their own across all user workflows.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll add a `--from-design` flag to make it explicit" | Flag-free principle (Part 2 §"Auto-detection of existing design doc"). Auto-detect is the contract — adding a flag duplicates information already encoded in the marker, fragments the surface, and creates a "did you remember the flag?" failure mode. |
| "Path alone is enough — design docs always live in `.geniro/planning/`" | False. Users move files; copy-paste and tracker-attachments lose the path; cross-project imports land elsewhere. Path is the most fragile of the three markers. |
| "I'll only check the HTML marker — frontmatter and path are redundant" | Pasted-as-plain-text strips HTML comments; some Markdown editors strip them on save. Single-marker checks have known failure paths. The 3-way OR is the answer. |
| "I'll only check YAML frontmatter — it's the most reliable" | Some editors strip frontmatter on auto-format. Reliable does not mean infallible. Same logic as the HTML-only argument: defense in depth requires three. |
| "If the file exists but no marker matches, I'll fall back to IDEA mode" | No — return `CODE_REFERENCE`. This preserves `/geniro:implement <path>` behavior (existing files are code references unless explicitly marked as design docs). Falling back to IDEA on a real file path silently misclassifies code references as topics. |
| "I'll skip the first-20-lines bound for HTML-comment checks and scan the whole file" | Don't — the marker is conventionally placed after the H1 (within a few lines of the top). Scanning the whole file invites false positives (e.g. a code block discussing the marker syntax). 20 lines is the agreed bound; honor it. |
