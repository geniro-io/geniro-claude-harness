# Reviewer agent — reference

Companion to `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md`. Detail the reviewer reads while scoring. Not an agent — nothing spawns this file.

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
