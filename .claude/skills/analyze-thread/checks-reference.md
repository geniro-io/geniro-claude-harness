# analyze-thread — checks reference

The canonical 32-check taxonomy used by `/analyze-thread` Phase 2. Each check is tagged:

- `[M]` mechanical (deterministic over the normalized events list) — runs in Phase 2 Step 1
- `[J]` judged (LLM pass over thread excerpts with this taxonomy seeded) — runs in Phase 2 Step 2
- `[generic]` valid on any Claude conversation thread
- `[plugin]` only meaningful when the thread is a Geniro skill run (skip when Phase 1 metadata extraction sets `geniro-run: no` AND no plugin signals appear)

## Contents

1. Mechanical checks — A-class (subagent spawning)
2. Mechanical checks — B-class (tool-call correctness)
3. Mechanical checks — C/D/E/F/G/H-class (state, gates, drift, memory, safety, context)
4. Judged checks — taxonomy seed for the LLM-judge prompt
5. Severity ladder & confidence calibration
6. Common false-positive recipes for Phase 3 filter
7. Evidence-excerpt ranking heuristic for the judge

---

## 1. Mechanical checks — A-class (subagent spawning)

| ID | Name | Severity | Scope | Detection logic |
|---|---|---|---|---|
| A1 | Missed parallel-spawn | warning | generic+plugin | Find runs of ≥2 `tool_use.name == "Agent"` events where each lives in a separate assistant turn AND the inter-event narration contains no result-dependency words ("based on the previous", "after the first agent returns"). Also flag when the active skill body text contains the phrase "in ONE assistant response" or "in ONE response" or "same assistant turn" within the spawn site's enclosing section. |
| A2 | Spawn-list violation | blocker | plugin | Only fires when `geniro-run: yes` AND the active skill is `/geniro:review` or `/geniro:implement` Phase 3. Parse the state.md frontmatter (if present in thread) for `spawn_dims_declared:` — count items. Count actual `tool_use.name == "Agent"` events in the same phase whose `subagent_type` is `reviewer-agent`. If actual < declared, flag the diff. |
| A3 | Hallucinated subagent name | blocker | generic | Extract every `tool_use.input.subagent_type` value from `tool_use.name == "Agent"` events. The Claude Code system prompt lists available agents — collect them from the thread's system message (or the in-thread `Available agent types for the Agent tool:` block). Flag any `subagent_type` not in that list. |
| A4 | Wrong tier — explicit `model=` against `inherit` | warning | plugin | For each `Agent` tool_use, check if `tool_input.model` is present. Cross-reference against the agent definition's expected behavior: plugin agents declared `model: inherit` in `agents/<name>.md` frontmatter should have NO `model=` field at the spawn site. Hardcoded `model="sonnet"` / `model="haiku"` defeats the user's session-level `/model` choice. |
| A5 | Fallback ladder not attempted | warning | plugin | After any `tool_result` containing `Agent type '<name>' not found`, the next 2 assistant turns must contain another `Agent` call. First retry should use the bare-name form; second retry should use `subagent_type="general-purpose"`. If the assistant abandons the spawn after one failure, flag. |
| A6 | Over-spawn / duplicate prompts | warning | generic | Group `Agent` tool_uses by assistant turn. Within each group, hash the `tool_input.prompt` field; if two have identical hashes (or Levenshtein distance < 50 chars on prompts >500 chars), flag as duplicate. |
| A7 | Leaf subagent spawning nested agent | blocker | plugin | If the thread under analysis is itself a subagent transcript (detectable when the system message lacks a slash-command invocation context and the user message is a structured prompt), any `Agent` call from within is a violation. Skip in main-context threads. |

## 2. Mechanical checks — B-class (tool-call correctness)

| ID | Name | Severity | Scope | Detection logic |
|---|---|---|---|---|
| B1 | Hallucinated tool / wrong tool selection | blocker | generic | Extract the available-tools list from the system message (or first `<functions>` block). For each `tool_use.name`, check membership. Flag non-members. Sub-check: when two tools share a stem (`*_user` vs `*_channel`, `Edit` vs `Write`), tally per-stem usage; if usage flips mid-thread without explicit reasoning, flag as potential mis-selection. |
| B2 | Schema-invalid tool arguments | blocker | generic | Cross-reference each `tool_use.input` against the tool's declared JSON schema (extracted from the system `<functions>` block). Flag: missing required fields, type mismatches (string passed where number expected), fields not in the schema (fabricated parameters). Best-effort: skip for MCP tools whose schema isn't in the thread. |
| B3 | Infinite / retry loop | warning | generic | Sliding window of 5 consecutive `tool_use` events. Flag when ≥3 share the same `tool_name` AND byte-identical `tool_input` AND the intervening `tool_result` events show no progress (same error message OR empty result OR identical content). |
| B4 | Edit/Write without prior Read | warning | generic | Pre-condition lookup: for each `tool_use.name in ("Edit","Write")`, scan all PRIOR events for a `tool_use.name == "Read"` whose `tool_input.file_path` matches the target. Flag misses. Exception: `Write` on a brand-new file (path doesn't exist in any prior tool result) is fine. |

## 3. Mechanical checks — C/D/E/F/G/H-class

### C-class state & persistence

| ID | Name | Severity | Scope | Detection logic |
|---|---|---|---|---|
| C1 | Direct Edit/Write on `.geniro/` state path | blocker | plugin | Flag any `tool_use.name in ("Edit","Write")` whose `tool_input.file_path` matches `.geniro/state/` / `.geniro/planning/` / `.geniro/knowledge/` / `.geniro/.geniro-state.json` AND the prior assistant narration does not invoke `source ... atomic-state-write.sh` or `atomic_state_write` in a Bash call. |

### D-class phase & gate compliance

| ID | Name | Severity | Scope | Detection logic |
|---|---|---|---|---|
| D2 | AskUserQuestion bypass | blocker | generic+plugin | Extract the active skill's `approval_required_for:` list (from spec.md frontmatter or skill body grep). For each entry, find the corresponding tool call (e.g., "git push" → `tool_use.name == "Bash"` with command matching `git push`). Cross-reference: did an `AskUserQuestion` resolve to the approval option BEFORE the call? If no AUQ or AUQ answered "Cancel"/"Skip" — flag. |
| D3 | Premature completion (mechanical part) | warning | generic+plugin | Find the last assistant turn containing one of: "shipped", "done!", "all tests pass", "ready to merge", "complete". Then check: (a) TodoWrite state at that point has open items, OR (b) the prior `tool_result` from a test-runner agent had non-zero failure count. The judged part is in §4. |
| D6 | Unresolved open_questions[] at gate | blocker | plugin | Grep handoff files referenced in the thread for `status: unresolved` entries. If the next assistant turn after the handoff read is a Phase 6 / Pre-PR action (gh pr create, gh pr comment, git push) without a preceding resolution step, flag. |

### E-class instruction-following & drift

| ID | Name | Severity | Scope | Detection logic |
|---|---|---|---|---|
| E4 | Reference to deleted skill / nonexistent phase | warning | plugin | Maintain a deny-list of removed slash commands: `/follow-up`, `/decompose`, `/learnings`, `/brainstorm`, `/deep-simplify`, `/features`, `/cleanup`, `/vendor`. Grep assistant turns for `/geniro:<deny>` or bare `/<deny>`. Also flag references to phases that don't exist in the named skill (e.g., "Phase 7 of /geniro:review" — review has 6 phases). |
| E5 | Hardcoded line refs in instructions written | warning | plugin | Triggered when an `Edit`/`Write` targets `skills/**/SKILL.md` or `.claude/skills/**/SKILL.md`. Grep the new_string / content for patterns like `SKILL.md:\d+`, `line \d+`, `at line \d+`, `:325-345`. Flag matches — content-anchored language is required per `.claude/rules/skill-prose.md`. |
| E6 | Internal jargon in user-facing prose | nit | plugin | Triggered when text in an `AskUserQuestion.question` / `description` / option `label` / TodoWrite item / final assistant report contains: `L4`, `L3`, `L2`, `L1` (as standalone tokens), `T1`, `T1.5`, `T2`, `T3` (as standalone tokens), bare `KR`, bare `CE`, bare `TR` (when referring to agents). Plain-English forms required per `.claude/rules/skill-prose.md` § User-facing narration. |

### F-class memory & layer hygiene

| ID | Name | Severity | Scope | Detection logic |
|---|---|---|---|---|
| F2 | L2 entry emitted without trust label | warning | plugin | Find Bash calls to `emit-learning.sh` or direct `echo {...} >> learnings.jsonl`. Parse the JSON. If `trust` field is absent, flag. Valid values: `verified`, `retrieved`, `inferred`. |
| F3 | Auto-promotion L2 → L4 without user approval | warning | plugin | Find sequences where a `learnings.jsonl` read or `query-learnings.sh` call is followed within 5 turns by an `Edit`/`Write` to `.geniro/instructions/*.md` without an intervening `AskUserQuestion` containing "promote" / "elevate" / "make a rule". |

### G-class git & safety-hook compliance

| ID | Name | Severity | Scope | Detection logic |
|---|---|---|---|---|
| G1 | Git destructive op attempted | blocker | plugin | Grep `tool_use` Bash commands for: `git push --force` (without `--with-lease` if also flagged), `git reset --hard`, `git branch -D`, `git clean -fd`, `git checkout -- .`, `git restore .`, `git update-ref -d`, `git filter-branch`, `git add -f .geniro/`, `git worktree remove`. Each is a separate finding ID. |
| G2 | `--no-verify` used | blocker | plugin | Grep Bash commands for ` --no-verify` (with leading space to avoid matching `name-verify`). Also flag `-c commit.gpgsign=false`, `--no-gpg-sign`. |
| G3 | Secret in state file | blocker | generic+plugin | When an `Edit`/`Write` targets `.geniro/state/` / `.geniro/knowledge/` / `.geniro/planning/`, scan `new_string` / `content` for patterns: `[A-Za-z0-9]{32,}` after `api_key|token|secret|bearer|password` (case-insensitive), `sk-[a-zA-Z0-9]{20,}`, `xoxb-`, `ghp_`, `glpat-`, PEM headers. Cross-check against `redact-secrets.sh` invocation in the same turn — if redaction was called, downgrade to nit. |

### H-class context / lost-in-the-middle

| ID | Name | Severity | Scope | Detection logic |
|---|---|---|---|---|
| H2 | Step repetition / redundant tool use | nit | generic | For each `tool_use.name in ("Read","Grep","Glob")`, hash `tool_input.file_path` + `tool_input.pattern`. Count occurrences. Flag any input that appears 3+ times. Exception: the second read is OK if the file was Edit/Written between reads. |

---

## 4. Judged checks — taxonomy seed for the LLM-judge prompt

These checks require LLM reading because they depend on intent inference, narrative coherence, or cross-section reasoning that regex cannot capture. The judge prompt seeds the full list below; the judge returns findings in the schema documented in SKILL.md Phase 2 Step 2.

| ID | Name | Severity | Scope | What the judge looks for |
|---|---|---|---|---|
| C2 | State validation skipped on resume | warning | plugin | Thread shows a state.md resume (Read of `.geniro/state/<skill>/<slug>/state.md` near start) but no `validate_state_file` invocation in the same or next turn. Judge confirms by checking if the assistant proceeded directly to a phase action. |
| C3 | Branch mismatch unhandled | warning | plugin | State.md `branch:` field differs from `git branch --show-current` output in the thread, and the assistant did not narrate a Case A/B/C/D decision per the helper. |
| C4 | T1/T1.5 tier confusion | nit | plugin | A state-write helper targeting a T1 path actually contains T1.5-grade durable content (spec excerpts, plan-* content), or vice versa. Judge inspects the written content against the tier spec. |
| D1 | Phase-skipping | blocker | plugin | Narration claims "Phase N" but the actions in that section match a different phase's expected tool surface (e.g., narrated as Phase 3 but only doing Phase 1 research-agent spawns). |
| D4 | Pre-Ship Visual Verification skipped | warning | plugin | Phase 3 Ship sub-step ran AND the changed-file list (via `git diff --name-only`) includes UI extensions (`.tsx`, `.jsx`, `.vue`, `.svelte`, `.html`, `.css`) AND no `mcp__plugin_playwright_playwright__*` calls appear in the ship section. Judge checks whether MCP unavailability was the cause (acceptable) or pure omission (flag). |
| D5 | Validation gate skipped | warning | plugin | The skill body specifies a validation gate (e.g., `/improve-template` Phase 4 Step 3) but the thread shows the action sequence proceeding past the gate point without the gate's checks running. |
| E1 | Documented constraint disobeyed | blocker | generic+plugin | Judge identifies constraints stated in: spec.md `forbidden_actions:`, skill body anti-rationalization rows, CLAUDE.md path rules. Then checks if any action in the thread violates one. This is the highest-signal judged check. |
| E2 | Reasoning-action mismatch | warning | generic | Narration says "I will spawn 5 reviewers in parallel" but the next assistant turn shows 1 spawn. Says "I'll read X" but no Read of X follows. Says "Approved — applying fix" but no Edit follows. |
| E3 | Task/goal drift | warning | generic | The final assistant turn addresses a meaningfully different scope than the opening user request. Judge identifies the original ask, traces topic shifts across phases, and flags the magnitude of drift (small/medium/large). |
| F1 | Memory layer precedence ignored | warning | plugin | When `load-semantic.sh` or `load-custom-instructions.md` outputs a conflict notice (visible in tool_result), the assistant should narrate the precedence decision per `resolve-conflicts.md`. If the next action uses the lower-precedence value, flag. |
| H1 | First-vs-last contradiction | warning | generic | Judge compares constraints/requests in the first 20% of events against actions/conclusions in the last 20%. Flag explicit contradictions — e.g., user said "don't modify file X" early and assistant edits X late without acknowledgement. |
| H3 | Failure to ask for clarification | warning | generic | User input contains ambiguity (multiple plausible interpretations) and assistant proceeds with one interpretation without firing `AskUserQuestion`. Judge sets confidence based on how genuine the ambiguity was. |
| D3 (judged half) | Premature completion (judged) | warning | generic+plugin | Combined with mechanical D3: judge inspects "shipped" claims against narrative evidence (did the test suite actually pass? Was the phase exit condition stated in the skill body actually met?). |

---

## 5. Severity ladder & confidence calibration

### Severity

| Tier | Definition | Examples |
|---|---|---|
| **blocker** | A failure that broke or would break the pipeline's correctness contract. Approved findings of this severity ship to `/improve-template` as priority items. | Hallucinated tool, spawn-list violation, `--no-verify`, secret in state file. |
| **warning** | A failure that degraded quality but did not break the pipeline. Worth fixing but not urgent. | Missed parallel-spawn, schema-invalid args, premature completion, step repetition. |
| **nit** | A stylistic or hygiene issue that compounds slowly. Often FILTERED in Phase 3 unless multiple instances cluster. | Internal jargon in user prose, redundant Read, T1 vs T1.5 confusion. |

### Confidence

| Tier | When the judge / mechanical assigns this | Phase 3 default tag |
|---|---|---|
| **high** | Mechanical rule matched with no exception conditions; OR judge cites unambiguous trace evidence (direct quote). | TRUE-POSITIVE |
| **medium** | Mechanical rule matched but the exception might apply; OR judge cites circumstantial evidence (inference from context, not direct quote). | UNCERTAIN |
| **low** | Heuristic match only (e.g., regex flagged something stylistically similar but semantically unclear); OR judge says "plausible but contestable". | UNCERTAIN (forced AUQ) |

---

## 6. Common false-positive recipes for Phase 3 filter

Use these when tagging FALSE-POSITIVE. Each is a documented case where a mechanical rule fires but the underlying intent is fine.

| Finding pattern | Likely false-positive when | How to confirm |
|---|---|---|
| A1 missed parallel-spawn | The second Agent call's prompt explicitly references the first agent's output ("based on the previous agent's findings, ...") | Read the spawn-site prompt; if it cites prior output, the serialization is intentional. |
| A6 over-spawn | The "duplicate" prompts target different `subagent_type` values (e.g., reviewer-agent for `bugs` vs `security`) | Diff the spawn invocations; different subagent_type = different work even with similar prompt. |
| B3 infinite loop | The 3+ identical calls were retries against a flaky external service (network, MCP) where the tool_result varies | Read the tool_results; if errors differ or eventually succeed, this is correct retry, not infinite loop. |
| B4 Edit-without-Read | The Edit's target was just created by a Write in the prior turn | Trace backwards: a Write counts as "knowing" the file. |
| D2 AUQ bypass | The action was on the `approval_required_for: []` (empty list) for the active skill | Re-check the spec.md frontmatter; empty list = nothing requires approval. |
| D3 premature completion | The "shipped" claim was about a sub-task (Phase 2 of N), not the overall pipeline | Read the narrative scope — "Phase 2 done" is fine even with open Todo items for Phase 3+. |
| E6 internal jargon | The jargon appears in a state-file write or REFERENCE section, not in user-facing prose | E6 only applies to AskUserQuestion / TodoWrite / final report. Other contexts are author-facing. |
| G1 git destructive | The command was inside a `<details>` block or a `# Legacy` section (not actually executed) | If Bash output is empty / non-existent for that command, it was illustrative, not executed. |
| G3 secret in state | The "secret" was a redacted token (`sk-***REDACTED***`) or a test fixture (`fake-api-key`, `dummy-token`) | Check if `redact_secrets` was called in the same turn, OR if the value matches a documented fixture pattern. |

---

## 7. Evidence-excerpt ranking heuristic for the judge

Phase 2 Step 2 slices the thread into excerpts to fit the 60K-token judge budget. The ranking decides which events to include:

Suspicion score per event = sum of:

- `+5` if the event is within ±2 events of a mechanical finding
- `+3` if the event is within ±3 events of an `AskUserQuestion` call
- `+3` if the event narration contains a phase-boundary word: `Phase`, `Step`, `shipping`, `complete`, `review`
- `+2` if the event is a `tool_use` to `Agent` (subagent spawn — high signal)
- `+2` if the event is a `tool_use` to `Edit` or `Write` (state-changing)
- `+1` if the event is in the first 10 or last 10 events of the thread (start/end carry context)
- `0` otherwise

Sort events by suspicion descending; take top events until 60K-token budget is reached; sort the selection back into chronological order for the judge. Always include the opening user message and the closing assistant turn regardless of score (anchors for E3 task-drift judging).

---

## Notes for maintainers

- The 32-check count is not load-bearing — add new checks here when new failure modes are discovered. Number them by category (A8, B5, etc.) so legacy finding IDs stay stable across versions.
- When `/improve-template` consumes a handoff from `/analyze-thread`, it sees finding IDs verbatim. Keep IDs stable across edits to this file; rename `name` columns freely.
- The judge prompt loads this file at spawn time, not at skill-install time. Editing the taxonomy takes effect on the next `/analyze-thread` run with no rebuild.
