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

Route review findings only to project-owned files — do NOT suggest edits to `${CLAUDE_PLUGIN_ROOT}/…` (criteria files, agent prompts, plugin hooks are global and overwritten on update; use `/improve-template` for those).

| What was discovered | Route to | Why |
|---|---|---|
| Recurring false positive revealing undocumented convention | **CLAUDE.md** | Document the convention so reviewers don't flag it |
| Non-obvious insight about codebase quality | **Knowledge** (`.geniro/knowledge/learnings.jsonl`) | Context for future reviews |
| Security pattern that should be blocked automatically in this project | **Project rules/hooks** (CI, lint, project-local hooks) | Automated enforcement beats manual detection |
| Review rule the user enforced manually (e.g., "always check X") | **Custom instructions** (`.geniro/instructions/review.md`) | Persists as review-specific rule |

Present via `AskUserQuestion` with header "Improvements": "Apply all" / "Review one-by-one" / "Skip". Group by target. If no improvements found, skip silently.

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
