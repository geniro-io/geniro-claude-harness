# Flags & presets — cross-skill catalog

The single catalog of every flag and modifier that pre-sets an otherwise-interactive question across `/geniro:plan`, `/geniro:implement`, and `/geniro:review`. A flag or modifier removes routine setup friction by answering a question in advance; it never pre-authorizes a safety gate. The safety gates listed in the final section fire on their own trigger regardless of any flag.

## Contents

- [How to read these tables](#how-to-read-these-tables)
- [/geniro:plan](#geniroplan)
- [/geniro:implement](#geniroimplement)
- [/geniro:review](#geniroreview)
- [Non-suppressible safety gates](#non-suppressible-safety-gates)

## How to read these tables

Each row names a flag or modifier, the values it accepts, what it presets, and which interactive question that pre-set removes. Modifiers are matched semantically from `$ARGUMENTS` (no strict CLI grammar). When two conflicting modifiers appear (e.g. `new-branch` and `current-branch`), last-occurrence wins and a soft notice names both detected variants.

## /geniro:plan

`argument-hint: "<topic-string-or-design-doc-path> [--prd] [--deep] [--artifact]"`

| Flag / modifier | Values | What it presets | Which question it skips |
|---|---|---|---|
| `--prd` | present / absent | Turns on the problem-discovery interview (problem / evidence / target user / hypothesis / success metrics / MoSCoW) and the spec's optional `## Problem & Evidence` section. | Adds the Phase 0.5 interview; absent = no problem-first pre-phase. |
| `--deep` | present / absent | Deepens the approach search (wider candidate set) and adds majority-vote verification of the spec's cited claims. Higher quality, higher cost. | The Standard/Deep depth question (asked at the Phase 3 clarify wrap-up). |
| `--artifact` | present / absent | Turns on the live, auto-updating visual plan artifact published to a private page as the plan develops. | The artifact opt-in question. |
| `new-branch` / `current-branch` / `worktree` / `no-worktree` (`here`) | one value | Pre-fills the spec's `launch_config` workspace setting so `/geniro:implement` runs hands-free without asking where to land its edits (`no-worktree` and `here` both map to the `here` enum value). | `/implement`'s workspace setup question (deferred — applied when `/implement` consumes the spec). |
| `don't push` / `no push` / `commit only` / `draft only` / `ready-for-review` / `stop after review` | one value | Pre-fills the spec's `launch_config` ship setting (commit-no-push / draft PR / ready-for-review PR / stop before commit). | `/implement`'s ship-mode question (deferred). |
| `freshness:merge` / `freshness:rebase` / `freshness:skip` | one value (colon form only) | Pre-sets the strategy for a branch behind the default branch. Feeds both `/plan`'s own Phase 1 branch-freshness offer and the spec's `launch_config`. | `/plan`'s Phase 1 branch-freshness offer AND `/implement`'s branch-freshness question (deferred). |

The launch modifiers above pre-fill the spec's `launch_config` block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`. A clean fast-forward applies a `freshness:` strategy without asking; a real merge or rebase conflict still surfaces (see the safety-gate section).

## /geniro:implement

`argument-hint: "[task description | spec.md path | empty to resume | 'continue'] [--deep]"`

| Flag / modifier | Values | What it presets | Which question it skips |
|---|---|---|---|
| `new-branch` / `current-branch` / `worktree` / `no-worktree` (`here`) | one value | Forces the workspace path — cut a fresh branch, work in place on the current branch, cut a worktree, or run in the current directory. | The Step 0 workspace question. |
| `--deep` | present / absent | Deepens two phases — a multi-angle self-review with verification escalated only where the call is contested, and a 3× fact-check of the spec's cited claims before the first edit. | The Standard/Deep depth question (folded into the Step 0 workspace question). |
| `--no-adversarial` | present / absent | Disables the adversarial-tester spawn in the self-review phase. | No question — drops the extra reviewer slot in the review round. |
| `don't push` / `no push` / `commit only` | one value | Commit succeeds, no push. | The ship-mode question. |
| `draft only` / `draft PR` / `open draft` | one value | Push and open a draft PR. | The ship-mode question. |
| `ready PR` / `ready-for-review` / `non-draft PR` | one value | Push and open a PR ready for review. | The ship-mode question. |
| `stop after review` | present / absent | Exit before any commit; surface clean review status as the deliverable. | The ship-mode question. |

A bare `open PR` / `with PR` (no draft-vs-ready qualifier) does NOT skip the ship-mode question — it routes through the gate so the safe draft default stays visible.

**Spec `launch_config` block (spec-driven runs).** When `/geniro:plan` wrote a `launch_config` block into the spec, `/implement` reads it at Step 0 and applies workspace / deep_mode / branch_freshness / ship_mode (and, when the spec has a linked tracker ticket, tracker_status) at once, skipping each corresponding setup question. The block is the cross-skill contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`. An inline-task run (no spec) has no block, so the setup questions fire interactively.

## /geniro:review

`argument-hint: "[files, diff range, branch, or PR ref (#N, URL)] [--plan <path>] [--deep]"`

| Flag / modifier | Values | What it presets | Which question it skips |
|---|---|---|---|
| `--deep` | present / absent | Reviews each check from several angles and majority-verifies findings where the call is contested. Higher quality, higher cost. | The Mode / depth question (the depth pick is folded into the Phase 1 Mode question). |
| `--plan <path>` | a spec path | Supplies the spec so the specification-compliance reviewer can check the diff against it. This is a context input, not a question pre-set. | No question — adds spec context to the reviewers. |
| `worktree` / `no-worktree` / `here` / `current-branch` / `new-branch` | one value | Forces the workspace path the review inspects. | The Step 0 workspace question. |

## Non-suppressible safety gates

These gates fire on a real triggering event regardless of any flag, modifier, or `launch_config` pre-set. Setup is presettable because the answer is known at invocation time and the action is reversible; a safety gate is not, because each one protects an irreversible or scope-expanding action whose trigger the plan cannot foresee — so a pre-set is not informed consent for it. The full doctrine is in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` §"Doctrine boundary — setup only, never safety".

- **New-dependency adoption** — adopting a new external library always asks before any dependency is added.
- **Runaway-scope / budget escalation** — a diff that crosses the spec's declared file/line budget stops for the user.
- **Handoff open-questions** — unresolved open questions from a prior review, debug, or resolve handoff gate before any edit.
- **Spec-challenge-on-drift** — a refuted cited claim or a blocking feasibility risk found by the pre-edit fact-check stops for the user.
- **Shared-branch / open-PR ship** — a push to a shared or default branch, or one updating an open PR reached via a handoff, is commit-grade and still gates even under a ship-mode pre-set.
- **Real merge / rebase conflict** — a clean fast-forward applies the pre-set freshness strategy silently, but an actual conflict surfaces interactively; a strategy pre-set is consent to attempt, not to resolve unseen conflicts.
- **`/review` re-review gate** — on a re-run, the scope / depth / repeat-finding decision is always re-asked, never silently inherited.
- **`/review` test-confirmation gate** — when testable findings exist, the offer to author failing tests for them fires and waits for approval.
