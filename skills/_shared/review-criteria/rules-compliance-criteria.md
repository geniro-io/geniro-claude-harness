# Rules-compliance review criteria

The authored-rule-citation class of the `conventions` dimension (the conventions reviewer spawn reads this file alongside `conventions-criteria.md`; see that file's §What to check step 1). Checks whether the diff obeys the project's OWN explicitly-authored rule files — the rules a human wrote to govern how code in this repo is written. Distinct from the dimension's modal-pattern class (`conventions-criteria.md` — patterns inferred by sampling the codebase) and from `spec-compliance` (the plan/spec for this one change). Every finding here quotes the exact rule and names the file it lives in.

## Contents

- §1 Rule-file sources
- §2 Path-scope matching
- §3 What to flag
- §4 Severity
- §5 What NOT to flag
- §6 Checklist

## 1. Rule-file sources

Your prompt carries an `AUTHORED RULE FILES:` slot holding the orchestrator's own discovery result — one path per line, or the sentinel `none found`. It is authoritative: review against exactly those paths and Read each one. Discover the files yourself with Glob only when the slot did not arrive at all, using the table below.

**Report the outcome as `authored-rules=` in your Dimension Summary's `Context loaded:` line.** Values per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The load report: `read` when you opened the listed files (the normal case — the slot names paths, so you still read them), `slot` if a whole rule body arrived inline and needed no read, `absent` on the `none found` sentinel, `unreadable` when a listed path failed to open.

This item is not the same load as `project-rules`, and collapsing them loses the one that matters here. `project-rules` is your Step 1.6 read of the two `.geniro/instructions/` files; `authored-rules` is this slot — the repo's own rule files, which no other item in that line records. A conventions report without it cannot show this class ran at all, and `absent` when the repo does ship rule files is a slot the orchestrator composed wrong, which it can only fix if you say so.

| Source | Path(s) | Scope |
|---|---|---|
| Claude Code project rules | `CLAUDE.md` (root + nested), `.claude/rules/**/*.md` | `.claude/rules/*.md` may declare `paths:` frontmatter globs (file-scoped); `CLAUDE.md` is global |
| Cursor rules (modern) | `.cursor/rules/**/*.mdc` | each `.mdc` has frontmatter `globs:` + `alwaysApply:` — honor them |
| Cursor rules (legacy) | `.cursorrules` | global |
| Windsurf | `.windsurfrules`, `.windsurf/rules/**` | global / per-file |
| GitHub Copilot | `.github/copilot-instructions.md` | global |
| Generic agent rules | `AGENTS.md`, `.agents.md` | global |

## 2. Path-scope matching

A rule applies to a changed file ONLY when the file is in the rule's declared scope:

- A `.cursor/rules/*.mdc` with `globs: ["src/**/*.ts"]` applies only to changed files matching that glob; `alwaysApply: true` → all files. A `.mdc` with neither `globs` nor `alwaysApply: true` (description-only / agent-requested / manual) is NOT auto-attached by Cursor — treat it as advisory and do not apply it repo-wide, or a rule the author deliberately scoped out becomes a false positive.
- A `.claude/rules/*.md` with `paths:` frontmatter → applies only to matching files; without `paths:` → all files.
- Global files (`CLAUDE.md`, `.cursorrules`, `.windsurfrules`, `AGENTS.md`, `.github/copilot-instructions.md`) → every changed file.

Flagging a file for a rule outside its declared scope is a false positive — the rule's author scoped it deliberately. Match scopes before checking.

## 3. What to flag

For each changed file, for each in-scope rule, check the diff against the rule's concrete requirement. Flag a violation when new or changed code contradicts a checkable rule. Each finding:

- Quote the exact rule (file + the rule line or sentence).
- Cite the diff line that violates it.
- State the violation in one sentence.

Checkable rule examples: "use the repo logger, never `console.log` in `src/`", "no default exports", "API handlers validate input with zod", "every component ships with a test", "imports ordered std / third-party / local".

## 4. Severity

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md`. A rule violation's severity follows the IMPACT of breaking the rule, not the bare fact that it is a rule:

- Rule encodes a correctness / security invariant (input validation, auth, no-secrets-in-source) → up to HIGH / CRITICAL.
- Rule encodes a maintainability convention → MEDIUM.
- Stylistic preference, or a rule the author marked advisory / optional → LOW.

Do NOT escalate every violation to HIGH because "it's a rule." A repo that bans `console.log` has a LOW finding when one slips into a script, not a HIGH.

## 5. What NOT to flag

- Files outside a rule's declared path-scope (§2).
- Process / workflow rules that code cannot violate ("open a PR for every change", "squash before merge").
- Pre-existing violations in lines the diff does not touch — review the diff, not the whole repo.
- Vague / aspirational rules with no checkable criterion ("write clean code", "be consistent") — not actionable.
- A restatement of a repo-modal pattern — this authored-rule-citation class owns the explicit-rule citation; cite the rule here and let the modal-pattern class (`conventions-criteria.md`) skip the duplicate.

## 6. Checklist

- [ ] Discovered all present rule files (Claude, Cursor `.mdc` + legacy, Windsurf, Copilot, AGENTS)
- [ ] Parsed path-scopes; applied each rule only to in-scope changed files
- [ ] Every finding quotes the exact rule + cites the violating diff line
- [ ] Severity calibrated by impact of breaking the rule, not by "it's a rule"
- [ ] No findings outside rule scope; no vague or process-only rules flagged
