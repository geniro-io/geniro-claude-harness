# M10c — `/geniro:actions` redesign

**Milestone:** M10 (operational skills) — part **c** of 4. Companion to M10a (`/setup`), M10b (`/instructions`), M10d (`/update`).

**Status:** Decided 2026-05-19. Builds on M1 (T3 `.geniro/actions/` PERSISTENT/CRUD tier), M3 (no compaction-survival concern — actions are user-authored files), M4 §13.5 (per-phase ACI), M10b (shared validate-mode rule set per OQ-M10b-1).

**Cross-cutting closures landing here:**

- **P-M10-1** — connector safety properties for `.geniro/actions/*`. Per **Q4 decision**: minimal 3-property enforcement (`name`, `description`, `risk_class`); the other 5 properties (scoped, untrusted-by-default, logged, disabled-when-unused, version-pinned) are documented as guidelines but not validated at the schema level.

---

## 1. Purpose

A CRUD frontend + runner over `.geniro/actions/` — user-authored workflow-helper actions stored as plain Markdown files. Five operations: `list`, `create`, `edit`, `run`, `delete`. Stateless: every invocation is single-transaction (per M10a Q5 — only `/setup` gets a state file).

**What is an action?** A `.md` file at `.geniro/actions/<slug>.md` with YAML frontmatter declaring `name`, `description`, `risk_class`, and a body containing a numbered `## Steps` section. The orchestrator (Geniro) reads the body and follows the steps — actions are NOT auto-registered as slash commands.

**Why a dedicated skill:**

- Users build project-specific automations (Slack release pings, PR finalizers, release checklists) without committing to a heavy DSL.
- AUQ-driven scaffolding ensures users don't omit critical frontmatter or risk-class declarations.
- Run-mode gates execution by `risk_class` — `low` runs unattended, `medium` asks once, `high` requires explicit double-confirmation.
- Cross-platform — pure Markdown + Bash/Read/Write tool surface, no external runtime needed.

**Anti-goal:** No autonomous external-send loop. Every action that calls `mcp__github__*`, network, or `Bash(curl ...)` is `risk_class: high` and AUQ-gated.

---

## 2. Architecture overview

### 2.1 State machine

`/actions` is **stateless** (per M10a Q5). The phase enum below describes runtime flow only — not persisted to disk.

```
init (parse $ARGUMENTS)
  │
  ▼
parse
  │ resolve intent + slug; bare-slug fast-path triggers `run` mode by default
  ▼
execute
  │ branch by mode:
  │   list   → read directory + format table
  │   create → interview + scaffold + validate frontmatter (P-M10-1 minimal)
  │   edit   → external editor OR dialogue-mode (same as M10b §8)
  │   run    → AUQ-gate by risk_class → execute body steps
  │   delete → AUQ-confirm → rm
  ▼
done
       │
       └─ failed (parse failed, slug not found after 3 AUQ rounds, run-mode user aborted, validation rejected by hook)
```

### 2.1.1 Termination case → state mapping

No state file, but failure paths report a structured reason in the final user message.

| Termination cause | Message format |
|---|---|
| User cancelled at any AUQ | `aborted: user cancelled at <step>` |
| Slug resolution failed after 3 AUQ retries | `aborted: slug unresolved after 3 AUQ rounds` |
| Run-mode AUQ rejected (risk_class: high, user picked Cancel) | `aborted: user rejected high-risk action <slug>` |
| Validation rejected on create (frontmatter missing required field) | `aborted: create blocked by validation — <reason>` |
| Action body execution failed mid-step | `failed: action <slug> step <N> returned non-zero exit` |
| Write blocked by file-protection hook | `aborted: file-protection hook blocked write to <path>` |

### 2.2 Loop invariants

Per M4 §2.2:

1. **One result per subagent call** — `/actions` does not spawn subagents in CRUD modes. **Run mode** may spawn an agent if the action body's `## Steps` instructs so (action-author's responsibility — `/actions` is a passthrough orchestrator).
2. **Args validated before exec** — every Write to `.geniro/actions/*.md` preceded by frontmatter validation; every `run` preceded by AUQ-gate matching the action's `risk_class`.
3. **Permission before side-effect** — `risk_class: medium | high` gates execution via AUQ; `risk_class: low` skips the gate but still respects per-step tool-allowlist if declared.
4. **Bounded structured results** — `list` truncates per-action body display at 200 chars (full body shown only via `view <slug>`).
5. **Hard escalation gates** — 3-retry on slug ambiguity → final abort AUQ.
6. **Observations not assumed success** — each step in `run` mode checks return status; failed step transitions to `failed` with step number captured.
7. **Errors as structured observations** — surfaced inline in final message.

### 2.3 Budgets — quality-first framing (per M4 §2.3)

`/actions` has **zero Class-A hard kill caps**.

| Layer | Lever | Why |
|---|---|---|
| **Class-B escalation gates** | 3-retry on slug ambiguity → abort | If user can't disambiguate after 3 rounds, the registry probably needs reshuffling — abort cleanly |
| | Body preview truncation at 200 chars in `list` mode | Long bodies clutter; full body via `view <slug>` or `cat .geniro/actions/<slug>.md` |
| | 3-retry on action body validation failure during `create` (Phase 3.6 in current skill) | Inherited verbatim — three attempts to write a valid action, then abort |
| **Architecture constraints** | Stateless (per Q5) | CRUD ops are single-transaction; runtime is brief; no state coordination needed |
| | One action runs at a time | Action body assumed sequential; concurrent action runs would race against shared resources (PRs, Slack channels). Document, don't enforce |
| **NOT capped** | Action body length, step count, tool-allowlist breadth, AUQ chain depth | Quality-first |

### 2.4 ACI surface per phase

| Phase | Allowed tools | Forbidden tools | Notes |
|---|---|---|---|
| `parse` | `Read`, `Bash` (read-only), `Glob`, `AskUserQuestion` | `Write`, `Edit`, `Bash` (mutating), `Agent` | No mutation in parse |
| `execute` | mode-dependent | mode-dependent | See sub-rules below |
| | **list:** `Read`, `Glob`, `Bash(ls ...)`, `AskUserQuestion` | `Write`, `Edit`, `Agent`, `mcp__*` | Read-only |
| | **create:** `Read`, `Write`, `Bash(mkdir -p .geniro/actions/, grep, echo >> .gitignore)`, `AskUserQuestion` | `mcp__github__*`, network egress, `Agent` | No subagents in create |
| | **edit:** `Read`, `Edit`, `Bash(stat, mv)`, `AskUserQuestion` | `mcp__*`, network egress | |
| | **delete:** `Read`, `Bash(rm)`, `AskUserQuestion` | `Write`, `Edit`, all `mcp__*`, network egress | Per-file `rm` of `.geniro/actions/<slug>.md` is allowed by the `.geniro/` deletion guard |
| | **run:** **determined by the action's frontmatter `allowed-tools:` field**, intersected with the global `/actions` allowed-tools | (whatever is NOT in the intersection) | Action authorship is user-controlled; tool surface is per-action-declared |
| `DONE` | (terminal report only) | (none) | |

**Run mode tool gating** (concrete rule):

```
effective_tool_surface = intersection(
  global allowed-tools for /actions skill,  # from SKILL.md frontmatter
  action frontmatter `allowed-tools:` field,  # user-declared per-action
)
```

Action frontmatter MAY include risky tools (`Bash(curl ...)`, `mcp__github__*`) — these are then AUQ-gated by `risk_class` per §6.3 below.

---

## 3. Scope deltas vs. pre-M10 `/geniro:actions`

### 3.1 Removed

| Removed item | Why |
|---|---|
| Reference to `/improve-template` in skill description | `/improve-template` is meta-tooling not part of 11-skill set; replaced by direct `/instructions edit` for instruction-rule changes; for skill-body changes users edit the plugin repo (out of scope for /actions) |
| Sub-decision "version it" branch on create-conflict | Kept (it's useful), but the `version-pinned` P-M10-1 property is documented (not enforced); users can put `version: v2` in frontmatter optionally |
| Implicit "actions can do anything" tool surface | Replaced by §2.4 explicit ACI table + §6.3 risk-class AUQ gates |

### 3.2 Kept (with adaptation)

| Kept item | Adaptation |
|---|---|
| 5-op CRUD (`list`, `create`, `edit`, `run`, `delete`) | Preserved verbatim |
| Bare-slug fast path in `parse` phase | Preserved — `/geniro:actions slack-release-ping` defaults to `run` mode |
| Interview-driven `create` flow (Q1 Purpose, Q2 When, Q3 Output, Q4 Test) | Preserved + **Q5 added: Risk class** (low/medium/high) |
| Draft-preview AUQ before Write | Preserved verbatim |
| Phase 3.6 validation gate | Adapted — now enforces P-M10-1 minimal 3-prop schema; full check list in §10 |
| Reserved-word slug list | Preserved verbatim (`anthropic`, `claude`, `geniro`, `list`, `create`, `edit`, `run`, `delete`) |
| `version it` conflict resolution | Preserved |
| `.gitignore` re-include of `.geniro/actions/` on create | Preserved |
| Example actions library at `${CLAUDE_PLUGIN_ROOT}/skills/actions/example-actions/` | Preserved |
| Cross-worktree main-repo fallback for slug resolution | Preserved (helps users in worktrees access main-branch actions) |

### 3.3 Added (new in M10c)

| Added item | Source |
|---|---|
| `risk_class: low \| medium \| high` mandatory frontmatter field | P-M10-1 (Q4 minimal) |
| Q5 in create-interview: ask risk class | New |
| Run-mode AUQ gate matching action's `risk_class` (§6.3) | P-M10-1 — risk-classed actions get AUQ-gated; the bare-slug fast path still respects the gate |
| `validate` mode (new — was missing in current skill) | OQ-M10b-1 closure — shared lint rule set with `/instructions validate review-extra` |
| Documentation of 5 unenforced P-M10-1 properties as guidelines (scoped, untrusted-by-default, logged, disabled-when-unused, version-pinned) | Q4 — minimal enforcement, full guideline list documented |
| Final report includes a one-line "L2 emit candidate" if action completed external-send work | Auto-replaces dropped `/learnings` skill pattern (action runs that produced novel state are good `discovery` candidates) |

---

## 4. Decisions recorded so far

| ID | Question | Decision |
|---|---|---|
| **Q1** | Bundle vs split | Split — part c of 4 |
| **Q2** | Phase model | Skill-natural — 3 phases (parse → execute → done), stateless |
| **Q3** | CLAUDE.md split | N/A — `/actions` doesn't write CLAUDE.md |
| **Q4** | Connector safety enforcement depth | **Minimal 3-property** (`name`, `description`, `risk_class`); 5 others documented |
| **Q5** | State file | None — `/actions` is stateless |

Sub-decisions:

| Sub-decision | Resolution |
|---|---|
| Should `risk_class: low` actions skip AUQ entirely? | Yes — `low` = "Bash(echo)", "Bash(ls)", read-only Bash, no network, no PR write. AUQ overhead would be friction with no safety gain |
| Should `risk_class: medium` actions get one AUQ confirmation? | Yes — one click, recommended option = `Run` |
| Should `risk_class: high` actions get one AUQ or two-step confirmation? | One AUQ but with **destructive-action label**: `Run high-risk action (Recommended: Cancel)` — the recommended option is `Cancel`, forcing the user to explicitly pick `Run`. This is the safest single-AUQ pattern |
| What counts as `high`? | External-send (Slack/email/SMS/PR creation/merge), git push, git force-push, file deletion outside `.geniro/`, npm publish, docker push, AWS/GCP/Azure mutations. Documented in create-interview Q5 description |
| What counts as `medium`? | Reading external content (curl GET from non-HTTPS, fetch from internal API), local file mutation outside `.geniro/`, git commit (without push), running tests with side effects (DB seed, integration test against staging) |
| What counts as `low`? | Pure read operations, local Bash with no network, no file mutation outside cwd, displaying or aggregating data |
| Should `/actions validate` exist? | Yes — for parity with `/instructions validate`; shared rule set per OQ-M10b-1 (§10) |
| Should run-mode honor a `--skip-confirm` flag? | No — explicit anti-pattern (rule #4 in P-MP-1 — "Autonomous external sends"). If user wants no-AUQ, they pick `risk_class: low` on create. The flag would let users override the safety net |

---

## 5. Defect inventory (audit 2026-05-19 — before/after)

11 defects identified in current `/actions` SKILL.md (519 LOC). All closed in this redesign.

| # | Defect | Fix |
|---|---|---|
| **D1** | No `risk_class` in frontmatter — actions that wrap `gh pr create`, network calls, etc. run with no risk signal | `risk_class` becomes mandatory; Q5 added to interview; Phase 3.6 validate-gate enforces |
| **D2** | Run-mode has no AUQ gate — once user invokes `/geniro:actions run slack-release-ping`, the action runs to completion with whatever tool surface its frontmatter declares | Run-mode now gates by `risk_class` (§6.3) — `medium` = 1-click confirm, `high` = explicit re-confirm with default option Cancel |
| **D3** | Reference to `/improve-template` (not in 11-skill set) | Removed from skill blurb; replaced by clear scoping ("actions are user-authored workflows; for plugin internals, edit the plugin repo directly") |
| **D4** | No `validate` mode — users discover frontmatter errors only when an action fails at runtime | Added; shared rule set with `/instructions validate review-extra` per OQ-M10b-1 |
| **D5** | P-M10-1 8-property safety model unaddressed | §6.2 documents all 8 properties (3 enforced, 5 documented as guidelines per Q4) |
| **D6** | No master plan reconciliation | §12 added |
| **D7** | No anti-pattern check | §13 added (P-MP-1) |
| **D8** | Body validation rules (Phase 3.6 in current skill) lack the M-doc-style structural enforcement (e.g., `## Steps` must have numbered items, every step is one of the canonical action-step shapes) | §10 specs the full validation rule set with severities matching M10b |
| **D9** | Cross-worktree main-repo fallback (current skill §Bare-slug fast path) silently runs main-worktree action without AUQ | Preserved fallback, but **cross-worktree AUQ is mandatory** before execution (regardless of risk_class) — see §6.3 step 1 |
| **D10** | No L2 emit on completion | §6.3 step 5: after successful run with `external-send: true`, emit L2 `discovery` row (auto-replaces dropped `/learnings`) |
| **D11** | Run-mode currently has no tool-surface intersection check — action frontmatter `allowed-tools:` is advisory only; orchestrator inherits its own tools | §2.4 "Run mode tool gating" — explicit intersection rule; if action declares `Bash(curl)` but global `/actions` ACI doesn't include it, the action fails validate-on-load, not silently mid-run |

---

## 6. Mode: run — **DECIDED**

This is the most-defects-closed mode; details first.

### 6.1 Slug resolution (preserved from current)

1. If `$ARGUMENTS` first token matches an existing `.geniro/actions/<token>.md` → fast-path `run`.
2. Else if `$ARGUMENTS` normalized (lowercase, kebab) matches a file → fast-path `run` with normalized slug.
3. Else if `$ARGUMENTS` is multi-word / quoted / contains whitespace → free-text matching against (slug, description) pairs of installed actions; AUQ confirms before execution.
4. Else if no match → AUQ "Action `<slug>` not found. Did you mean `<closest-match>` (Levenshtein)? Or list all actions?"

### 6.2 Action frontmatter schema (P-M10-1 closure)

```yaml
---
# REQUIRED (P-M10-1 minimal 3-prop enforcement per Q4):
name: <slug>                  # MUST match filename, kebab-case ^[a-z][a-z0-9-]*$
description: "Use when ..."   # one line, ≤250 chars, starts with "Use when"
risk_class: low               # one of: low | medium | high

# OPTIONAL but recommended:
model: inherit                # inherit | haiku | sonnet | opus
allowed-tools: [Read, Bash, AskUserQuestion]  # P-M10-1 "scoped" — documented, not enforced as a hard rule
argument-hint: "[name] [...args]"
created: 2026-04-12           # YYYY-MM-DD; auto-set by /actions create
created-by: geniro:actions

# OPTIONAL P-M10-1 properties (documented as guidelines, not validated):
version: v1                   # P-M10-1 "version-pinned" guideline — useful for action evolution; opt-in
external-send: true           # marks an action that talks to external services (Slack/PR/etc.)
                              # docs: actions with external-send=true SHOULD be risk_class: medium or high
---
```

**P-M10-1 8-property mapping:**

| P-M10-1 property | M10c handling | Enforced? |
|---|---|---|
| 1. namespaced | `name: <slug>` (kebab-case, no reserved words) | ✅ via frontmatter |
| 2. scoped | `allowed-tools:` field; ACI intersection in run mode | ⚠ Documented; not validated to be present (defaults to `inherit`) |
| 3. concise descriptions | `description:` field; ≤250 chars, "Use when" prefix | ✅ via validate-mode |
| 4. untrusted-by-default | Run-mode AUQ gate by `risk_class` | ✅ via §6.3 |
| 5. risk-classed | `risk_class: low \| medium \| high` | ✅ via frontmatter |
| 6. logged | Future: P-X6 observability (deferred candidate); for now, `## Tool log` in `/actions` SKILL.md state... but `/actions` is stateless. Best-effort: action steps that include `Bash(...)` get logged in conversation transcript natively | ⚠ Documented; relies on P-X6 |
| 7. disabled-when-unused | No usage tracking in MVP; documented as user-managed via `/actions delete` | ⚠ Documented |
| 8. version-pinned | Optional `version:` field; preserved on `version it` conflict resolution | ⚠ Documented; opt-in |

### 6.3 Run-mode AUQ-gating ladder

```
Step 1 — Cross-worktree gate (if applicable):
  If slug resolved to main-worktree (not cwd) → AUQ:
    "Action found in main worktree, not current cwd. Use main-worktree copy?"
    Options: [Use main-worktree copy] [Cancel]
  (This fires before the risk_class gate; D9 closure)

Step 2 — Risk-class gate:
  Read action's frontmatter `risk_class`.

  if risk_class == "low":
    Skip AUQ. Proceed to step 3.

  elif risk_class == "medium":
    AUQ:
      "Run action `<slug>` (medium risk)?"
      Options: [Run] [Cancel]
    Recommended option: Run.
    If Cancel → failed (user aborted).

  elif risk_class == "high":
    AUQ:
      "Run action `<slug>` (HIGH risk — confirm explicitly)?"
      Options: [Cancel] [Run anyway]
    Recommended option: Cancel.   # forces explicit Run pick
    If Cancel → failed.

Step 3 — Execute action body:
  Read action body. For each numbered step in `## Steps`:
    - Translate step description to tool call(s).
    - Each tool call uses the intersection of /actions allowed-tools AND action's allowed-tools.
    - If step has a `## AUQ:` or `## Confirm:` annotation, fire AUQ at that step.
    - Capture step output.
    - On non-zero exit or tool failure → halt; transition to `failed` with step number.

Step 4 — Final report:
  Print results to user.
  Format: action name, steps executed, side-effects observed.

Step 5 — L2 emit (D10 closure):
  If action frontmatter declared `external-send: true` AND run succeeded:
    emit one L2 `discovery` row per M2 §5.3:
      {"id":"<uuid>","ts":"<ISO-8601>","type":"discovery","trust":"verified",
       "skill":"actions","tags":["actions","run","<risk_class>"],
       "summary":"ran <slug> (risk=<risk_class>, external=true)",
       "entry":{"slug":"<slug>","side_effects":[...]}}
  Else: no emit (most action runs are not novel-discovery events).
```

Approvals[] persistence does NOT apply to run mode — risk-class AUQs are context-dependent decisions (re-ask each run intentionally; "did I confirm `slack-release-ping` last week" must NOT auto-confirm this week).

---

## 7. Mode: create — **DECIDED**

### 7.1 Interview Q1-Q5 (Q5 is new)

Q1-Q4 preserved verbatim from current skill. Q5 added:

**Q5 — Risk class:** "What is the risk class for this action?"

| Option | Description |
|---|---|
| `low` | Pure read operations: read files, list dirs, aggregate data, display info. No network, no file mutation outside cwd. Runs with no AUQ confirmation. |
| `medium` | Local file mutation, git commit (no push), tests with side effects (DB seed, integration test). External reads (HTTP GET). Runs with 1-click confirm. |
| `high` | External sends (Slack/PR/email), git push, npm publish, docker push, cloud mutations, file deletion outside `.geniro/`. Runs with explicit Cancel-default confirm. |

Recommended option (per scaffold heuristic) is suggested based on Q3's Output answer:

- Q3 = "Reports back to chat only" → suggest `low`
- Q3 = "Writes a file" → suggest `medium`
- Q3 = "Posts to an external system" → suggest `high`
- Q3 = "Multiple side effects" → suggest `high` (worst-case)

### 7.2 Phase 3.6 validation gate (P-M10-1 minimal enforcement)

Inherits from current skill, plus 3 new checks:

| Check | Severity | New? |
|---|---|---|
| YAML frontmatter parses | CRITICAL | preserved |
| `name:` matches filename slug | CRITICAL | preserved |
| `description:` starts with "Use when" | HIGH | preserved |
| `description:` length ≤250 chars | HIGH | preserved |
| No `{{placeholder}}` in body | HIGH | preserved |
| File <500 lines | MEDIUM | preserved |
| `## Steps` section present with ≥1 numbered item | HIGH | preserved |
| **`risk_class:` field present** | **CRITICAL** | **NEW (Q4)** |
| **`risk_class:` value in `{low, medium, high}`** | **CRITICAL** | **NEW** |
| **If `external-send: true`, `risk_class` MUST be `medium` or `high`** | **HIGH** | **NEW (consistency check)** |

On fail: refuse to write; surface failed check(s); offer to re-edit via `AskUserQuestion` (max 3 retry rounds; matches current Phase 3.4 cap).

### 7.3 Scope-specific scaffold examples

(Inherits current examples library at `${CLAUDE_PLUGIN_ROOT}/skills/actions/example-actions/`.)

Add 3 new examples reflecting risk_class levels:

| Example | risk_class | Demonstrates |
|---|---|---|
| `daily-recap.md` | `low` | Aggregates git log + jest output; pure reads, prints to chat |
| `commit-and-pr-summary.md` | `medium` | `git commit` (no push) + AUQ-gated summary draft |
| `slack-release-ping.md` (already exists) | `high` | Curl POST to Slack webhook; high-risk external send |

---

## 8. Mode: edit — **DECIDED**

Inherits from M10b §8 (external editor OR dialogue-mode). Additional rule:

- After every `edit`, automatically run §10 validate-mode against the edited file. If validation fails (CRITICAL/HIGH), surface findings and prompt: `[Open editor again | Save anyway despite warnings | Revert to pre-edit version]`.

The auto-validation does NOT block save; it surfaces. User remains in control.

---

## 9. Mode: delete — **DECIDED**

Inherits from M10b §9 (AUQ confirm + per-file rm). Additional safeguard for `/actions`:

- If the action's `risk_class == high`, the delete AUQ adds a warning line:
  > "This high-risk action will be permanently removed; if it represents critical workflow, consider versioning it first via `/actions edit <slug>` and renaming to `<slug>-archived`."

  Options unchanged: `Confirm delete | Cancel`.

---

## 10. Mode: validate — **DECIDED (OQ-M10b-1 closure)**

### 10.1 Flow

`/actions validate [<slug>]` — accepts optional slug or validates all `.geniro/actions/*.md`. Read-only; never mutates.

### 10.2 Lint rule set (shared with `/instructions validate review-extra`)

Inherits M10b §10.2 rule set for the `description:` field (P-M10-2 rules). Plus the `/actions`-specific checks from §7.2 above.

**Combined rule table:**

| Check | Severity | Source |
|---|---|---|
| YAML frontmatter parses | CRITICAL | current /actions Phase 3.6 |
| `name:` matches filename | CRITICAL | current |
| `description:` starts with "Use when" | HIGH | current + M10b P-M10-2 |
| `description:` ≤250 chars | HIGH | current |
| `description:` mentions adjacent terms (M10b lint preference) | LOW | M10b §10.2 |
| `description:` includes boundary clause ("Skip for ...") | LOW | M10b §10.2 |
| `risk_class:` present and valid | CRITICAL | M10c §7.2 (new) |
| `external-send: true` ⇒ `risk_class: medium|high` | HIGH | M10c §7.2 (new) |
| `## Steps` section present with ≥1 numbered item | HIGH | current |
| No `{{placeholder}}` in body | HIGH | current |
| File <500 lines | MEDIUM | current |
| `allowed-tools:` field present (if action mutates anything) | LOW | M10c (P-M10-1 "scoped" guideline) |
| No references to dropped skills in body | HIGH | M10b §10.2 alignment |

### 10.3 Output format

Same as M10b §10.3:

```
$ /geniro:actions validate

Validation results: 3 actions checked, 1 issue found.

✓ daily-recap.md                  no issues
⚠ slack-release-ping.md           1 HIGH
  └── Line 4: risk_class missing — REQUIRED field per P-M10-1
✓ pr-finalize.md                  no issues

To fix: /geniro:actions edit slack-release-ping
```

Exit non-zero if any CRITICAL or HIGH.

---

## 11. Mode: list — **DECIDED**

Preserved from current skill. Output format:

```
$ /geniro:actions list

Custom actions in .geniro/actions/ (project: my-project):

| Name | Description | Risk | Created |
|------|-------------|------|---------|
| daily-recap | Use when wrapping the day's commits + tests | low | 2026-04-12 |
| commit-and-pr-summary | Use when finalizing a PR before push | medium | 2026-04-18 |
| slack-release-ping | Use when posting a release note to #releases | high | 2026-04-15 |

3 actions total · run with /geniro:actions run <name>
```

Risk column shows colored / sigil indicator if terminal supports (out of scope — plain text MVP).

---

## 12. Memory I/O (M2 §13 obligation)

**`.geniro/actions/*.md` is NOT a memory layer** — it's executable workflow content, similar to `.claude/commands/` in vanilla Claude Code. M2's 4 layers (L1 Working / L2 Episodic / L3 Semantic / L4 Procedural) do not include actions.

| Layer | Read at | Write at | Notes |
|---|---|---|---|
| **L1 (CLAUDE.md)** | not read | not written | `/actions` does not touch CLAUDE.md |
| **L2 (`learnings.jsonl`)** | not read in CRUD modes | written in run mode if `external-send: true` and success (§6.3 step 5) | One `discovery` row per external-send run; auto-replaces dropped `/learnings` |
| **L3 (semantic project files)** | not read | not written | N/A |
| **L4 (`.geniro/instructions/*.md`)** | not read by `/actions` itself | not written | `/instructions` owns this surface |
| **Actions (`.geniro/actions/*.md`)** | read in all modes | written in create/edit | T3 PERSISTENT/CRUD per M1; NOT part of M2 memory model |

Actions are stored at the M1 T3 PERSISTENT/CRUD tier (`.geniro/actions/`). They survive compaction trivially (file-on-disk M3 §6 Block 1). They are NOT considered Geniro's memory — they're user-authored workflows.

---

## 13. Master plan reconciliation

| Master plan ref | Closure |
|---|---|
| §107 row M10 (operational skills) | M10c covers `/actions` |
| §122 row M10 ("lowest priority") | Respected — minimal phases, no state machine, narrow ACI surface |
| **P-M10-1** "Connector safety properties" | Closed minimal (Q4) — 3 enforced (`name`, `description`, `risk_class`), 5 documented (scoped, untrusted-by-default, logged, disabled-when-unused, version-pinned) |
| **P-M10-2** "Skill description lint rules" | Shared rule set with M10b §10.2 — `description:` lint applies to action frontmatter via §10.2 above |
| **OQ-M10b-1** "Should `/instructions validate` also lint `.geniro/actions/<slug>.md` frontmatter?" | Answered: shared rule set, but the actual command is `/actions validate` (per skill ownership); cross-reference documented in §10 |
| **P-MP-1** "Anti-patterns guardrail" | §14 below |
| Anti-pattern #4 ("Autonomous external sends in first release") | Addressed via §6.3 risk-class AUQ ladder; `risk_class: high` requires explicit confirm |

---

## 14. Anti-pattern check (P-MP-1 obligation)

| # | Anti-pattern | M10c status |
|---|---|---|
| 1 | One giant prompt | ✅ SKILL.md modular; action bodies are user-authored (out of plugin's control); action template at `${CLAUDE_PLUGIN_ROOT}/skills/actions/skill-template.md` is ~80 LOC |
| 2 | One giant tool | ✅ N/A |
| 3 | Unbounded autonomous loop | ✅ 3-retry on slug + 3-retry on create-validation; run mode is one-pass through action body |
| 4 | Autonomous external sends in first release | ✅ `risk_class: high` AUQ-gate with Cancel-as-recommended default; bare-slug fast path still respects the gate |
| 5 | No approval state | ✅ Run-mode is per-invocation (context-dependent) — approvals[] persistence intentionally NOT applied; rationale documented in §6.3 |
| 6 | No durable plans or goals | ✅ N/A — actions ARE the durable plans for user-authored workflows |
| 7 | No compaction strategy | ✅ Actions are file-on-disk; survive compaction natively |
| 8 | All connectors loaded up front | ✅ Actions are loaded only when invoked; one at a time |
| 9 | High-risk tools without policy | ✅ §2.4 per-mode ACI + §6.3 risk-class AUQ ladder + §6.2 schema constraints (allowed-tools intersection in run mode) |
| 10 | Subagents before single-agent MVP measured | ✅ Zero subagents in `/actions` itself (action body may spawn agents if user-authored, but that's not /actions concern) |
| 11 | Dynamic timestamps in plugin-distributed Markdown | ⚠ Implementation note — `/actions` SKILL.md should NOT embed runtime timestamps; the action `created:` field IS a timestamp but lives in user-authored content (not plugin-distributed) |
| 12 | Non-deterministic agent registration order | ✅ N/A |

---

## 15. Open questions

| # | OQ | Resolution path |
|---|---|---|
| **OQ-M10c-1** | Should action body steps support a `## AUQ:` annotation that fires mid-run? | Mentioned in §6.3 step 3; defer concrete syntax to implementation. Spec idea: a step prefixed with `[AUQ]` triggers `AskUserQuestion` with the step text as the question |
| **OQ-M10c-2** | Should `/actions run` support `--dry-run` to preview tool calls without executing? | Yes-in-principle; defer to implementation. The action body is Markdown — running through it without executing tool calls is straightforward |
| **OQ-M10c-3** | Should `risk_class` auto-update based on tool-allowlist inspection? (e.g., if `allowed-tools:` contains `Bash(curl)`, force `risk_class: high`) | No — manual is fine. The validate-mode lint catches `external-send: true ⇒ risk_class: medium|high`. Auto-elevation would surprise users |
| **OQ-M10c-4** | Should actions support a `before:` / `after:` hook field that runs another action? | Out of scope MVP. Composability is a future extension; users today can chain by having step N call `/geniro:actions run <other-slug>` |

---

## 16. Cleanup checklist

`/actions` is stateless — no state files to clean.

| Side-effect | Cleanup |
|---|---|
| `create` wrote a file | No cleanup; user-authored content |
| `edit` modified a file | No cleanup; atomic write |
| `delete` removed a file | No cleanup; file gone |
| `run` executed an action that wrote files / sent external messages | NO CLEANUP — `/actions` does not undo external sends. If an action's step has side effects, those are the action author's responsibility to make idempotent or reversible |
| Validate produced report | Conversation-only |

The `/run` mode being stateless means: if a run fails mid-step, partial side effects (e.g., commit written but push failed) are NOT rolled back by `/actions`. Action authors should design steps to be idempotent or include their own rollback logic — documented in `skill-template.md` (preserved from current).

---

## 17. Cross-references

- **M1 §T3 PERSISTENT (CRUD)** — `.geniro/actions/` tier; CRUD concurrency via optimistic mtime check (M1 §T3 CRUD)
- **M2 §5.3 L2 emit triggers** — `discovery` emit on external-send actions (§6.3 step 5)
- **M3 §6 Block 1** — file-on-disk compaction-survival channel for `.geniro/actions/*.md`
- **M4 §2.2** — 7 loop invariants
- **M4 §2.3** — quality-first budgets
- **M4 §13.5** — per-phase ACI; §2.4 mirrors structure (run mode has uniquely user-determined tool surface — documented as intersection rule)
- **M10b §8** — edit dialogue-mode pattern (shared)
- **M10b §10** — validate rule set (shared P-M10-2 + structural lint)
- **P-MP-1** — Anti-pattern guardrail (12-item) — §14 above
- **P-X6** (deferred candidate) — observability layer that would close P-M10-1 property #6 ("logged") and #7 ("disabled-when-unused") via telemetry. Documented as forward-reference; out of M10c scope
