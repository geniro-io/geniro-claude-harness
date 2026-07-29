# launch_config — canonical cross-skill schema

Single source of truth for the optional `launch_config:` block in spec.md frontmatter. `/geniro:plan` produces it (when the user opts in at the end of planning); `/geniro:implement` reads it at Step 0 and applies it, skipping the corresponding setup questions. Because it is a cross-skill contract, it lives here rather than in either skill's files — every producer and consumer cites this file so the shape, the enum values, and the version rule cannot drift between them.

## Contents

- [When this applies](#when-this-applies)
- [The block](#the-block)
- [Field semantics](#field-semantics)
- [Doctrine boundary — setup only, never safety](#doctrine-boundary--setup-only-never-safety)
- [Version & backward-compat](#version--backward-compat)
- [Producer / consumer contract](#producer--consumer-contract)
- [Validator contract](#validator-contract)
- [Lockstep file set](#lockstep-file-set)

## When this applies

`launch_config:` is opt-in and spec-driven only. It captures `/geniro:implement`'s launch settings at plan time so `/implement` runs without re-asking. Three rules govern when it is read:

- **Opt-in.** The block is written when the user explicitly pre-defines implement settings at the end of planning OR by passing launch modifiers (workspace / ship / `freshness:` / `--deep`) to `/plan`. A user who declines (and passes no launch modifiers) gets no block, and planning proceeds unchanged.
- **Spec-driven only.** An inline-task `/implement` run (no spec.md) has nothing to pre-define — there is no frontmatter to carry the block, so the launch questions fire interactively as they do today.
- **Absent = ask interactively.** When `launch_config:` is absent from a spec, `/implement` asks its Step 0 setup questions exactly as it does now. The block is purely additive: removing it changes nothing about today's behavior.

## The block

```yaml
launch_config:                 # optional; present only when the user pre-defined implement settings at plan time
  workspace: new-branch        # new-branch | current-branch | worktree | here
  deep_mode: false             # true | false
  branch_freshness: rebase     # merge | rebase | skip
  ship_mode: draft-pr          # commit-no-push | draft-pr | ready-for-review | stop-after-review
  tracker_status: move-to-in-progress  # move-to-in-progress | leave-unchanged; OPTIONAL even within the block — written only when the spec has a linked tracker ticket (workflow_refs[] non-empty)
```

Each key pre-answers exactly one existing `/implement` setup question:

| Key | Enum | Pre-answers |
|---|---|---|
| `workspace` | `new-branch` \| `current-branch` \| `worktree` \| `here` | `/implement` Step 0 workspace question (the same choices the `new-branch` / `current-branch` / `worktree` / `here` `$ARGUMENTS` modifiers select). |
| `deep_mode` | `true` \| `false` | The Standard/Deep depth chooser; `true` is equivalent to passing `--deep`. |
| `branch_freshness` | `merge` \| `rebase` \| `skip` | The strategy when the branch is behind the default branch. |
| `ship_mode` | `commit-no-push` \| `draft-pr` \| `ready-for-review` \| `stop-after-review` | The Ship-gate behavior — maps to the four sanctioned Ship modifiers. |
| `tracker_status` | `move-to-in-progress` \| `leave-unchanged` | `/geniro:implement` Step 0 workflow-status question ("Move to In Progress?"). Written only when the spec carries a linked tracker ticket (`workflow_refs[]` non-empty). |

## Field semantics

### `workspace`

Pre-answers the Step 0 workspace question. The four values match the existing `$ARGUMENTS` workspace modifiers: `new-branch` (cut a fresh branch), `current-branch` (work in place), `worktree` (cut a worktree), `here` (work in the current directory as-is). It pre-answers the question that would otherwise fire; it does NOT override an active auto-continue or resume signal. When `/implement` detects a prior-task continuation (smart auto-continue), that signal wins — the user is already mid-task, and a plan-time workspace pre-set is not a directive to abandon the in-flight workspace.

### `deep_mode`

Pre-answers the Standard/Deep depth chooser. `true` runs the deeper mode (multi-angle self-review plus the pre-edit fact-check, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md`) — equivalent to `--deep`. `false` runs standard depth. The chooser does not fire when this key is present.

### `branch_freshness`

Pre-sets the strategy used when the branch is behind the default branch (`merge` / `rebase` / `skip`), per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md`. The STRATEGY is pre-answered, but a real merge or rebase **conflict still surfaces interactively**. The "offer, never silently auto-run a conflicting history rewrite" principle is honored for the conflict case: a clean fast-forward applies the pre-set strategy without asking, but a conflict stops for the user. A plan-time choice of `rebase` is consent to attempt a rebase, not blanket consent to resolve arbitrary conflicts the user has not seen.

### `ship_mode`

Maps to the four sanctioned Ship-gate bypass modifiers:

- `commit-no-push` — commit, do not push.
- `draft-pr` — push and open a draft PR.
- `ready-for-review` — push and open a PR ready for review.
- `stop-after-review` — stop before any commit or push.

The existing commit-grade safeguards STILL apply regardless of `ship_mode`. A push to a shared or default branch, or a push updating an open PR that was reached via a handoff, is commit-grade and still gates. `ship_mode` pre-answers the routine Ship choice; it does not waive the safeguards that protect shared history.

### `tracker_status`

Pre-answers the Step 0 workflow-status question (`/geniro:implement` "Move to In Progress?"). `move-to-in-progress` is consent to auto-confirm the kickoff status move the workflow file's `### On task start` block would offer; `leave-unchanged` declines it. This key is captured at plan time ONLY when the spec carries a linked tracker ticket (`workflow_refs[]` non-empty) — with no ticket there is nothing to move, so the question is not offered and no key is written. It is therefore optional even within a present block: its absence never fails validation.

The pre-set is consent to the move the workflow file would offer, NOT an unconditional tracker write. `/geniro:implement` still threads it through the workflow file's status-conditional gate — the move is skipped when the task is already In Progress and reframed (or omitted) in other states, exactly as an interactive answer would be. It is a no-op when no tracker ref is in scope at `/implement` time, and fail-open when the workflow MCP is unavailable (logs a warning and proceeds without the transition, mirroring an interactive "Yes"). This stays inside `/geniro:implement`'s tracker-mutation authority — a kickoff status transition, never a ticket creation; `/geniro:plan` only records the preference, it never writes to the tracker.

## Doctrine boundary — setup only, never safety

`launch_config` pre-answers SETUP only. It does NOT and CANNOT pre-authorize the genuine safety gates that fire on a real event. The following gates remain Always-WAIT and fire only when their trigger condition is actually met:

- **New-dependency adoption** — the library-adoption gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/library-reuse-audit.md`). Adopting a new external dependency always asks.
- **Runaway-scope escalation** — the not-converging / budget-blown escalation. A diff that crosses the spec's declared budget still stops for the user.
- **Handoff open-questions gate** — unresolved `open_questions[]` from a prior review/debug/resolve handoff still gate before any edit.
- **Spec-challenge-on-drift gate** — a refuted cited claim or a blocking feasibility risk found by the pre-edit fact-check still gates.

Why these stay interactive: each protects an irreversible or scope-expanding action — installing a dependency, blowing past the agreed file/line budget, proceeding past an unresolved question, or building on a claim the live code has since contradicted. The plan cannot foresee which of these a run will hit, so a plan-time pre-set is not informed consent for them. A clean spec-driven run triggers none → it runs uninterrupted; a run that hits one still stops for the user. The pre-set removes the routine setup friction without weakening the gates that exist to catch the unforeseen.

## Version & backward-compat

Bump `geniro_schema_version` to `m5-v4` when `launch_config` is present. Backward-compat is the load-bearing rule, mirroring the `workflow_refs[]` m5-v* rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workflow-refs-schema.md`:

- `m5-v1` (legacy, no `workflow_refs` / no `launch_config`), `m5-v2`, `m5-v3` (chain-enrichment fields), and `m5-v4` (`launch_config` present) are ALL valid downstream.
- Every reader that accepts `m5-v1` / `m5-v2` / `m5-v3` must also accept `m5-v4`. The `launch_config` additions are purely additive and optional, so a reader rejecting an `m5-v4` value would lose the structured pre-set and fall back to interactive setup — never a hard error.
- A spec at `m5-v4` may still carry `launch_config` as the only m5-v4-distinguishing block; the chain-enrichment fields remain orthogonal and optional.
- Adding a key to the `launch_config` block (e.g. `tracker_status`) is a further additive-optional change WITHIN `m5-v4` — it does NOT bump the version, because an absent or unknown key already falls through to the interactive question (§When this applies). Do not bump to a new version for a new launch_config key.

## Producer / consumer contract

**Producer — `/geniro:plan`.** `/plan` populates the block from EITHER the end-of-plan opt-in answer OR the launch modifiers (workspace / ship / `freshness:` / `--deep`) passed in `$ARGUMENTS`; both persist to state.md `approvals[]` under category `launch_config` (the modifier-sourced entry notes its source was `$ARGUMENTS`). The `launch_config` block is written into spec.md frontmatter inside the SAME approval-time full-spec `atomic_state_write` rewrite that flips `lifecycle: draft` → `lifecycle: approved`, so it commits atomically with the approved spec — there is no window where an approved spec exists without its pre-set, or a pre-set exists against a not-yet-approved spec. `/plan` does not act on the values; it only records them for `/implement`. When the spec carries a linked tracker ticket, the block also carries `tracker_status` (the kickoff move-to-In-Progress pre-answer); with no linked ticket the key is omitted.

**Consumer — `/geniro:implement`.** When `launch_config` is present, Step 0 applies it and records the equivalent `approvals[]` entries (`deep_mode_choice`, `ship_mode`, the workspace choice, and — when `tracker_status` is set — `implement_workflow_status`), each noting the source is the spec's `launch_config`, and skips the corresponding setup questions. The recorded source matters for the session-restore and compaction paths — a restored run must distinguish a choice the user made interactively this session from one carried in from the plan. Every safety gate listed under the doctrine boundary continues to fire on its own trigger; the recorded pre-sets cover setup only.

## Validator contract

A shape-only check mirrors the `workflow_refs_consistency` check in `${CLAUDE_PLUGIN_ROOT}/skills/plan/validator-checks.md`:

- **When present:** verify each key's value is within its enum — `workspace` ∈ {`new-branch`, `current-branch`, `worktree`, `here`}; `deep_mode` ∈ {`true`, `false`}; `branch_freshness` ∈ {`merge`, `rebase`, `skip`}; `ship_mode` ∈ {`commit-no-push`, `draft-pr`, `ready-for-review`, `stop-after-review`}; and, when the optional `tracker_status` key is present, `tracker_status` ∈ {`move-to-in-progress`, `leave-unchanged`} (key-presence-guarded — its absence inside a present block is valid, since it is written only when the spec had a linked tracker ticket). An out-of-enum value returns `fail` — the block is structurally broken.
- **When absent:** skip the check entirely. Older specs without the block stay valid.
- **Guard by `geniro_schema_version`:** the check runs only when `launch_config:` is present (which implies `m5-v4`); it never fires on a spec that omits the block, so a legacy `m5-v1` / `m5-v2` / `m5-v3` spec is never failed for not carrying it.

## Lockstep file set

These files describe one cohesive contract — when the `launch_config` shape, an enum value, the version rule, or the producer/consumer wiring changes, update all of them in the same change so a future editor cannot leave them inconsistent:

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` (this file) — the canonical schema.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` — the frontmatter example carrying the block.
- `${CLAUDE_PLUGIN_ROOT}/skills/plan/validator-checks.md` — the shape-only enum check.
- `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-8-user-approval.md` — the end-of-plan opt-in write (§8.3.5 capture, §8.4 step 2 write).
- `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` — the opt-in question wording.
- `${CLAUDE_PLUGIN_ROOT}/skills/implement/SKILL.md` — the Step 0 read-and-apply path.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` — the `approvals[]` category schema.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-context.md` — the plan→implement priming contract.
- `${CLAUDE_PLUGIN_ROOT}/ARCHITECTURE.md` — the cross-skill architecture overview.
- `${CLAUDE_PLUGIN_ROOT}/CLAUDE.md` — the skill-set summary rows for `/plan` and `/implement`.
