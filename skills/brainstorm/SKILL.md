---
name: geniro:brainstorm
description: "Use when refining an idea into an approved design before any implementation. Triggers on speculative inputs ('we should add X', 'thinking about Y', 'explore Z', 'what if we'). Skip for well-formed specs — use /geniro:implement directly. The HARD-GATE in brainstorming-loop.md prevents implementation invocation until the design is approved."
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Task, AskUserQuestion, TodoWrite, WebSearch, WebFetch]
model: opus
argument-hint: <topic-string-or-design-path>
---

# Brainstorm — refine an idea into an approved design

Turn a speculative idea into a committed design doc the rest of the pipeline can consume. This skill is a thin wrapper around the canonical 8-phase ideation loop in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/brainstorming-loop.md`. It applies the loop verbatim with no modifications, then fans out to the user-chosen next step (implement / decompose / backlog / stop).

**Output:**
- A committed design doc at `.geniro/planning/<branch>/<YYYY-MM-DD>-<topic-slug>-design.md` with all three detection markers (YAML frontmatter, HTML comment, path placement) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`.
- A user-chosen Phase 9 hand-off (run `/geniro:implement`, `/geniro:decompose`, `/geniro:features add`, or stop).

The HARD-GATE in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/brainstorming-loop.md` prevents any implementation invocation until Phase 8 user re-review approves the design.

---

## When to use

- User has an idea but no spec yet.
- `$ARGUMENTS` contains speculative phrasing (`maybe`, `should we`, `thinking about`, `explore`, `what if we`).
- Topic spans new functionality (vs a bug fix, which routes to `/geniro:debug`).
- Pre-implementation refinement (vs architecture review during `/geniro:implement` Phase 2 — that runs after the design exists).

## When NOT to use

- Spec already written → use `/geniro:implement <design-path>`. Detection is automatic per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` — no flag needed.
- Bug to fix → `/geniro:debug` for root cause, `/geniro:follow-up` for the patch.
- Backlog tracking only → `/geniro:features add` (uses the same loop and additionally registers an F-id).

---

## Phase 0 — Input mode detection

Run the detection algorithm in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` on the first non-flag token of `$ARGUMENTS`. Branch on the resolved mode:

- **`mode=DESIGN_DOC`** (token resolves to a file matching any of: path under `.geniro/planning/**/*.md`, HTML `<!-- geniro:design-doc -->` marker, YAML `geniro_kind: design-doc` frontmatter) → fire `AskUserQuestion` per the schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`:
  - `header`: `"Design exists"`.
  - `question`: `"Design doc already exists at <path>. What now?"` (substitute the actual resolved path).
  - `options[]`:
    - `label`: `"Refine"` — `description`: `"Load the existing doc and jump to brainstorming-loop Phase 5 (section approval) with the doc as the starting state. Use this to revise specific sections without re-running Phase 1 explore."`
    - `label`: `"Start over"` — `description`: `"Discard the existing doc and run the full loop from Phase 1 with the original topic. Use this when the doc is stale enough that targeted edits would not converge."`
    - `label`: `"Cancel"` — `description`: `"Exit the skill. The existing design doc remains untouched."`
  - On **Refine** → load the doc, jump to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/brainstorming-loop.md` Phase 5 with the existing sections pre-populated as the starting state. Phase 6/7/8 then run normally.
  - On **Start over** → run the full loop from Phase 1 below with the original topic.
  - On **Cancel** → exit.

- **`mode=IDEA`** (token does not resolve to a file) → run the full brainstorming loop starting at Phase 1 below.

- **`mode=CODE_REFERENCE`** (file exists but no design-doc markers match) → error and exit:
  > "Argument `<path>` is a code file, not a design doc. Did you mean `/geniro:implement <path>`?"
  >
  > Brainstorm only accepts a topic string or a design-doc path. Code references belong to `/geniro:implement`.

If `$ARGUMENTS` is empty, fall back to the empty-argument AUQ in `brainstorm-reference.md` § Edge cases.

---

## Phases 1–8 — Brainstorming loop

Cite and execute `${CLAUDE_PLUGIN_ROOT}/skills/_shared/brainstorming-loop.md` Phase 1 through Phase 8 verbatim. This skill applies the loop with **no modifications** — the only divergence is the Phase 9 hand-off menu defined below, which the loop deliberately leaves to consumers.

The HARD-GATE at the top of `brainstorming-loop.md` is binding throughout this section. It releases only when Phase 8 user re-review returns "Approve".

---

## Phase 9 — Hand-off menu

Once Phase 8 releases the HARD-GATE, fire `AskUserQuestion` per the schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`:

- `header`: `"Hand-off"`.
- `question`: `"Design committed at <path>. What's next?"` (substitute the actual committed path).
- `options[]` (single-select, 4 options):
  - `label`: `"Implement directly"` — `description`: `"Recommended for Small/Medium scope. Orchestrator runs /geniro:implement <design-path> — the design-doc auto-detect skips Phase 1 Discover and treats this doc as the authoritative spec."`
  - `label`: `"Decompose into milestones"` — `description`: `"Recommended for Big scope. Orchestrator runs /geniro:decompose <design-path>, which writes 3-7 milestone-N-*.md files under the same task-dir. After approval you run /geniro:implement milestone <N> per slice."`
  - `label`: `"Add to backlog"` — `description`: `"Orchestrator runs /geniro:features add <design-path>. The design-doc auto-detect skips ideation and just registers an F-id with this doc as the linked spec."`
  - `label`: `"Stop here"` — `description`: `"Done. The committed design doc remains as a draft artifact and can be passed to any pipeline skill later via its path."`

**Routing on answer:**
- **Implement directly** → orchestrator invokes `/geniro:implement <design-path>` in the next response.
- **Decompose into milestones** → orchestrator invokes `/geniro:decompose <design-path>` in the next response.
- **Add to backlog** → orchestrator invokes `/geniro:features add <design-path>` in the next response.
- **Stop here** → exit. The doc is already committed; no further action.

Empty `AskUserQuestion` answer = upstream Claude Code bug per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`; fall back to plain text and re-ask. Never auto-default.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The user's idea is clearly trivial — skip Phase 1 Explore" | Even trivial ideas have unexamined assumptions; Phase 1 Explore is mandatory per the HARD-GATE in `brainstorming-loop.md`. Phase 5 already scales sections to topic size (1-2 sections for trivial); Explore stays. |
| "I'll skip Phase 8 user re-review — my Phase 7 self-review is enough" | Agent self-review (Phase 7) and user re-review (Phase 8) catch DIFFERENT defect classes — placeholders/contradictions vs intent/missing-constraint. Both required per `brainstorming-loop.md`. |
| "I'll write the design doc inline in chat instead of `.geniro/planning/`" | Path placement is one of the three required detection markers per `design-doc-detect.md`. Inline-only loses path-based detection on subsequent invocations and breaks the design-doc auto-detect contract for downstream skills. Write all three markers; commit the file. |
| "I'll skip Phase 9 and just run `/geniro:implement` automatically — saves a round-trip" | The Phase 9 menu is where the user picks Big-vs-Small routing (decompose vs implement) and backlog routing. Auto-routing destroys that decision. The HARD-GATE released at Phase 8 covers approval, not routing. |
| "`mode=CODE_REFERENCE` should silently fall back to `mode=IDEA`" | Per `design-doc-detect.md` Anti-rationalization, falling back to IDEA on a real file path silently misclassifies code references as topics. Error and exit with the corrective hint. |

---

## Definition of Done

Brainstorm skill is complete when:

- [ ] Phase 0 mode detection ran via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`; mode is one of `DESIGN_DOC`, `IDEA`, `CODE_REFERENCE`.
- [ ] On `mode=DESIGN_DOC`, the Refine/Start over/Cancel AUQ fired and was respected.
- [ ] On `mode=CODE_REFERENCE`, the skill errored with the corrective hint and exited (no loop run).
- [ ] On `mode=IDEA` (or DESIGN_DOC + Refine / Start over), the brainstorming loop ran per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/brainstorming-loop.md` Definition of Done.
- [ ] Design doc committed at `.geniro/planning/<branch>/<YYYY-MM-DD>-<topic-slug>-design.md` with all three detection markers (YAML frontmatter `geniro_kind: design-doc`, HTML comment `<!-- geniro:design-doc -->`, path under `.geniro/planning/`).
- [ ] HARD-GATE released only on Phase 8 "Approve".
- [ ] Phase 9 hand-off AUQ fired; user picked one of the four options; orchestrator routed accordingly (or exited on "Stop here").

See `brainstorm-reference.md` for refining-existing-design entry, edge cases, and skipping-the-hand-off-menu.
