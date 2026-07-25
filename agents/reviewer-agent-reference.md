# Reviewer agent — reference

Companion to `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md`. Detail the reviewer reads while scoring and while writing findings. Not an agent — nothing spawns this file.

## Confidence rubric

Cited from the agent body §Confidence Scoring. The percentage is an advisory hint, not the admission filter — see that section for why.

| Score | Meaning | Example |
|-------|---------|---------|
| 80-100 | Definitely real, certain fix needed | Race condition with clear evidence; SQL injection in user input |
| 60-79 | Very likely real, should fix | Missing null check that could crash; hardcoded secret in code |
| 40-59 | Probably real but uncertain | Possible logic error, unclear without more context |
| 20-39 | Might be real, low priority | Nitpick; unclear if this matters in context |
| 0-19 | Probably false positive | Code looks odd but is actually correct |

**Scoring adjustments:**
- Evidence is explicit (you can point to the exact line): +10
- Pattern exists elsewhere in codebase (systemic): -10 per individual, but flag as systemic
- Mitigating code exists nearby: -20
- Criteria explicitly calls this out: +10

## Anti-patterns

Cited from the agent body §Anti-patterns to avoid. Each shape below either gets the finding dropped at the orchestrator's filter or makes it unusable once it reaches a reader.

### Scope creep
- Do not flag issues outside your dimension
- If you notice a critical issue in another dimension, mention it in a single line at the end under "Cross-dimension notes" — but do not score it

### Performative findings
- Do not report findings just because the criteria mentions a category
- Only report if you have specific evidence in the code
- False positives waste engineer time and erode trust in review

### No-action observations
- A finding must call for an action — a fix, a test, or a decision. If your conclusion is "this is fine" / "no change needed" / a neutral informational note, it is not a finding: put it under Dimension Summary → "Notable clean areas", or leave it out
- A no-action comment posted to a PR is noise the author cannot act on — it reads as review for its own sake and dilutes the findings that do need attention

### Assumption over evidence
- "This looks like it could be a problem" is not a finding
- Every finding needs a specific file, line number, and code snippet
- If you can't point to the exact issue, don't report it

### Vague fixes
- "Consider improving this" is not a suggested fix
- Show the actual code change or specific approach needed
- If you don't know the fix, say so — the finding is still valid

### Self-report trust
- Do not skip verification because a comment says "this is intentional"
- Comments can be outdated or incorrect
- Always verify with your own code reading

### Internal references in finding bodies
- Your `Why this matters:`, `Suggested fix:`, `description`, and `recommendation` text can be posted verbatim to a public PR comment, where the author has no access to the project's internal incident log, learnings store, or your briefing
- When a finding restates a known failure mode from your briefing (an incident report, a learnings entry), describe it in plain language — "the documented backdated-migration-ordering failure" — and do NOT cite the internal ID (`incident 4`, `learning B.1.5`, the `B.x.y` numbering). The ID indexes a log the reader cannot open; it reads as noise
- If a shareable link to the incident exists in your briefing, include the link instead of the bare ID
