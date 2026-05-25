# Strip-Geniro-tags helper

**Status:** Authoritative for stripping Geniro plugin doctrine sections from a project's `CLAUDE.md`. Invoked by `/geniro:setup` re-run via the MIGRATION.md v2.6.0 `Auto-fix:` mechanism.

**Spec source:** `MIGRATION.md` v2.6.0 entry «`CLAUDE.md` should not contain plugin doctrine».

## API

```bash
source lib/strip-geniro-tags.sh
strip_geniro_tags [--dry-run]
```

Or direct invocation:
```bash
bash lib/strip-geniro-tags.sh [--dry-run]
```

**Exit codes:**
- `0` — success (stripped N sections, or dry-run completed)
- `1` — no `CLAUDE.md` present OR no plugin doctrine found (no-op)
- `2` — IO error (awk failed, tmp-write failed, rename failed, bad flag)

## What counts as plugin doctrine

A `##`-anchored section is dropped iff ANY of:

1. **H1 marker.** The line `# Geniro Plugin` appears as an H1 (only the plugin's own CLAUDE.md uses this title).
2. **Heading-anchored.** The `##` heading matches one of these plugin-doctrine names exactly:
   - `Available Skills`
   - `Memory Layers` / `Memory Layers (M2)`
   - `Custom Agent Invocation`
   - `Safety Hooks` / `Safety Hooks (Active)`
   - `Optional MCP Dependencies`
   - `State Files`
   - `Path Rules`
3. **Marker-anchored.** The section body contains any of these high-precision plugin markers:
   - `${CLAUDE_PLUGIN_ROOT}`
   - `geniro-claude-plugin`
   - `geniro-claude-harness`

Sections that pass none of these checks are preserved verbatim — including sections whose prose mentions `/geniro:*` slash commands in passing. The strip rule is heading-/marker-anchored, not free-text slash-command matching.

## Atomicity & safety

- **Atomic write.** awk-based transform streams to `${claude_md}.tmp.$$`, then `mv` performs a POSIX `rename(2)` (atomic on same filesystem). Mid-run interruption leaves either the old or the new file, never a partial one.
- **No `.bak` files.** Atomic rename IS the safety. Re-running with no plugin sections is a cheap no-op (idempotency gate).
- **Cheap idempotency.** A single `grep -qE` pre-scan checks for any of the strip-triggering markers; if zero, returns rc=1 without touching the file.
- **Blank-line collapse.** Removing a section leaves a trailing/leading blank line; the helper collapses 3+ consecutive blank lines to a single blank line so the surviving content reads cleanly.

## Known limitations

- **H3 sections inside a stripped H2 are stripped with it.** The strip operates at H2 granularity. If a user authored useful project content as `### Foo` directly under a stripped `## Memory Layers`, that H3 is lost. Workaround: promote the H3 to `## Foo` before re-running setup. (Highly unlikely in practice — users don't nest project content under doctrine headings.)
- **No `.bak` snapshot.** If the user wants a recovery snapshot, they should run `--dry-run` first, or rely on git history (CLAUDE.md is typically tracked).
- **No opt-out flag.** Project CLAUDE.md hygiene is policy, not preference — the helper runs unconditionally during the setup re-run migration sweep. To suppress, exclude the v2.6.0 entry from the sweep by editing `.geniro/safety.json` to add a custom skip clause (documented in MIGRATION.md v2.6.0). Direct invocation always strips.
- **No multi-file processing.** Only `<repo-root>/CLAUDE.md` is touched. Nested project CLAUDE.md files (e.g. monorepo packages) need separate invocation with the appropriate cwd.

## Example output

**Dry-run mode** (`--dry-run`):
```
strip-geniro-tags: 4 plugin section(s) would be stripped from CLAUDE.md (dry-run — no changes written)
Run without --dry-run to apply.
```

**Real run:**
```
strip-geniro-tags: removed 4 plugin section(s) from CLAUDE.md
Project CLAUDE.md now contains only project-specific content. Plugin doctrine is loaded automatically by the plugin itself.
```

**No-op** (rc=1):
```
strip-geniro-tags: no plugin doctrine found in CLAUDE.md (no-op)
```

## Verification

After running, this grep should produce no matches in the project's `CLAUDE.md`:

```bash
grep -E '^# Geniro Plugin$|^## (Available Skills|Memory Layers|Memory Layers \(M2\)|Custom Agent Invocation|Safety Hooks|Safety Hooks \(Active\)|Optional MCP Dependencies|State Files|Path Rules)$|\$\{CLAUDE_PLUGIN_ROOT\}|geniro-claude-plugin|geniro-claude-harness' CLAUDE.md
```

This is the same predicate used by the helper's idempotency gate and by MIGRATION.md v2.6.0's `Auto-detect:` command.
