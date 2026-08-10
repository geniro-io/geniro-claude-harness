# Why this task is negative

The slice is internally consistent and its own suite is green: every declared
phase exists, every cited path resolves, the registered hook exists and exits 2
on its deny path, the hook fails closed on an unreadable allowlist and on
unparseable stdin, its bypass ID is documented, and both the helper and the hook
are covered in both directions — including the global-option forms of the
blocked command and the near-miss flag that must not block.

## What this fixture got wrong, and how it was caught

It did not start out negative. The champion returned ten findings on it per
trial, several CRITICAL, and both A-vs-A arms converged on the same ones — which
is the signature of a broken fixture rather than a noisy reviewer. Read against
the source, four were real defects in this tree:

- **The guard was evadable.** `grep -Eq 'git +push +.*--tags'` requires `git`
  and `push` to be adjacent, so `git -C /repo push --tags` and `git -c k=v push
  --tags` ran straight through the hook whose entire purpose is to stop them.
  Verified by running the pattern, not by reading it.
- **`jq` on malformed stdin left through `set -e`** with jq's own status rather
  than the hook contract's 0 or 2.
- **The allowlist-bypass branch had no test**, while the suite header claimed an
  allow path — the covered "allow" was a non-matching command, a different
  branch.
- **The bypass ID appeared in no instruction file**, so nothing told a reader
  the hook could be turned off project-wide.

One of the ten was the reviewer's own false positive: `git push --follow-tags`
was reported as blocked by the old pattern, and it was not — `--tags` is not a
substring of `--follow-tags`. That one is now pinned by a test.

**The lesson for every fixture here.** Planting endorsed patterns is not the
same as verifying the rest of the tree is clean. The `no unplanted defect` sweep
in `tests/evals/audit-modules.sh` checks cited paths only; a defect in behaviour
is not mechanically detectable, so a finding that reproduces across arms indicts
the fixture until it has been read and ruled out. Until this repair, every noise
number measured on this module included a task where the correct answer was
non-empty — `noise_floor` in `target.json` among them.

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
