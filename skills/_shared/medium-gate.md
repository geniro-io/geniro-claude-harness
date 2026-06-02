# MEDIUM Inclusion Gate

Canonical AskUserQuestion gate that fires at the top of any code-review fix loop when MEDIUM-severity findings exist. Replaces the older "Drop Medium" / "Skip MEDIUM" policy — auto-dropping MEDIUMs treats real bugs as advisory. See `ARCHITECTURE.md` §Operational Rules.

This file is the single source of truth. Skills cite this file; do NOT inline-paste the gate logic.

## When this fires

Fires at the top of any code-review fix loop when MEDIUM-severity findings exist.

Skip silently when zero MEDIUM findings exist after deduplication, or when no reviewer-agents ran.

## Always-WAIT contract

This gate is **Always-WAIT** in every mode and lane (Auto, Fast, Light included). Auto-handling MEDIUMs (drop or auto-fix) is unsafe — the user has context (e.g., an integration test or migration step already covers the gap, making the MEDIUM informational; or the MEDIUM is a real regression that must block) the orchestrator does not.

Empty `AskUserQuestion` answer = upstream Claude Code bug; fall back to plain text and re-ask. Never auto-default.

## Required AUQ shape — outer gate (single-select)

- **`header`**: `"MEDIUMs"`.
- **`question`**: multi-line markdown — render the count and a one-line digest of each finding so the user can decide without drilling in:

  ```
  N MEDIUM finding(s) detected:
  - <SEVERITY> `path:lines` — <short title> — <one-line why-matters>
  - ...

  How do you want to handle them?
  ```

  Pull the digest from each finding's persisted body fields (severity / `File:` / finding-title / `Why this matters:`) per the per-finding line schema in `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` Phase 5 — the same fields PRODUCT-DECISION findings persist. If more than 6 MEDIUMs exist, show the first 6 and append `… and N more — pick "Pick which to include" to see the full list`.

- **`options[]`** (3 single-select):
  - `label`: `"Include all in fix loop"` — `description`: `"Treat MEDIUMs equivalently to CRITICAL/HIGH for this fix round — every MEDIUM is fed to the fixer agent."`
  - `label`: `"Pick which to include"` — `description`: `"Chain a multi-select question listing each MEDIUM with its full body — selected MEDIUMs join the fix loop, the rest go to the Ship summary."`
  - `label`: `"Skip — note in Ship summary only"` — `description`: `"Do NOT fix any MEDIUM this round — record them in the Ship summary so the user has a documented backlog. Use when fallbacks already cover the gap."`

## Required AUQ shape — inner picker (only when user picks "Pick which to include")

Chain a multi-select AUQ following `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Multi-select pick loop verbatim:
- `multiSelect: true`, `header: "Pick MEDIUMs"`, `question: "Pick MEDIUMs to include in the fix loop"`.
- One option per MEDIUM finding, with `preview` showing the full body (Evidence / Suggested fix / Confidence / Origin) per the per-finding-question.md preview block.
- Cap-extension: when more than 4 MEDIUMs exist, batch across multiple chained AUQ calls (≤4 per call) per the per-finding-question.md cap-extension rule. Never split or drop options to fit a single question.

## Result handling

After the gate resolves:
- **"Include all in fix loop"** → every MEDIUM finding is appended to the CRITICAL/HIGH pool the fixer agent receives. The fixer treats them with the same priority. Re-review fires for every dimension that had any finding (CRITICAL/HIGH or promoted-MEDIUM).
- **"Pick which to include"** → user-selected MEDIUMs join the fix-loop pool; non-selected MEDIUMs are written to a `## Deferred MEDIUM` section in the review-feedback artifact and surface in the Ship summary line "Review feedback addressed".
- **"Skip — note in Ship summary only"** → all MEDIUMs are written to `## Deferred MEDIUM` and surface in the Ship summary; none enter the fix loop.

Promoted MEDIUMs lose their MEDIUM tag in the fix-loop pool — the fixer agent sees them as "user-promoted findings" and treats them with the same fix-and-re-review treatment as CRITICAL/HIGH. Severity is preserved in the artifact for audit trail.

## Persisted-fields requirement

For the gate to render bodies correctly, the artifact that carries MEDIUM findings into this gate (e.g. `<task-dir>/review-feedback.md` for `/geniro:implement` Phase 3 self-review, `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` for `/geniro:review` Phase 5) MUST persist each MEDIUM finding's body sub-fields (severity / `File:` / finding-title / `Why this matters:` / `Evidence:` / `Suggested fix:` / `Confidence:` / `Origin:`) per the per-finding line schema in `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` Phase 5. This mirrors the existing PRODUCT-DECISION persistence requirement, extended to MEDIUM rows.

## Why this exists

Auto-dropping MEDIUMs creates two failure modes:
1. **Real bugs ship.** The reviewer-agent's MEDIUM definition is "Bug or deviation from standards impacting reliability/clarity" (`agents/reviewer-agent.md` §Output Format) — these are real issues, just not blocking. Dropping them silently means real bugs reach production with no audit trail.
2. **Visibility lost.** The Ship summary previously showed only CRITICAL/HIGH counts — the user had no way to even see what was dropped. The Always-WAIT gate forces the count + digest to surface at the moment of decision.

The cost is one AUQ call per fix-loop entry when MEDIUMs exist. Skipped silently when zero MEDIUMs — matches the PRODUCT-DECISION gate's skip-when-empty behavior.
