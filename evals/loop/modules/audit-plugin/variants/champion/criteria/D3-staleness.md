## D3 — Stale rules & dead references

**Scope:** `skills/`, `agents/`, `.claude/rules/`, `.claude/skills/`, `cursor/`, `scripts/`, top-level docs. **Method:** LLM reviewer seeded with D1 candidate lists. Where a reference is dead, check git history for a rename before writing the fix — repointing to the survivor beats deleting the mention.

Checks:
1. **Deleted-skill references** outside the documented replacement tables (adjudicate D1 candidates).
2. **Dangling section anchors — the undecidable half only.** A `§` sitting next to a file path is decided mechanically: `lint-canonical-homes.sh` hard-fails a canonical declaration whose file or heading is gone, and `lint-skills.sh`'s dangling-section-anchor ratchet check ratchets the rest. What is left for a reader is the BARE anchor, whose binding is not mechanically recoverable — it may name a section in the citing file, in a file named a paragraph earlier, or in none. Adjudicate those; do not re-scan what the lints already decided.
3. **Dropped phase/step names.** References to phases or steps that were renamed or removed (grep the referenced skill for the phase name). Read each hit rather than counting it — a hit that only *documents the removal* is not evidence the name is still live.
4. **Stale conditionals.** "when X ships" / "once Y lands" where X/Y already exists; "reserved for future" hooks that are now live.
5. **Orphans.** Adjudicate D1 orphan candidates: a `_shared` helper, lib script, or agent with zero inbound references is dead weight (or its callers reference it by a wrong name — which is a T1 instead).
6. **Stale rule files.** `.claude/rules/*` migration-audit sections describing work already completed; rules citing files that moved.
7. **MIGRATION.md / HOOKS.md entries** describing behavior the current code no longer has.

Tier mapping: wrong-name reference breaking a runtime lookup → T1; everything else → T3.

