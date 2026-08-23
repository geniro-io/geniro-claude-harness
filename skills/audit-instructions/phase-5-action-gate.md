# Phase 5 — Action gate (steps)

Read on Phase 5 entry from `/geniro:audit-instructions` SKILL.md; the spine's invariants and budgets stay binding here.

Use AskUserQuestion: "The audit found N issues across your AI instruction files (N₀ leaked secrets or unsafe directives, N₁ instructions that mislead agents, N₂ cross-tool contradictions, ...). How should I proceed?" with options: "Fix critical issues now (Recommended)" (secrets, unsafe directives, and misleading instructions — the top two tiers just rendered) / "Fix everything — every tier" / "Let me pick findings" / "Report only — I'll handle fixes separately".

The critical-only option carries `(Recommended)` because it is the smallest change set that closes every safety and correctness defect, so it is the one the user can still review end-to-end. "Fix everything" is a first-class option, not a fallback — say what it costs (more agents, far more files touched, all in one fix round) and let the user choose. When the run carries whole-surface deletion proposals, say in the question that those are asked one by one afterwards whichever option is picked, or "Fix everything" reads as having authorized them.

- **Deletion path (D4's surface-level-subtraction proposals):** these split off from whatever the user chose above and are walked one at a time per §Deletion gate below — including under "Fix everything", which approves fixes, not removals (the no-blanket-deletion invariant). Approved deletions then join the fix path as their own scope.
- **Fix path:** group approved findings into **strictly disjoint file scopes** — two agents editing one file overwrite each other, and a shared instruction file is where a fix round loses work silently. Name each agent's scope as an allowlist and name the files other agents hold, so a finding that spans a boundary gets reported back rather than reached for. Then run the finding-ownership invariant's ownership check before spawning: every approved finding appears in exactly one agent's list, every file the findings touch falls inside exactly one allowlist, and any finding or file with no owner is echoed and assigned. Spawn one agent per group in ONE response (`model="sonnet"` ceiling per SKILL.md §Subagent tiering — one tier for the batch, cheaper when every approved finding is a textual edit), with the finding rows, the report path as the finding source of truth, and the constraint set: edit only the approved findings, no scope creep, preserve each file's format contract (frontmatter fields, glob syntax). Max 1 fix round — surviving failures go back to the user. Then run the round out per the reference §Fix-round execution.
- **Pick path:** present findings per tier with multi-select AskUserQuestion calls (≤4 options per call; chain calls past the cap), then run the fix path on the selection.
- **Report only:** proceed to cleanup.

## Deletion gate

Walk the whole-surface proposals one at a time. Per proposal, render the explanation as its own chat message and then fire a lean `AskUserQuestion`, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering, in the visual language of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md`.

The render carries the four things the finding had to establish, plus what the user is left with:

- **What it is and where it lives** — the file or section named in plain terms, with its path.
- **The case it exists for, and how often that case arises here** — the reason someone wrote it, not a guess at their intent.
- **What it costs** — its word count and whether that is paid every session or only when its scope attaches.
- **What covers that ground afterwards** — the other surface carrying the same rule, or a plain statement that nothing will and no run will report it.
- **Whether it stands alone** — or only holds together with another proposal in this set, which the user has to decide as one.
- **What a session looks like once it is gone** — the observable difference, so the decision is about agent behavior rather than about a file.

Options: "Keep it" / "Delete it" / "Shrink it instead" / "Explain further". Mark whichever of keep-or-delete the evidence actually supports as `(Recommended)`, per that helper's §Recommended-label policy — a gate that recommends deletion by default spends the user's attention to obtain a signature, which is the same net-negative shape the surface-level-subtraction check exists to find. "Shrink it instead" is the honest middle when the cost is real but the ground is still needed; it converts the finding into a line-level one that re-enters the fix path as an edit.

Record the ones the user keeps in the report's subtraction sweep as considered-and-kept, with the reason.

**Re-verify:** after the fix round, re-run the Phase 1 battery over the touched files and Read each changed location to confirm the finding is resolved — a fix to a frontmatter file must still parse.

**Cleanup & commit:** delete the current slug's directory `.geniro/state/audit-instructions/<slug>/` per the helper §Cleanup contract (never glob sibling slug directories — they belong to parallel pipelines on other branches). The dated report survives outside the slug dir. Offer via AskUserQuestion: "Commit the instruction-file fixes?" — "Commit and push (Recommended)" / "Commit only" / "Skip". Stage only the instruction files changed by approved fixes (never `git add -A`); the report stays local under `.geniro/state/` and is never staged or force-added (a plugin hook blocks `git add -f` on `.geniro/` paths). Follow the repo's commit style; never `--no-verify` / `--amend`.
