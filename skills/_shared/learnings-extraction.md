---
name: learnings-extraction
description: "Canonical doctrine for the auto-learning extraction step that runs at the end of every pipeline + discovery skill (/implement Phase 3, /debug Phase 3, /refactor Phase 3, /plan, /onboard, /investigate, /review). Single source — referenced from each consumer. Canonical L2 emit helper: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.sh`."
---

# Canonical: Auto-Learnings Extraction

Used by every pipeline + discovery skill at its terminal auto-emit step per M2 §5.3 trigger table: `/implement` Phase 3 (M4 §13.2), `/debug` Phase 3 (M7 §3.3 `diagnosis`), `/refactor` Phase 3 (M8 §3.5 `discovery` + `pitfall`), `/plan` (M5 `decision`), `/review` (M6 §5b `pitfall`), `/onboard` (M9 §7.3 `discovery`), `/investigate` (M9 §10.5 `discovery`). The canonical L2 emit helper is `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.sh`.

## What we capture (preferred tier)

Bias hard toward **flow, architectural, and recurring-mistake** learnings — things that would change *how* a future session approaches a class of problem:

| Tier | Save? | Examples (good shape) |
|------|-------|----------------------|
| **A. Architectural / cross-cutting** | YES — primary target | "Auth state must be derived from server session, never duplicated to client storage" / "Background job retries amplify rate-limit failures — debounce upstream" |
| **A2. Architectural-prevention (post-mortem)** | YES — high signal from `/debug` and `/refactor` | "Cache invalidation bug would not occur if cacheKey were derived from a single source of truth — extract to a CacheKey value type at the seam" / "This race condition class disappears if writes go through a single serialized actor — use the existing JobQueue adapter for new write paths" |
| **B. Flow / process** | YES | "Migrations on this codebase must be tested against a production-shape dataset, not the seed file" / "When CI fails on snapshot tests, regenerate locally before debugging — flakes are common" |
| **C. Recurring-mistake patterns** | YES | "Treating null and undefined as interchangeable causes silent bugs in this stack" / "Adding feature flags without an off-ramp accumulates dead branches" |
| **D. User corrections of approach** | YES (high-signal) | "User prefers small bundled PRs over salami-slicing for refactors in this area" |
| **E. Single-file behavior detail** | NO — re-derivable | "interface User has a `createdAt` field of type Date" — anyone can read the file |
| **F. Specific values / IDs / paths** | NO — drift fast | "Timeout is set to 5000ms in config.json" |
| **G. Trivial / obvious** | NO | "Use TypeScript strict mode" |
| **H. One-shot facts that won't recur** | NO | "PR #234 had a typo in the README" |

**Mapping tiers to JSONL `category`:** A/C → `pattern` or `anti-pattern`; A2 → `architectural-prevention` (new category, see schema below); B → `pattern` or `gotcha`; D → `decision`. See "JSONL schema" appendix below for the per-category field structure.

### When A2 (architectural-prevention) fires

Tier A2 is the canonical capture for **post-mortem insights from `/geniro:debug` §3.3 (M7 L2 auto-emit) and `/geniro:refactor` §8.5 (M8 L2 auto-emit)** — situations where a confirmed root cause OR a surfaced refactor opportunity points to a *design change* that would prevent the *class* of issue. Unlike Tier A (which states an architectural rule), A2 names the specific design change as the prevention. Use the canonical vocabulary from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/architecture-vocabulary.md` (depth, seam, adapter, leverage, locality) to describe the change so multiple skills can recognize and apply it.

**Promotion to ADR:** if the prevention design meets the ADR criteria in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` (hard to reverse + surprising + genuine trade-offs), the learning entry SHOULD also propose an ADR. The two are not mutually exclusive: the learning is the searchable summary; the ADR is the durable record.

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

- **Architectural / flow / cross-cutting → `.geniro/knowledge/learnings.jsonl`** (searchable across sessions by knowledge-retrieval-agent) — resolve the path prefix via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A so writes land in the main worktree, not a linked worktree's gitignored tree.
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

---

## JSONL schema

Single source of truth for the structure of `.geniro/knowledge/learnings.jsonl` entries (consumed by the auto-extraction step in every pipeline + discovery skill — /implement, /plan, /review, /debug, /refactor, /onboard, /investigate; auto-replaces the dropped `/learnings` skill per master plan §60).

### Base entry format

Each entry is a single-line JSON object:

```json
{
  "id": "L1",
  "category": "pattern|gotcha|anti-pattern|architectural-prevention|decision|recipe",
  "learning": "One-sentence specific learning",
  "verified": true,
  "session": "2026-04-03-batch-optimization",
  "source": "Code inspection + testing",
  "counter": 0,
  "files": ["batch-processor.ts"],
  "keywords": ["performance", "async", "javascript"],
  "context": "Discovered when optimizing batch-processor.ts",
  "code_example": "// optional: code snippet showing the pattern"
}
```

### Validation checklist

Before storing, an entry must pass:

- [ ] **Reusable across ≥2 contexts?** (Not pinned to a single file or identifier.)
- [ ] **Has a concrete trigger condition?** (WHEN does this fire? Concrete trigger ≠ narrow scope.)
- [ ] **Survived the Generalize pre-pass?** (Restated one level up. If you can't, drop.)
- [ ] **Verified?** (User feedback, tests, or direct observation — not speculation.)
- [ ] **Actionable?** (A future agent can read this and take concrete action in a different context.)
- [ ] **Non-obvious?** (A teammate cannot derive it by reading the affected code.)

If any check fails, drop the entry (or revise it until it passes).

### Per-category field structures

#### Pattern entries (recurring solution to a common problem)

```json
{
  "type": "pattern",
  "title": "Middleware authentication chain pattern",
  "description": "Stack of auth middleware evaluators, each can reject or pass to next.",
  "when_to_use": "When multiple authentication strategies (JWT, OAuth, API key) are supported",
  "implementation": "Use Express middleware composition with early-return on failure",
  "example_file": "auth/middleware.ts",
  "trade_offs": "Increased indirection vs. clarity and testability"
}
```

#### Gotcha entries (surprising behavior or edge case that caused bugs)

```json
{
  "type": "gotcha",
  "title": "Database connection pool exhaustion under load",
  "description": "Without connection.end() in finally block, connections leak and pool exhausts",
  "how_discovered": "Production incident: timeouts after 5 minutes under load",
  "root_cause": "Promise rejection bypassed finally block cleanup",
  "solution": "Use connection pool with built-in timeout and always close in finally",
  "file_reference": "db/connection.ts (lines 12-28)",
  "severity": "Critical"
}
```

#### Anti-pattern entries (what NOT to do and why)

```json
{
  "type": "anti-pattern",
  "title": "Synchronous file reads in request handlers",
  "description": "Using fs.readFileSync() in Express route handlers blocks event loop",
  "why_bad": "All concurrent requests wait for disk I/O, causing cascading timeouts",
  "what_to_do_instead": "Use fs.promises.readFile() with async/await",
  "impact": "100ms disk read blocks all traffic; with async, unrelated requests proceed",
  "example_wrong": "const data = fs.readFileSync(path); res.json(data);",
  "example_right": "const data = await fs.promises.readFile(path); res.json(data);"
}
```

#### Architectural-prevention entries (post-mortem design insight)

```json
{
  "type": "architectural-prevention",
  "title": "Cache-key drift across consumers caused stale-permission bug",
  "trigger_event": "User-permission cache returned stale data after role change",
  "root_cause": "Each consumer constructs cacheKey independently; one omitted userId",
  "design_change": "Extract CacheKey value type at the cache seam; consumers must build keys via the type's constructor (deepens the cache module, narrows the seam)",
  "vocabulary": ["seam", "depth", "adapter"],
  "prevents_class_of": "Cache-correctness bugs from drifted key construction",
  "promote_to_adr": false,
  "files_affected_at_root_cause": ["src/cache/user.ts", "src/services/permission.ts"]
}
```

Set `promote_to_adr: true` when the design change meets all 3 ADR criteria from `improvement-routing.md`. The receiving skill then proposes an ADR alongside the learning entry.

#### Decision entries (architectural or technology choices)

```json
{
  "type": "decision",
  "title": "Chose PostgreSQL over MongoDB for user data",
  "context": "Building user management service, needed transactions and schema enforcement",
  "options_considered": [
    { "option": "MongoDB", "pros": "flexible schema, horizontal scaling", "cons": "no transactions, eventual consistency" },
    { "option": "PostgreSQL", "pros": "transactions, schema enforcement, ACID", "cons": "vertical scaling, operational overhead" }
  ],
  "decision": "PostgreSQL",
  "rationale": "User data requires ACID guarantees; schema enforcement prevents bugs",
  "trade_offs": "Higher operational complexity, but eliminates class of data consistency bugs",
  "date": "2024-03-15",
  "decision_maker": "Tech lead review"
}
```

#### Recipe entries (step-by-step instructions for common tasks)

```json
{
  "type": "recipe",
  "title": "How to add a new API endpoint",
  "steps": [
    "1. Define request/response types in types/api.ts",
    "2. Add route to routes/index.ts with auth middleware",
    "3. Implement handler in handlers/[name].ts",
    "4. Add integration test in tests/integration/[name].test.ts",
    "5. Update API docs in docs/api.md",
    "6. Run type check and linter before PR"
  ],
  "checklist": ["Types defined", "Route added", "Handler implemented", "Tests pass", "Docs updated"],
  "typical_time": "30-45 minutes",
  "common_mistakes": [
    "Forgetting to add route to main router",
    "Skipping type definitions and adding any",
    "Not testing error cases"
  ]
}
```
