---
name: learnings-extraction
description: "Canonical doctrine for the auto-learning extraction step that runs at the end of /implement, /follow-up, /debug, and other pipelines. Single source — referenced from each consumer."
---

# Canonical: Auto-Learnings Extraction

Used by `/implement` Phase 7, `/follow-up` Phase 6, and `/debug` step 7. Other pipelines that auto-extract learnings should adopt this canonical as they are converted.

## What we capture (preferred tier)

Bias hard toward **flow, architectural, and recurring-mistake** learnings — things that would change *how* a future session approaches a class of problem:

| Tier | Save? | Examples (good shape) |
|------|-------|----------------------|
| **A. Architectural / cross-cutting** | YES — primary target | "Auth state must be derived from server session, never duplicated to client storage" / "Background job retries amplify rate-limit failures — debounce upstream" |
| **B. Flow / process** | YES | "Migrations on this codebase must be tested against a production-shape dataset, not the seed file" / "When CI fails on snapshot tests, regenerate locally before debugging — flakes are common" |
| **C. Recurring-mistake patterns** | YES | "Treating null and undefined as interchangeable causes silent bugs in this stack" / "Adding feature flags without an off-ramp accumulates dead branches" |
| **D. User corrections of approach** | YES (high-signal) | "User prefers small bundled PRs over salami-slicing for refactors in this area" |
| **E. Single-file behavior detail** | NO — re-derivable | "interface User has a `createdAt` field of type Date" — anyone can read the file |
| **F. Specific values / IDs / paths** | NO — drift fast | "Timeout is set to 5000ms in config.json" |
| **G. Trivial / obvious** | NO | "Use TypeScript strict mode" |
| **H. One-shot facts that won't recur** | NO | "PR #234 had a typo in the README" |

**Mapping tiers to JSONL `category`:** A/C → `pattern` or `anti-pattern`; B → `pattern` or `gotcha`; D → `decision`. The schema is defined in `agents/knowledge-agent.md` Principle 5.

## Quality gates (apply in order — fail any → drop)

1. **Reusable across ≥2 contexts?** If this rule only ever applies to the file you just changed, it's not a learning — it's a comment. Drop.
2. **Non-trivial?** Could a teammate derive this by reading the affected code? If yes, drop.
3. **Generalizable?** Try to restate the finding ONE LEVEL UP — as an architectural pattern, flow rule, or class-of-bugs prevention. If you cannot generalize, the finding is too narrow → drop. If you can, **save the generalized form**, not the raw specific.
4. **Verified?** Based on user feedback, test evidence, or direct observation — not speculation.
5. **Not duplicate?** Check existing learnings/memory first. UPDATE rather than append if related entry exists.

## The Reflect → Abstract → Generalize pre-pass

For each candidate learning, do this two-step transform before saving:

- **Reflect:** What concrete event triggered this? (a bug, a correction, a CI failure)
- **Abstract:** What was the *category* of mistake or insight?
- **Generalize:** Restate as a rule that would apply to a future, *different* instance of the same category.

Example:
- Raw: "The `useUserData` hook returned undefined for 200ms after login because we read from localStorage before the auth context hydrated."
- Generalized (save this): "Hooks that read from auth-derived storage must wait on the auth context's hydration signal — direct storage reads race with rehydration."

If you cannot complete the Generalize step, the learning is too narrow. Drop it.

## What NOT to save (stop-list)

Never write to learnings.jsonl or promoted memory:

- Specific interface/type field shapes ("the Task type has a `priority: number`")
- Single-file implementation behaviors that re-reading the file would reveal
- Hard-coded values, IDs, paths, port numbers, env-var names without principle
- One-off bug fixes with no transferable pattern
- Decisions captured in the commit message or PR description (those are the durable record)
- Anything the user can find faster with `git log` or `grep`

If you find yourself writing the file path INTO the learning text as the load-bearing part, it's probably stop-list material.

## Storage routing

- **Architectural / flow / cross-cutting → `.geniro/knowledge/learnings.jsonl`** (searchable across sessions by knowledge-retrieval-agent)
- **User-preference / collaboration corrections → auto-memory `feedback_*.md`** (per the user's profile, not project-wide)
- **Project-wide ongoing-work facts → auto-memory `project_*.md`**
- **Skip if nothing genuinely novel was discovered** — empty extraction is the correct outcome for routine sessions.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "But this specific fact was important" | Important to *this* session ≠ reusable. The commit message captures session-specific facts. |
| "The user might want to see this later" | They have `git log` for that. The knowledge base is for transferable rules. |
| "I'll save it 'just in case' it's useful" | Bloat causes the model to ignore the whole base. Empty is better than noisy. |
| "Specific is better than vague" | False dichotomy. The opposite of "vague platitude" is "concrete trigger conditions," not "narrow code fact." A good learning is concrete in its trigger but general in its scope. |
| "I can't generalize this, but it's still real" | A finding you can't generalize is by definition not a learning — it's a fact. Facts go in commits, not memory. |

---

## How skills reference this

Each consumer uses the canonical opener verbatim:

> Follow the canonical rubric in `skills/_shared/learnings-extraction.md`. Bias hard toward flow, architectural, and recurring-mistake learnings; do NOT save narrow interface/field shapes, single-file behaviors, or facts re-derivable by reading the code. Apply the Reflect → Abstract → Generalize pre-pass before every save: if you cannot restate the finding one level up, drop it.

Then add skill-specific context (where to save, when to skip).
