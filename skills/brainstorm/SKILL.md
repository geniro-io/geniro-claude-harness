---
name: geniro:brainstorm
description: "DEPRECATED — renamed к /geniro:plan под M5. This stub exists для one release cycle к preserve invocation compatibility. Invoking surfaces the migration directive и exits. Do NOT add new logic here."
allowed-tools: [Read]
model: haiku
argument-hint: <topic-string-or-design-doc-path>
---

# /geniro:brainstorm — DEPRECATED (one-cycle alias)

This skill is а **one-release-cycle deprecation alias** для `/geniro:plan` (М5 §20.3).

The pre-M5 `/geniro:brainstorm` skill was renamed к `/geniro:plan` per master plan §20 + М5 §1. The new skill at `${CLAUDE_PLUGIN_ROOT}/skills/plan/SKILL.md` ships:

- А fixed 10-section spec.md schema (P-M5-1) so downstream consumers (М4 /implement, М6 /review) can reliably parse the output.
- Goal-state frontmatter block (P-M5-2 — budget / checkpoints / forbidden_actions / approval_required_for / tools_required).
- А mechanical 13-check validator (Phase 7) replacing the pre-M5 free-form Opus self-prompt.
- Approvals-persistence via state.md frontmatter `approvals[]` (M1 P-M1-1) — compaction-safe across all phases.
- Milestone-mode (Phase 5 §5.3) absorbing the deleted /decompose skill.
- А 2-option Phase 9 hand-off menu (was 4 options) since /features и /decompose are deleted.
- Phase 8 git commit deferred к post-approval (D1 defect fix — pre-M5 auto-commit at Phase 6 violated Always-WAIT).

---

## Action when invoked

Emit а single one-line directive в chat и exit. Do NOT run any loop, do NOT call any helper, do NOT mutate any state. The Read tool is granted only к honor potential L4 instructions; nothing else is allowed.

**Directive text** (emit verbatim, substituting $ARGUMENTS):

> `/geniro:brainstorm` is deprecated under M5 — use `/geniro:plan $ARGUMENTS` instead. The new skill ships а fixed 10-section spec.md schema, mechanical validator, и compaction-safe approvals persistence. See `${CLAUDE_PLUGIN_ROOT}/skills/plan/SKILL.md` for the full contract. This alias will be removed after one release cycle per master plan §60.

Then exit cleanly. The user re-invokes `/geniro:plan` when they're ready.

---

## Why а stub (and not а silent redirect)?

- **User agency.** Auto-redirecting `/geniro:brainstorm` к `/geniro:plan` would silently apply the M5 schema-first semantics к users who learned the pre-M5 free-form pattern. The deprecation message lets them see what changed before opting in.
- **Discoverability.** The chat directive surfaces the rename in а place the user will see — better than а silent migration that breaks the user's mental model.
- **Per master plan §60.** Each deleted skill gets а one-cycle deprecation alias so external scripts / docs / muscle memory have time к migrate.

---

## Definition of Done

- [ ] Invocation emits the migration directive в chat.
- [ ] Skill exits без mutating any state, calling any helper, или running any loop.
- [ ] $ARGUMENTS is preserved verbatim в the directive so the user can re-invoke с one paste.
