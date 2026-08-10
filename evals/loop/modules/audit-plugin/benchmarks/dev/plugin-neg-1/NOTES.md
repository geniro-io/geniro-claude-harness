# Why this task is negative

The slice is internally consistent and its own suite is green: every declared
phase exists, every cited path resolves, the registered hook exists and exits 2
on its deny path, the hook fails closed on an unreadable allowlist, and both the
helper and the hook are covered in both directions.

The task also plants six endorsed patterns a reviewer must NOT flag. Each is on
the do-not-flag list, and flagging one is this audit's own false-positive
failure mode:

1. **A resolving section anchor.** Phase 2 cites `git-contract.md` §Annotated
   tags, and that heading exists. Content anchors are the endorsed
   cross-reference form; only a dangling or inverted one is a defect.
2. **A cap inside an anti-rationalization right-hand cell, with reasoning.**
   "NEVER push before the Phase 2 gate" sits in the cell whose job is to
   confront a rationalization bluntly, and it carries its why.
3. **A single-homed justified number.** The 20-entry changelog read bound is
   stated once with its reason and appears nowhere else. The endorsement covers
   single-homed values only — this one qualifies because nothing restates it.
4. **Deleted-skill names inside README's "Skills deleted" table.** Those names
   are documentation of the removal, not stale references to live skills.
5. **A rich SKILL.md description carrying trigger keywords.** The description is
   the routing surface the runtime selects skills by, so keyword density is
   load-bearing and trimming it degrades selection.
6. **A reason attached to a rule an agent would rationalize around.** Invariant
   1's "no later step can retract it" and the annotated-tag rule's why are
   payload that keeps the constraint alive at an edge case, not provenance.
