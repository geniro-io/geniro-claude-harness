# Verification checks

The `/geniro:setup` verification subagent reads this file during Phase Validate and runs every check below against the generated `CLAUDE.md`. The subagent has Read-only tools (Read, Bash read-only, Glob, Grep) — it reports DRIFT items for the orchestrator to fix in a regeneration round; it never edits any file itself.

The orchestrator reads it too, at Phase Generate: §Excluded content is the single enumeration of what must never reach `CLAUDE.md`, so the step that writes the file and the step that checks it work from one list.

---

## Excluded content

`CLAUDE.md` is a **project file**, not a plugin manual. Everything below already lives in the plugin's own files and is loaded automatically, so copying it into `CLAUDE.md` spends tokens on every run for content the model already has:

- Geniro skill table (already in plugin SKILL.md files)
- Path rules / `~` expansion warning (already in plugin CLAUDE.md)
- Safety hooks summary or allowlist (already in plugin hooks/)
- MCP dependencies table (already in plugin settings.json)
- Agent invocation ladder (already in plugin spawn-agent.md)
- Updating instructions (already in plugin update/SKILL.md)
- Any `<!-- geniro-setup-managed -->` markers (CLAUDE.md is user-owned)

Generation (`phase-3-generate.md` §3.2), the re-run pre-write audit and merge rules, the Phase Validate check below, and the Definition of done all resolve to this list.

---

## Cross-language contamination, template-artifact and generic-placeholder checks

These three checks are fixed literal-token/pattern batteries — run them with the script rather than re-deriving the token lists:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-grep.sh" <detected-language> <generated-file> [<generated-file> ...]
```

`<detected-language>` is one of `python | typescript | javascript | go | rust | ruby | java` — whatever Phase Detect resolved. Each output line is `<CHECK-LABEL>|<file>:<line>:<text>`, where `<CHECK-LABEL>` is `CROSS-LANG`, `TEMPLATE`, or `PLACEHOLDER`.

**TEMPLATE and PLACEHOLDER hits need no further judgment** — report every line as a DRIFT item with its file:line so the orchestrator can rewrite the section to be concrete and project-specific, or regenerate it from the detected project facts.

**CROSS-LANG hits need one judgment call per hit** — the check itself cannot tell a genuine cross-language reference from a generation artifact:
1. Read the offending line.
2. Decide: is this a legitimate cross-language reference (some projects genuinely use multiple languages, e.g. a monorepo with both Python and TypeScript), or a generation artifact?
3. Generation artifact → report it as a DRIFT item with file:line. The orchestrator removes it during regeneration; a Read-only subagent cannot edit it.
4. Legitimate → leave it; do not report.

---

Report findings as the §4.1 output contract requires: `## PASS items` and `## DRIFT items` (one per line, each DRIFT entry with file:line).
