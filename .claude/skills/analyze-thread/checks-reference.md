# analyze-thread — checks reference

The canonical check taxonomy used by `/analyze-thread` Phase 2. Each check is tagged:

- `[M]` mechanical (deterministic over the normalized events list) — runs in Phase 2 Step 1
- `[J]` judged (LLM pass over thread excerpts with this taxonomy seeded) — runs in Phase 2 Step 2
- `[generic]` valid on any Claude conversation thread
- `[plugin]` only meaningful when the thread is a Geniro skill run (skip when Phase 1 metadata extraction sets `geniro-run: no` AND no plugin signals appear)

## Contents

1. Mechanical checks — A-class (subagent spawning)
2. Mechanical checks — B-class (tool-call correctness)
3. Mechanical checks — C/D/E/F/G/H-class (state, gates, drift, memory, safety, context) · I-class (custom-instruction wiring) · K-class (stage & gate completeness)
4. Judged checks — taxonomy seed for the LLM-judge prompt
5. Severity ladder & confidence calibration
6. Common false-positive recipes for Phase 3 filter
7. Evidence-excerpt ranking heuristic for the judge
8. The expectation set — what the coverage checks (I/K-class) compare against

---

## 1. Mechanical checks — A-class (subagent spawning)

| ID | Name | Severity | Scope | Detection logic |
|---|---|---|---|---|
| A1 | Missed parallel-spawn | warning | generic+plugin | Find runs of ≥2 `tool_use.name == "Agent"` events where each lives in a separate assistant turn AND the inter-event narration contains no result-dependency words ("based on the previous", "after the first agent returns"). The phrase "in ONE assistant response" / "in ONE response" / "same assistant turn" in the spawn site's enclosing skill section confirms one response was required — it raises confidence on a separate-turn hit; on its own, with the spawns batched in one turn, it is compliance, not a finding. |
| A2 | Spawn-list violation | blocker | plugin | Only fires when `geniro-run: yes` AND the active skill is `/geniro:review` or `/geniro:implement` Phase 3. Parse the state.md frontmatter (if present in thread) for `spawn_dims_declared:` — count items. Count actual `tool_use.name == "Agent"` events in the same phase whose `subagent_type` is `reviewer-agent`. If actual < declared, flag the diff. |
| A3 | Hallucinated subagent name | blocker | generic | Extract every `tool_use.input.subagent_type` value from `tool_use.name == "Agent"` events. The Claude Code system prompt lists available agents — collect them from the thread's system message (or the in-thread `Available agent types for the Agent tool:` block). Flag any `subagent_type` not in that list. |
| A4 | Wrong tier for the spawn's side of decide-vs-apply | warning | plugin | For each `Agent` tool_use carrying `tool_input.model`, place the spawn per `skills/_shared/model-tiering.md` §The rule. Defect: a tier at a spawn whose agent declares `model: inherit` — it defeats the user's session-level `/model` choice. Also a defect: a category 2-4 spawn passed a tier *above* `sonnet`, its ceiling. Not a defect: a tier at or below `sonnet` at a category 2-4 site (test-runner, knowledge-retrieval, code-delegate, UI-description, setup-verifier, fix agents), which the orchestrator may size down per §Sizing a non-judgment spawn; or any tier at any site in a run that carried `--subagent-model`. |
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
| D2 | AskUserQuestion bypass | blocker | generic+plugin | Key off the outward-action set, not a declared field: for every call matching the `non-resumable-actions[]` enum in `skills/_shared/state-tier-spec.md` (`git push`, `gh pr create`, `gh pr comment`, commit, release tag, outward post), scan backwards for an `AskUserQuestion` whose resolved answer covered that action class. Flag when none precedes the call, or the answer was "Cancel" / "Skip". Per `skills/_shared/approval-scope.md`, an approval reaches only the class the user was shown, so a gate about a different class does not count. |
| D3 | Premature completion (mechanical part) | warning | generic+plugin | Find the last assistant turn containing one of: "shipped", "done!", "all tests pass", "ready to merge", "complete". Then check: (a) TodoWrite state at that point has open items, OR (b) the prior `tool_result` from a test-runner agent had non-zero failure count. The judged part is in §4. |
| D6 | Unresolved open_questions[] at gate | blocker | plugin | Grep handoff files referenced in the thread for `status: unresolved` entries. If the next assistant turn after the handoff read is a Phase 6 / Pre-PR action (gh pr create, gh pr comment, git push) without a preceding resolution step, flag. |

### E-class instruction-following & drift

| ID | Name | Severity | Scope | Detection logic |
|---|---|---|---|---|
| E4 | Reference to deleted skill / nonexistent phase | warning | plugin | Grep assistant turns for `/geniro:<name>` or bare `/<name>` where `<name>` matches a deleted skill per README.md's "Skills deleted" table. Also flag references to phases that don't exist in the named skill (e.g., a phase number past the end of `/geniro:review`'s own phases-overview list). |
| E5 | Hardcoded line refs in instructions written | warning | plugin | Triggered when an `Edit`/`Write` targets `skills/**/SKILL.md` or `.claude/skills/**/SKILL.md`. Grep the new_string / content for patterns like `SKILL.md:\d+`, `line \d+`, `at line \d+`, `:325-345`. Flag matches — content-anchored language is required per `.claude/rules/skill-prose.md`. |
| E6 | Internal jargon in user-facing prose | nit | plugin | Triggered when text in an `AskUserQuestion.question` / `description` / option `label` / TodoWrite item / final assistant report contains: `L4`, `L3`, `L2`, `L1` (as standalone tokens), `T1`, `T1.5`, `T2`, `T3` (as standalone tokens), bare `KR`, bare `CE`, bare `TR` (when referring to agents). Plain-English forms required per `.claude/rules/skill-prose.md` § "User-facing output uses plain English". |

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

### I-class custom-instruction loading & dynamic-rule wiring

Every I-class check is a **coverage check**: it compares what the run declared it would load against what the trace shows it loaded and applied. Both halves come from the expectation set (§8).

Three rules keep this class honest, and they govern K-class equally.

- **An expectation the trace does not establish is not a finding.** A project that declares no `## Data Sources` cannot omit consulting one, and a thread whose expectation set came out empty produces zero coverage findings rather than a wall of "missing" rows.
- **One finding per declaration site, itemised.** A `pipeline` load site that read none of its four files is one finding listing four missing files, not four findings; a phase whose six steps went unrun is one finding listing six. This is what keeps a systematically-broken run inside the raw-findings cap SKILL.md §Budgets sets instead of burying every other check under it.
- **Confidence tracks the trace, not the rule.** Elsewhere a mechanical hit is always high-confidence, because the rule either matched or it did not. A coverage check matched on an absence, so an absence in what you could see is indistinguishable from an absence in what happened: a check built on a partial trace or a project-read expectation set (§8 degradations 1-2) caps at medium and carries the reason in its rationale.

| ID | Name | Severity | Scope | Detection logic |
|---|---|---|---|---|
| I1 | Declared instruction file never loaded | blocker | plugin | For each `load_sites[]` entry in the expectation set, expand its `LOAD_TIER` to the file set the loader defines (`pipeline` → `global.md`, `memory.md`, `<SKILL_SLUG>.md`, `code-style.md`; `rules-only` → the first two). Between that site and the next phase boundary, look for a `Read` whose `file_path` resolves to each file — under `.geniro/instructions/`, under the active external instructions dir when one appears in the trace, or under a `PRIMARY_ROOT` absolute path. Flag the site once, itemising every file with no Read. |
| I2 | Load echo missing | warning | plugin | For each instruction-file Read that DID fire, scan that assistant turn and the next for the file's echo line in one of the loader's formats — `Loaded <file> (…rules, …constraints[, …data sources]).`, the `from primary worktree` / `from external instructions dir` variants, the `Loaded memory.md (memory backend: …)` form, or `No <file> found — skipping.` A Read with no echo is a load nobody downstream can see; a `No <file> found` echo with no preceding Read is an echo for a load that never happened — flag both, tagging which. |
| I3 | Phase-boundary refresh skipped | warning | plugin | For each `refresh_sites[]` entry (a phase boundary whose skill body prescribes `MODE: refresh`), check that the boundary's turn or the next re-Reads the whole load set and re-echoes. A refresh that reads a strict subset counts as skipped for the unread files — the refresh exists because compaction drops all of them equally. |
| I4 | Fallback path not attempted | warning | plugin | After a `Read` on `.geniro/instructions/<file>` whose `tool_result` is file-not-found, the loader owes one of two things: a retry against `<PRIMARY_ROOT>/.geniro/instructions/<file>`, or evidence that `PRIMARY_ROOT` equals cwd (no worktree probe in the trace, or one whose output shows a single worktree). Flag a run that goes straight from the miss to `No <file> found — skipping.` while the trace shows a linked worktree. Same shape for a configured-but-missing external dir: the bad-pointer caveat must be echoed before the in-repo fallback runs. |
| I5 | Declared memory backend bypassed | warning | plugin | When the `memory.md` tool_result carries a `## Memory Backend` block routing the `learnings` layer, every later learnings write and read must go through the declared tools. Flag an `emit-learning.sh` call or a direct `learnings.jsonl` append with no companion call to the declared write tool, and a `query-learnings.sh` call or file read with no companion call to the declared read tool. Under `mode: replace` the file path alone is a silent no-op, so it is a blocker rather than a warning there. |
| I6 | Custom reviewers discovered but not spawned | blocker | plugin | When the trace shows `review-extra/*.md` files resolved (a Glob result, or Reads of those paths), each valid slug owes one `Agent` spawn carrying `custom:<slug>` as its dimension. Flag a slug with no spawn; flag separately a spawn that lands in a different assistant turn than the built-in reviewer batch, which serialises what the helper requires to run parallel. A slug the trace shows failing validation is correctly absent — not a finding. |
| I7 | Subagent load report missing | warning | plugin | For each `Agent` spawn whose `subagent_type` is one whose contract prescribes its own instruction load, check the returned `tool_result` for a `Context loaded: <item>=<state>` line. A report without one came from an agent that did not run its load steps, so its conclusions rest on plugin defaults rather than project rules. Also flag `<state>` = `unreadable` on a path the orchestrator itself passed — that is a spawn-site defect, not an agent defect. |

### K-class stage & gate completeness

K-class answers "did every stage the skill declared actually run, and did every gate actually fire". Its declared side comes from the expectation set's `phases[]`, `phase_files[]`, `steps[]`, and `gates[]` (§8); the three coverage rules above apply here unchanged.

| ID | Name | Severity | Scope | Detection logic |
|---|---|---|---|---|
| K1 | Declared phase never entered | blocker | plugin | Walk `phases[]` in order. A phase is entered when the trace shows either its narration marker or its characteristic tool surface. Flag a phase with neither whose successors did run — an unentered phase between two run phases is a skip; a run that stopped early at the user's request is not. Do not flag a phase the expectation set marks conditional whose trigger the trace shows unmet. |
| K2 | Phase-entry Read skipped | warning | plugin | For each `phase_files[]` entry — a phase whose steps live in a sibling file, including a second hop to a reference or criteria file — require a `Read` of that file before the phase's first step, plus the `Phase <N> (<name>) — loaded <file>.` echo. A phase whose body was never read ran with its gates deleted and its work intact, which is why this is the highest-yield check in the class. Re-entry after a resume or a compaction owes its own Read. |
| K3 | Gate declared but never fired | blocker | generic+plugin | For each `gates[]` entry, look for an `AskUserQuestion` between the gate's phase entry and the run's end whose subject matches the gate's decision. Flag a gate with none whose guarded action nevertheless happened. A gate whose precondition the trace shows unmet (nothing to decide) is clean when the run says so; silence is not. |
| K4 | Choice put to the user outside the tool | blocker | generic+plugin | Scan assistant text for a choice offered in prose — enumerated options, `(A)/(B)`, "let me know which you prefer", "should I X or Y?" — with no `AskUserQuestion` in the same or next turn (canonical rule: `skills/_shared/gate-rendering.md` §Lean-question conventions). The one documented exception is a repeated empty-answer loop from the tool itself, visible in prior tool_results — anything else flags. |
| K5 | Empty AUQ answer auto-defaulted | blocker | generic+plugin | For each `AskUserQuestion` whose `tool_result` is empty or carries no selected option, the next turn must re-ask. Flag a run that instead proceeds on an assumed answer — an empty answer signals an upstream tool bug, and treating it as consent manufactures an approval the user never gave. |

---

## 4. Judged checks — taxonomy seed for the LLM-judge prompt

These checks require LLM reading because they depend on intent inference, narrative coherence, or cross-section reasoning that regex cannot capture. This table is what the orchestrator inlines verbatim into each judge prompt (SKILL.md's one-judge-per-thread invariant); the judge returns findings in the schema documented in SKILL.md Phase 2 Step 2.

| ID | Name | Severity | Scope | What the judge looks for |
|---|---|---|---|---|
| C2 | State validation skipped on resume | warning | plugin | Thread shows a state.md resume (Read of `.geniro/state/<skill>/<slug>/state.md` near start) but no `validate_state_file` invocation in the same or next turn. Judge confirms by checking if the assistant proceeded directly to a phase action. |
| C3 | Branch mismatch unhandled | warning | plugin | State.md `branch:` field differs from `git branch --show-current` output in the thread, and the assistant did not narrate a Case A/B/C/D decision per the helper. |
| C4 | T1/T1.5 tier confusion | nit | plugin | A state-write helper targeting a T1 path actually contains T1.5-grade durable content (spec excerpts, plan-* content), or vice versa. Judge inspects the written content against the tier spec. |
| D1 | Phase-skipping | blocker | plugin | Narration claims "Phase N" but the actions in that section match a different phase's expected tool surface (e.g., narrated as Phase 3 but only doing Phase 1 research-agent spawns). |
| D4 | Pre-Ship Visual Verification skipped | warning | plugin | Phase 3 Ship sub-step ran AND the changed-file list (via `git diff --name-only`) includes UI extensions (`.tsx`, `.jsx`, `.vue`, `.svelte`, `.html`, `.css`) AND no browser-driving call appears in the ship section (a browser-automation MCP tool, an agent-browser tool, or a scripted end-to-end driver run through Bash). Judge checks whether the session having no browser tool at all was the cause (acceptable) or pure omission (flag) — the walkthrough itself is automatic, so a missing user prompt is not an excuse. |
| D5 | Validation gate skipped | warning | plugin | The skill body specifies a validation gate (e.g., `/improve-template` Phase 4 Step 3) but the thread shows the action sequence proceeding past the gate point without the gate's checks running. |
| E1 | Documented constraint disobeyed | blocker | generic+plugin | Judge identifies constraints stated in: spec.md `forbidden_actions:`, skill body anti-rationalization rows, CLAUDE.md path rules. Then checks if any action in the thread violates one. This is the highest-signal judged check. |
| E2 | Reasoning-action mismatch | warning | generic | Narration says "I will spawn 5 reviewers in parallel" but the next assistant turn shows 1 spawn. Says "I'll read X" but no Read of X follows. Says "Approved — applying fix" but no Edit follows. |
| E3 | Task/goal drift | warning | generic | The final assistant turn addresses a meaningfully different scope than the opening user request. Judge identifies the original ask, traces topic shifts across phases, and flags the magnitude of drift (small/medium/large). |
| F1 | Memory layer precedence ignored | warning | plugin | When `load-semantic.sh` or `load-custom-instructions.md` outputs a conflict notice (visible in tool_result), the assistant should narrate the precedence decision per `resolve-conflicts.md`. If the next action uses the lower-precedence value, flag. |
| H1 | First-vs-last contradiction | warning | generic | Judge compares constraints/requests in the first 20% of events against actions/conclusions in the last 20%. Flag explicit contradictions — e.g., user said "don't modify file X" early and assistant edits X late without acknowledgement. |
| H3 | Failure to ask for clarification | warning | generic | User input contains ambiguity (multiple plausible interpretations) and assistant proceeds with one interpretation without firing `AskUserQuestion`. Judge sets confidence based on how genuine the ambiguity was. |
| D3 (judged half) | Premature completion (judged) | warning | generic+plugin | Combined with mechanical D3: judge inspects "shipped" claims against narrative evidence (did the test suite actually pass? Was the phase exit condition stated in the skill body actually met?). |
| I8 | Additional Step never executed at its boundary | warning | plugin | The loaded instruction content carries an `## Additional Steps` subsection named after a phase boundary. Judge checks the trace at that boundary for the step's work. Two distinct verdicts, and the judge must say which: the step ran somewhere else (misplaced — the loader's "apply where it fits" allowance covers a boundary the skill genuinely lacks, not one it has), or the step never ran at all. A run that loaded a file and echoed it, then executed none of its steps, is a load that changed nothing. |
| I9 | Loaded rule or constraint not applied | blocker | plugin | Judge takes each `## Rules` bullet (standing, every phase) and `## Constraints` bullet (a hard gate) from the loaded content and looks for an action in the trace that contradicts it, or a decision point where the rule was the deciding input and went unmentioned. The load echo proves the file was read; this check is the only evidence that reading it mattered. Cite the bullet verbatim alongside the contradicting action. |
| I10 | Declared data source never consulted | warning | plugin | A `## Data Sources` block declares sources whose `(confirms: …)` hint names a fact kind. Where the run asserted a load-bearing fact of that kind — a status, a shipped-state, a production behavior — judge checks whether the declared source was queried, or the fact was explicitly marked unconfirmed. Flag an assertion that is neither. Facts outside every declared `confirms:` hint are out of scope for this check. |
| I11 | Result stated wider than the Verification Surface allows | warning | plugin | A `## Verification Surface` block states, per check, what it covers and what it does not. Judge compares the run's result claims against the entry for the command that produced them: flag a bare "tests pass" / "verified" where the block names ground that command leaves uncovered, and flag a criterion demonstrated by substituting the nearest green command when no entry covers it. The does-not-cover clause is the boundary the claim may not cross. |
| K7 | Declared step within a run phase skipped | warning | plugin | Mechanical K1 sees whole phases; this sees inside one. Judge walks the entered phase's steps from the expectation set against the trace and flags steps with no corresponding work — weighting steps that gate something (an approval, a validation, a load) over bookkeeping ones, since a skipped gate step changes the run's outcome and a skipped echo does not. Report the phase once with its skipped steps itemised. |
| K8 | Gate fired without its render | warning | plugin | A gate carrying finding, plan, or investigation context owes a visible render message BEFORE the lean question — the digest, evidence, and visual the question refers to. Judge checks the assistant message immediately preceding each such `AskUserQuestion`: flag a question whose options reference content the user was never shown, and flag a render that was reasoned through but never emitted as chat text. A lean question following a genuine render is the compliant shape, not a finding. |

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
| D2 AUQ bypass | An upstream approval already covered the action class — a ship gate answered "push and open the PR" covers both calls | Read the approving question and its options; if they named that class, the action is covered. |
| D3 premature completion | The "shipped" claim was about a sub-task (Phase 2 of N), not the overall pipeline | Read the narrative scope — "Phase 2 done" is fine even with open Todo items for Phase 3+. |
| E6 internal jargon | The jargon appears in a state-file write or REFERENCE section, not in user-facing prose | E6 only applies to AskUserQuestion / TodoWrite / final report. Other contexts are author-facing. |
| G1 git destructive | The command was inside a `<details>` block or a `# Legacy` section (not actually executed) | If Bash output is empty / non-existent for that command, it was illustrative, not executed. |
| G3 secret in state | The "secret" was a redacted token (`sk-***REDACTED***`) or a test fixture (`fake-api-key`, `dummy-token`) | Check if `redact_secrets` was called in the same turn, OR if the value matches a documented fixture pattern. |

A coverage check compares a declared side against an observed side, so it has two ways to be wrong that the other classes do not: the declaration can be misread, and the observation can be missed. Both fail toward a false "missing", which is why the recipes below skew to confirming absence rather than confirming presence.

| Finding pattern | Likely false-positive when | How to confirm |
|---|---|---|
| I1 file never loaded | The file loaded from a path the check didn't recognise — an external instructions dir, or a `PRIMARY_ROOT` absolute path from a linked worktree | Search the trace for any Read whose path ends in the filename, whatever its prefix, and for the external-dir probe's `EXTERNAL_DIR=` output. A matching echo line is equally good evidence the load fired. |
| I1 / I3 missing at a load site | The thread is truncated, compacted, or starts mid-run, so the turns holding the load are simply not in the file | Check whether the trace contains the run's opening turn. A thread that begins mid-phase cannot evidence a Step 0 load — downgrade every load-site finding to UNCERTAIN and say the trace is partial. |
| I5 memory backend bypassed | The declared backend tool was unavailable in that session and the run fell back to the file with the fail-open documented in its narration | Read the turns around the call: a stated fallback after a backend error is the contract working, not a bypass. |
| I6 reviewer not spawned | The slug failed the loader's validation (reserved name, slug/filename mismatch, bad `model:`) and was correctly dropped with a warning | Look for the one-line skip warning naming that file. A validated-out reviewer owes no spawn. |
| I7 load report missing | The spawn was to an agent whose contract prescribes no instruction load, or the orchestrator pre-inlined the file as a prompt slot | Check the agent's own contract; a `Context loaded: …=slot` line is compliance, and an agent with nothing to load owes no line. |
| I9 rule not applied | The rule's subject never arose in this run, so there was no decision point for it to govern | A rule can only be violated where it applies. Name the specific action that contradicts it; if you cannot, this is UNCERTAIN at best. |
| I10 data source never consulted | The asserted fact fell outside every declared `(confirms: …)` hint, or the run explicitly marked it unconfirmed | Re-read the hint list; an unconfirmed-marked fact is the contract's own clean path. |
| K1 phase never entered | The phase was conditional and its trigger never fired, or the run legitimately terminated early — a user interrupt, an abort gate, a stop the user asked for | Check the terminal turns. A run that ended on a user "stop" skipped nothing; only a phase stepped over while later phases ran is a skip. |
| K2 phase-entry Read skipped | The skill keeps that phase's steps inline in SKILL.md, so there is no sibling file to read | Confirm from the expectation set that the phase actually has a body file. A single-file skill has no hop to miss. |
| K3 gate never fired | An earlier approval already covered this decision class, or the gate's precondition was genuinely empty | Read the earlier question and its options — per `skills/_shared/approval-scope.md` an approval reaches only the class the user was shown. For an empty precondition, look for the `none — <step> ran …` sentinel; a bare-empty artifact means the producing step did not run, which is a different finding. |
| K4 choice outside the tool | The prose was narrating options the run then put through `AskUserQuestion`, or it was recapping a decision the user had already made | Look one turn forward for the tool call and one turn back for the answer. Narration around a real gate is not a bypass. |
| K7 step skipped | The step was conditional, or the trace records its work without narrating it under the step's name | Match on the step's effect, not its label — a step whose work is visible ran, whatever the narration called it. |

---

## 7. Evidence-excerpt ranking heuristic for the judge

Phase 2 Step 2 slices the thread into excerpts to fit the judge's excerpt budget (SKILL.md §Budgets & quality gates — LLM-judge token budget row). The ranking decides which events to include:

Suspicion score per event = sum of:

- `+5` if the event is within ±2 events of a mechanical finding
- `+3` if the event is within ±3 events of an `AskUserQuestion` call
- `+3` if the event narration contains a phase-boundary word: `Phase`, `Step`, `shipping`, `complete`, `review`
- `+3` if the event is a `Read` of an instruction file, a phase body, or a criteria file, or carries a load echo (`Loaded <file>`, `No <file> found`, `Phase <N> … loaded`) — these anchor every I/K-class judged check
- `+2` if the event is a `tool_use` to `Agent` (subagent spawn — high signal)
- `+2` if the event is a `tool_use` to `Edit` or `Write` (state-changing)
- `+1` if the event is in the first 10 or last 10 events of the thread (start/end carry context)
- `0` otherwise

Sort events by suspicion descending; take top events until the excerpt budget is reached; sort the selection back into chronological order for the judge. Always include the opening user message and the closing assistant turn regardless of score (anchors for E3 task-drift judging), and both ends of each declaration the expectation set carries — the tool_result that established it, and the turns at the boundary where it applied — before spending the budget on the ranked tail: a purely score-sorted slice reliably keeps the declaration and drops its boundary, because a boundary where nothing happened scores near zero for exactly the reason it is the finding, and the judged coverage checks (I8-I11, K7, K8) need that empty boundary as evidence, not just the declaration. Where an excerpt had to be dropped anyway, tell the judge which checks are running on partial evidence rather than letting it read absence as proof.

---

## 8. The expectation set

Every A-H check reads the trace and asks "is this action wrong?". The I- and K-class checks ask a different question — "is something *missing*?" — and a missing thing has no event to match on. They need a declared side to compare the trace against. That is the expectation set: per thread, what the run said it would load, enter, and ask, built at Phase 1 and consumed by Phase 2.

### Build it from the trace, not from this checkout

The thread being analyzed usually belongs to a different project than the machine running the analysis — that is the normal case in a batch, where threads are drawn from every project on the box. Reading the analyzer's own `.geniro/instructions/` or `skills/` to decide what a thread should have loaded compares one project's run against another project's rules, and every row it produces is fiction.

The trace is self-sufficient, and this is what makes the class work: a Claude Code session log records the skill body that was injected, the tool_results of every instruction file the run read, and the arguments of every call it made. What the run was told and what it did are both in the file.

| Field | What it holds | Where the trace shows it |
|---|---|---|
| `skill` | The skill this run executed | The slash-command invocation, or the injected skill body's `name:` |
| `phases[]` | Declared phases in order, each flagged conditional or unconditional | The injected skill body's phase headings and its phases overview |
| `phase_files[]` | Phases whose steps live in a sibling file, plus any second hop that file defers to | The spine's phase-body pointers |
| `steps[]` | Per entered phase, its declared steps, flagged gate-bearing or bookkeeping | The phase body's tool_result, once the run read it |
| `gates[]` | Decisions the skill declares it will put to the user | `AskUserQuestion` sites named in the skill and phase bodies |
| `load_sites[]` | Instruction-load sites with their `SKILL_SLUG` / `LOAD_TIER` / `MODE` | The load-site wording in the skill body |
| `refresh_sites[]` | Phase boundaries prescribing `MODE: refresh` | Same |
| `instruction_blocks[]` | Per loaded file, which blocks it carried — `## Rules`, `## Constraints`, `## Additional Steps` (with the boundary each names), `## Data Sources`, `## Verification Surface`, `## Memory Backend` | The tool_result of each instruction-file Read |
| `custom_reviewers[]` | Valid `review-extra/` slugs the run resolved | The Glob result or Reads under `review-extra/` |

### When the trace does not carry it

Three degradations, in order of preference. Each one weakens the checks that depend on the missing field, and the weakening travels with the finding rather than being decided once for the thread.

1. **Partial trace** — the thread is compacted or starts mid-run, so a declaration is visible but the turns that would have honored it are not. Keep the check, cap its confidence at medium, and say the trace is partial in the finding's rationale. Absence in a slice you cannot see is not evidence.
2. **Skill body absent, project reachable** — the trace names the skill but does not carry its body, and the thread's own project directory is readable from here. Read the body from there, and mark every finding derived from it as UNCERTAIN: the file has changed since the run by an unknown amount, so a mismatch may be an edit rather than a failure.
3. **Neither** — drop the I- and K-class checks for that thread and say so in the report. A coverage check with no declared side reports nothing, which is the correct answer; inventing the declared side reports everything, which is worse than the silence it replaces.

An empty expectation set is a normal outcome, not a parse failure. A thread with no Geniro run in it — the `geniro-run: no` case — has no declarations to check, and generic threads skip the whole class the same way they skip every other `[plugin]` row.
