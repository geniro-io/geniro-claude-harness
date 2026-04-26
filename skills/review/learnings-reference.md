# Review Skill Reference

Companion to `skills/review/SKILL.md`. Contains the full procedures and worked example extracted from SKILL.md to keep it under 500 lines.

## Phase 5b — Learn & Improve (full procedure)

After delivering the review summary, extract knowledge and suggest improvements. **Skip this phase when `/geniro:review` is called as a sub-phase within `/geniro:implement`** (the parent pipeline handles learnings in Phase 7). Only run when `/geniro:review` is invoked standalone.

### Extract Learnings

Scan the review findings for patterns worth remembering:
- **Recurring anti-patterns** found across multiple files → save as `project` memory (helps future implementations avoid the same mistakes)
- **False positives** where a finding looked real but wasn't (framework-specific pattern, intentional deviation) → save as `feedback` memory (improves future review accuracy)
- **User corrections** on review findings — "that's not a bug, it's intentional because..." → save as `feedback` memory (calibrates future reviews)

Before writing, check if an existing memory covers this topic — UPDATE rather than duplicate. Skip if nothing novel was discovered.

### Suggest Improvements (project scope only)

Follow the canonical routing in `skills/_shared/improvement-routing.md`. Review runs typically surface: (a) **recurring false positives revealing undocumented coding conventions / style or naming patterns** → **`.claude/rules/<scope>.md`** with `paths:` glob frontmatter (Anthropic-native, file-scoped — auto-loads when matching files are touched, so future reviewers see the convention; do NOT route to CLAUDE.md — code rules belong in scoped rules files, not always-loaded context); (b) **non-obvious insights about codebase quality** → `learnings.jsonl`; (c) **security patterns that should be auto-blocked** → project rules/hooks; (d) **skill-behavior review rules the user enforced manually** (e.g. "always check X in this skill") → `.geniro/instructions/review.md`. Plugin-internal paths (`${CLAUDE_PLUGIN_ROOT}/…`) are out of scope — use `/improve-template`.

## Example Workflow

```
$ review src/auth/login.js src/auth/logout.js
Analyzing 2 files with 47 lines changed...

Spawning parallel reviewers (5–6, +design when UI files present):
  - Bugs reviewer (async pattern detection)
  - Security reviewer (injection points, auth flows)
  - Architecture reviewer (module dependencies)
  - Tests reviewer (coverage analysis)
  - Guidelines reviewer (code style)

[Reviewers execute in parallel: ~5-8 seconds]

Running relevance filter against repo conventions...
- 10 of 12 findings kept
- 2 filtered (over-engineering for this repo's complexity level)

Judge pass on 10 findings...
- 8 pass confidence threshold (>=80)
- 2 filtered (< 80% confidence)

Validating 4 Critical/High findings (per-finding validators)...
- 3 confirmed, 1 rejected (false positive — mitigating context found)

## Review Summary
Files: 2 | Issues: 7 (1 CRITICAL, 2 HIGH, 4 MEDIUM)

## CRITICAL ISSUES (1)
[SQL Injection in login.js:34-38] ...

## HIGH PRIORITY (2)
[Missing logout validation] ...
[Race condition in session] ...

## MEDIUM PRIORITY (4)
[Inconsistent error messages] ...
[Missing JSDoc comments] ...
...

Overall Assessment: APPROVE WITH CHANGES

Persisting findings to .geniro/review-findings-state.md
Suggested next stage: /geniro:implement (1 CRITICAL → recommend full pipeline)
```
