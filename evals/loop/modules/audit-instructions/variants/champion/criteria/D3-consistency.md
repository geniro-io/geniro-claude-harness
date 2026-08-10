## D3 — Cross-tool consistency

**Scope:** every surface, `.geniro/instructions/*.md` included. **Method:** reviewer seeded with D1's same-rule candidates.

Checks:
1. **Direct contradictions.** One surface says X, another — or a later section of the same file — says not-X: commit-message rules, formatting, test-first policy, tool choices → T2.
2. **Threshold divergence.** The same limit with different values across surfaces (line length, coverage floor, file-size cap) → T2.
3. **Mirror drift.** Where `AGENTS.md` (or another surface) is symlinked to or generated from `CLAUDE.md`: verify the symlink resolves or the generated copy matches its source. Drift → T2. The mirroring itself is endorsed — flag only the drift.
4. **Hand-maintained duplicates that agree.** The same rule copied across surfaces with no symlink or generation mechanism → T4, even while the copies match: agreement today is drift tomorrow. Propose one home (the richest surface, usually `CLAUDE.md` or `AGENTS.md`) with the others pointing at it, or a mirroring mechanism.
5. **Material guidance divergence.** The same topic covered non-contradictorily but differently enough that an agent on one tool would surprise a teammate on another → T4, judgment call. Tool-specific phrasing carrying the same rule is not a finding (§Do-not-flag list).

