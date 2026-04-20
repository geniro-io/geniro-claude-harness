---
name: geniro:learnings
description: "Use when a session produced corrections, gotchas, or decisions worth remembering. Extracts learnings into categorized JSONL with quality gates. Do NOT use for trivial sessions with no surprises."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Grep, AskUserQuestion]
argument-hint: "[optional: topic or area to focus on]"
---

# Learnings: Continuous Learning from Sessions

Use this skill at the end of a session to extract learnings and improve future work. Captures patterns, gotchas, decisions, and anti-patterns. Stored in `.geniro/knowledge/learnings.jsonl` for reference across sessions.

## Relationship to Built-in Memory

Claude Code has a native auto-memory system (`~/.claude/projects/<proj>/memory/`) that stores user preferences, project context, and workflow habits automatically. **This skill is complementary, not redundant.** Native memory handles general context; this skill handles **structured technical learnings** — categorized, searchable, counter-tracked entries that need selective retrieval by the `knowledge-retrieval-agent`. Do not duplicate what native memory already captures (user preferences, build commands, general project context).

## Extraction Categories

Extract learnings into one of four categories:

| Category | Example (architectural / flow shape — preferred) | Reusability |
|----------|---------|-------------|
| **Pattern** | "Auth-derived state must wait on the auth context's hydration signal — direct storage reads race with rehydration" | High – architectural rule |
| **Gotcha** | "Background-job retries amplify upstream rate-limit failures — debounce at the producer, not the consumer" | High – cross-cutting |
| **Decision** | "Prefer server-derived session state over duplicating to client storage in this stack — simpler invalidation, fewer race conditions" | Medium – architectural choice |
| **Anti-Pattern** | "Adding feature flags without an off-ramp accumulates dead branches that can't be safely removed later" | High – flow-level rule |

**All learnings must (apply gates in order — fail any → drop):**
1. Be **reusable across ≥2 contexts** (not a fact about one file)
2. Be **non-trivial** (not re-derivable by reading the affected code)
3. Be **generalizable** — restate the finding one level up as an architectural pattern, flow rule, or class-of-bugs prevention. If you cannot, drop it.
4. Be **verified** (user feedback, test evidence, direct observation — not guessed)
5. Have **no duplicates** (UPDATE existing entries rather than appending)

"Specific" here means **concrete trigger conditions** ("when X happens, do Y because Z"), NOT narrow code facts. A good learning is concrete in its trigger but general in its scope. See `skills/_shared/learnings-extraction.md` for the canonical doctrine.

## Learnings.jsonl Format

Append-only JSON Lines file (one JSON object per line):

```jsonl
{"id":"L1","category":"pattern","learning":"Before scaffolding new automation, scan existing scripts/CI for the same intent — duplicating intent across script + workflow file causes drift","verified":true,"session":"2026-04-03-auth-work","source":"user correction after redundant script proposed","counter":0,"files":["package.json","ci/**"],"keywords":["scripts","scaffolding","drift"]}
{"id":"L2","category":"gotcha","learning":"FIFO queues without reprioritization invert priority under bursty load — model bursts as a separate concern from steady-state","verified":true,"session":"2026-04-03-queue-debug","source":"discovered via load testing","counter":0,"files":["src/services/*queue*"],"keywords":["queue","backpressure","load"]}
{"id":"L3","category":"anti-pattern","learning":"Filter at the data layer, not the application — fetching-then-filtering bounds throughput by network, not by index","verified":true,"session":"2026-04-02-performance","source":"identified during optimization","counter":0,"files":["src/services/**"],"keywords":["data-access","performance","filtering"]}
{"id":"L4","category":"decision","learning":"Token lifetime should be derived from the trust class of the device, not a global default — short for browser, long for mobile, near-zero for shared kiosks","verified":true,"session":"2026-04-01-auth","source":"user preference communicated","counter":0,"files":["src/auth/**"],"keywords":["JWT","auth","tokens"]}
```

**Fields:**
- **id**: Auto-incremented (L1, L2, L3...)
- **category**: pattern | gotcha | decision | anti-pattern
- **learning**: One-sentence, specific learning
- **verified**: true (confirmed) | false (hypothesis)
- **session**: Date and topic of session where learned
- **source**: How was this verified? (user feedback, testing, docs, code inspection)
- **counter**: How many times has this been referenced? (for relevance ranking)
- **files** (optional): Glob patterns for affected files — enables selective retrieval
- **keywords** (optional): Topic tags for keyword-based filtering

## Workflow: Extract → Validate → Store

### 1. Extract (5–10 min)
Review the session conversation and identify:
- Did the user correct you? → Learning
- Did you discover something unexpected? → Learning
- Did you avoid a pattern you should remember? → Learning
- Did you make a decision with tradeoffs? → Learning

Extract 3–5 learnings per session. More is often noise.

### 2. Validate (2 min)
For each learning, ask:
- **Concrete trigger conditions?** "When operations on a table fall under the slow-query threshold, check whether foreign keys are indexed" — concrete WHEN+WHAT+WHY, not "database performance matters." Concreteness ≠ narrowness; the rule should still apply across files.
- **Verified?** Not a guess, but confirmed via code, testing, or user feedback. If uncertain, use the `AskUserQuestion` tool to confirm with the user before storing.
- **Non-Trivial?** Would a junior dev benefit? Or is it obvious?
- **Reusable?** Could this apply to future work in this codebase or similar projects?
- **Unique?** Not already in learnings.jsonl?

Drop learnings that fail these gates.

### 3. Store
Append to `.geniro/knowledge/learnings.jsonl` with:
- Auto-incremented ID (L1, L2, L3...)
- Clear one-sentence learning
- Verified flag
- Session date and focus
- How it was verified
- counter=0 (tracks reference count over time)

### 4. Use Across Sessions
- Before implementing, scan learnings.jsonl for gotchas or patterns
- Reference relevant learnings in your work
- Increment counter when a learning helps
- Update learnings if you find better formulations

## Compliance — Do Not Pollute Knowledge

| Your reasoning | Why it's wrong |
|---|---|
| "This is a useful general lesson" | "Write tests" and "use types" are noise. Only store non-obvious, project-specific insights. |
| "I'm pretty sure this is correct" | Unverified guesses become trusted rules. Only store confirmed findings. |
| "I'll skip the duplicate check" | Duplicate learnings dilute signal. Always cross-check before storing. |
| "I'll add file paths and function names to make it concrete" | Concreteness ≠ narrowness. Pin the rule to architectural shape, not to a single identifier. A learning that names one file applies to one file. |
| "This applies broadly with no concrete trigger" | Vague platitudes ("communication matters") are noise. Add a concrete trigger condition (when X), but keep the rule general in scope. |
| "The user didn't mention this but it seems important" | Learnings without user input or test evidence are guesses. Verify first. |

## Definition of Done

For each improvement session, confirm:

- [ ] Conversation reviewed for corrections, surprises, decisions
- [ ] 3–5 learnings extracted (or 0 if session had no new insights)
- [ ] Each learning passes quality gates (specific, verified, non-trivial, reusable)
- [ ] Learnings.jsonl checked for duplicates
- [ ] New learnings appended to `.geniro/knowledge/learnings.jsonl`
- [ ] Each learning has: id, category, verified, session, source
- [ ] No generic or unverified lessons stored

---

## When to Use This Skill

**Use `/geniro:learnings`:**
- End of a complex or learning-rich session
- Made a mistake that should be remembered
- User corrected you on a pattern or convention
- Discovered a gotcha the hard way
- Made a significant decision with tradeoffs
- Want to improve future sessions on this codebase

**Don't use:**
- Simple bug fix with no learnings
- Session was straightforward with no surprises
- Just documenting a feature (use `/geniro:features`)
- Need to refactor code (this skill is not for code changes)

---

## Example Extraction

### Session: Auth System Debugging
Conversation included:
- User: "Oh, we already have a JWT validation middleware in middleware/auth.ts"
- You: [Implemented redundant validation]
- You: [Tested and found task table uses UNIX timestamps]
- User: "Yes, all timestamps are seconds since epoch for compatibility with legacy system"

**Extracted Learnings (after Reflect → Abstract → Generalize):**
1. **Pattern:** "Before adding a cross-cutting concern (auth, logging, validation), scan the request-pipeline middleware layer first — duplicating cross-cutting logic into handlers is the most common architectural drift in this codebase"
   - Category: pattern
   - Verified: true (user corrected; pattern confirmed across multiple route files)
   - Source: "user feedback + code inspection"

2. **Gotcha (generalized from a specific timestamp finding):** "When integrating with legacy systems, treat the data shape contract as load-bearing — units (seconds vs ms), encodings (UTF-8 vs UTF-16), and null semantics drift silently and cause class-of-bugs failures"
   - Category: gotcha
   - Verified: true (root-caused via schema + legacy-code review)
   - Source: "user clarification + schema inspection"

3. **Decision:** "Cross-cutting validation belongs at the boundary (middleware), not at the call site — pushes the consistency contract to one place and removes per-handler drift risk"
   - Category: decision
   - Verified: true (codebase convention)
   - Source: "code inspection + user confirmation"

(Note: a raw finding like "Task table uses UNIX seconds" would be DROPPED unless generalized — it's re-derivable from the schema file. Save the *class* of insight, not the specific value.)

All three pass quality gates and get added to learnings.jsonl.

---

## Phase 4: Session Document (optional)

Create a session summary document **only if** the session was complex enough to warrant one (multi-step debugging, architectural decisions, significant discoveries). Skip for simple bug fixes or straightforward implementations.

### Session Document Format

Write to `.geniro/knowledge/sessions/YYYY-MM-DD-<topic>.md`:

```markdown
# Session: [Topic]
**Date:** YYYY-MM-DD
**Type:** feature | debug | refactor | investigation
**Status:** completed | partial | blocked

## Summary
[2-3 sentences: what was done, what was the outcome]

## Key Decisions
- [Decision 1]: [rationale]
- [Decision 2]: [rationale]

## Discoveries
- [What was learned about the codebase]
- [Unexpected behaviors found]
- [Patterns identified]

## Files Changed
- `path/to/file.ts` — [what changed and why]

## Unresolved Items
- [Anything left open for future sessions]

## Related
- Learnings: [L12, L45] (IDs from learnings.jsonl)
- Debug: [.geniro/debug/HYPOTHESES.md] (if debugging was involved)
- Spec: [.geniro/planning/<branch-name>/spec.md] (if implementation was involved)
```

### When to Create Session Documents

- After any `/geniro:implement` session — captures architecture decisions, conventions discovered, and integration notes
- After any `/geniro:debug` session — captures root cause, misleading signals, and environment-specific quirks
- After any `/geniro:refactor` session — captures what was restructured and why
- After significant `/geniro:follow-up` sessions — captures any non-obvious fixes or discoveries
- **Not needed** for trivial changes (typo fixes, config tweaks)

### Retrieval

Future sessions can search these documents via the `knowledge-retrieval-agent`:
- Pipeline skills like `/geniro:implement` and `/geniro:debug` spawn it automatically before starting work
- It searches learnings.jsonl, session artifacts, debug history, and planning docs
- Returns condensed, citation-rich findings so you don't re-discover known information

Add retrieval to the start of complex skills (implement, debug, refactor) — check what's already known before starting fresh.

## Learning Lifecycle

```
Session → Extract → Validate → Store → Use → Reference → Increment Counter
    ↓                            ↓
Session Doc                  learnings.jsonl
    ↓                            ↑
  sessions/                 knowledge-retrieval-agent
    ↓___________________________|
         (cross-session retrieval)
```

**High-counter learnings** (referenced multiple times) are most valuable.
**Zero-counter learnings** might be outdated and can be pruned.

## Tips for High-Quality Learnings

- **Concrete trigger, general scope:** ✓ "When a job queue lacks reprioritization, model bursts as a separate concern from steady-state" vs. ✗ "queues matter" (vague) and ✗ "the OrderQueue uses FIFO" (narrow — re-derivable from the file)
- **Verifiable:** ✓ "Found in code + tested" vs. ✗ "seems important"
- **Actionable:** ✓ "Check middleware/ before writing validation" vs. ✗ "middleware exists"
- **Memorable:** One sentence, clear. If you need a paragraph, it's too complex.

---

## Examples

### Example 1: End of Auth Feature
```
/geniro:learnings auth
```
→ Scan conversation for learnings about JWT, tokens, password hashing
→ Extract pattern: "Hash passwords with bcrypt, never plain text or basic algorithms"
→ Extract gotcha: "Token refresh endpoint needs _both_ access and refresh tokens"
→ Store in learnings.jsonl
→ Future sessions can reference this for auth work

### Example 2: End of Performance Optimization
```
/geniro:learnings
```
→ Review entire conversation
→ Extract anti-pattern: "Never SELECT * then filter in app—filter in SQL"
→ Extract pattern: "Add indexes on foreign keys before adding relationships"
→ Extract decision: "Use query caching for stable lookups (cache invalidation on 5 min TTL)"
→ Store all three, increment counter for existing similar learnings

### Example 3: Quick Review After Bug Fix
```
/geniro:learnings
```
→ Quick scan for key learnings
→ Extract gotcha if found, otherwise store nothing
→ Focus on "did I learn something that prevents future bugs?"
