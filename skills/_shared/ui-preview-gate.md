# UI preview gate

A pre-approval procedure that produces a preview of how the UI will look after a change, lets the user critique or rewrite it in their own words, and only then returns control to the caller's approval flow. Callers invoke this when a change touches UI files so the user shapes visual intent BEFORE any code is written.

The preview has two forms. Default: a structured text description. When the caller passes `MOCKUP: true` — it has a live page to publish to — the agent renders a working HTML mockup and emits a compact text digest beside it, because a rendered page carries a UI far more reliably than a paragraph describing one — the digest, not the page, is what the caller persists and its downstream sections cite.

## Contents

- UI-file detection rule — which changed paths make a change UI-touching
- When to run — the caller's trigger condition
- Procedure — Step 1 spawn the description agent · Step 1b mockup form · Step 2 present to user · Step 3 revision loop · Step 4 emit the approved description
- Caller contract — what the caller supplies and what comes back
- Anti-rationalization

## UI-file detection rule

Canonical definition, shared across `/geniro:review` (design dimension + PR-metadata screenshot check), `/geniro:implement` (Pre-Ship Visual Verification gate), and this preview gate. Defined here once so no skill body owns it — cross-skill coordination lives in `_shared/`.

A file is a UI file if its path matches `**/components/**`, `**/pages/**`, `**/app/**`, `**/views/**`, `**/ui/**`, OR its extension is `.tsx` / `.jsx` / `.vue` / `.svelte` / `.css` / `.scss` / `.sass` / `.less` / `.styled.ts` / `.styled.tsx`. A UI-gated step is skipped when no changed/affected file matches.

## When to run

Skip entirely unless at least one file in the predicted affected-files list matches the §UI-file detection rule above. Callers must check this condition before entering the procedure — do NOT re-check here.

## Procedure

### Step 1: Spawn the UI description agent

Spawn a general-purpose subagent for the description. Pass `model="sonnet"` — an execution spawn per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` category 4: the spec already decided what the UI does, and this spawn only transforms it into a structured description. That is the ceiling, not a fixed value: a spec covering one or two screens is a §Sizing down-pick, and the tier goes with it. If the spawn returns an empty result, apply the empty-result fallback in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`. Satisfy the pre-inlined-context contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` at this spawn site. The agent is read/transform-only — set `disallowedTools: ["Edit", "Write", "NotebookEdit"]`.

```
Agent(model="sonnet", disallowedTools=["Edit", "Write", "NotebookEdit"], prompt="""
## Task: Describe UI Before Implementation

Produce a textual, structured description of how the UI will LOOK after this change — so the user can review it and request changes BEFORE any code is written.

## Inputs (pre-inlined by caller)
- Spec or change request: [pre-inlined]
- Plan or predicted affected files: [pre-inlined]
- Exemplar UI files from the same area (1-2, for style reference): [pre-inlined]
- Prior user guidance, if a revision round: [pre-inlined or "none"]

## Output sections
Emit exactly these sections. Use ASCII/Unicode box-drawing where a sketch helps.

### Layout
Where the new or changed element sits on the page. Hierarchy, alignment, spacing intent.

### Components
For each component: name, type (button/input/card/modal/etc.), label text, visible states (default, hover, focus, disabled, loading, error, empty), key props.

### Interactions
Click/submit/focus/keyboard behaviors. Animations, transitions, modal open/close, navigation flows.

### Responsive behavior
Mobile vs tablet vs desktop differences. Stack vs row, visibility toggles, breakpoint notes.

### Accessibility
Keyboard flow, ARIA roles, focus order, contrast considerations.

### Open questions
Things you could not infer from the inputs — as crisp questions. If none, write "none".

## Constraints
- Do NOT write code. Describe intent only.
- Do NOT invent requirements that are not in the inputs.
- Keep the whole response under 200 lines.
""", description="UI preview: describe intent")
```

### Step 1b: Mockup form

Run this only when the caller passed `MOCKUP: true`. Spawn the same agent with the same inputs and four changes to its prompt:

- **Deliverable.** It returns a working HTML mockup of the UI *and* the digest. The mockup is one self-contained block — inline CSS, inline SVG, no external requests, no scripts — with every rule scoped under a single container id, so its styles and the host page's cannot bleed into each other.
- **The six sections become coverage, not format.** The mockup shows what they describe: every component rendered once per visible state (default, hover, focus, disabled, loading, error, empty) as labelled variants, every breakpoint as its own labelled frame, and the focus order marked on the elements it runs through. The digest then restates the same six headings compactly.
- **What the mockup claims.** It encodes structure, hierarchy, and states — not the final visual design. Put that in a caption on the mockup itself, so an implementer reading it later builds the structure the plan approved instead of treating its spacing, color, and type as decisions the plan made.
- **Constraint swap.** "Do NOT write code" still bars production source — no framework components, no imports, no file writes anywhere in the project; the mockup is markup returned in the response. Step 1's line cap applies to the digest, not to the markup.

### Step 2: Present to user

Present the agent's output verbatim — in mockup form that output is the digest, and the caller publishes the mockup before the question fires. Chat stays the surface the user reads the decision on and the one the question's render check looks for; the page is where they see the UI. The options are the same in both forms. Then use `AskUserQuestion` (do NOT print options as plain text) with header "UI preview":

- A) **Looks right — approve** — matches my intent, proceed to the caller's approval flow
- B) **Describe differently — I'll explain** — I want to describe how the UI should look in my own words
- C) **Adjust the plan instead** — the description is fine but the underlying plan is wrong

A reply that isn't A, B, or C — a question back, off-topic text, anything that isn't a selection — has not answered the gate: apply the unanswered-gate contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions (record it if the caller keeps a state file, then re-fire this identical question) rather than reading it as approval or moving on.

### Step 3: Revision loop (only if user picked B)

1. Fire a follow-up `AskUserQuestion` with header "Your version" offering two meaningful options: "Rewrite the whole description — I'll describe it fresh" / "Add targeted changes — I'll list specific edits". The user can also type freely via "Other". Capture the user's text from whichever option they pick.
2. Re-spawn the UI description agent with the captured text appended as `USER GUIDANCE: <text>` in the "Prior user guidance" input. If the user picked "Add targeted changes", instruct the agent to apply those edits to the prior description rather than starting over.
3. Re-present (Step 2) with the revised description — in mockup form the caller republishes the revised mockup first, so each round is judged against the rendered page.
4. **Max 3 revision rounds.** After round 3, fire `AskUserQuestion` with header "UI preview" and options: "Proceed with latest version" / "Adjust the plan instead". Do NOT loop a 4th time.

### Step 4: Emit approved description

Write the approved text where the caller designates, or hold it in-memory when the caller requests it. `/geniro:plan` Phase 2 holds it in-memory and persists it to state.md `## UI Preview` rather than a standalone file. In mockup form the digest is that text; the mockup itself already lives on the caller's page, so it gets no second copy on disk. Return control to the caller along with the file path or content.

## Caller contract

- **Callers provide:** predicted affected-files list, spec/change-request, 1-2 exemplar UI files, destination path for the approved text, and `MOCKUP: true` when they have a live page to publish the mockup to (omit it and the text form runs).
- **Callers receive:** the approved text — the description, or the digest in mockup form — plus the mockup markup when they asked for it, OR a routing signal "adjust plan" when the user picked option C at any round.
- **Callers are responsible for:** consuming the approved text per their own procedure — e.g. `/geniro:plan` feeds it into spec.md section 6 (Steps) + section 9 (Validation) as authoring substrate — and, in mockup form, publishing and republishing the mockup around each round.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The plan already describes the UI, skip the preview" | Plans describe files and steps. They do not describe what the user will see. The preview gate surfaces visual intent BEFORE code is written — that is its whole job. |
| "No UI files matched — skip" | Correct — skip. The gate is conditional by design, enforced by the caller. |
| "The user will approve anyway — skip" | Preview is cheap. Rebuilding UI after approval is expensive. Never skip when the rule matches. |
| "I'll describe the UI myself as the orchestrator" | Delegate to the description subagent (tier per the procedure above). Orchestrator tokens are the most expensive resource. |
| "3 revision rounds isn't enough, keep looping" | If 3 rounds did not converge, the real issue is plan-level, not preview-level. Route to plan adjustment. |
| "I'll tack on a 'also note X' after the approved description" | Rewrite the description in full via another revision round. Appended notes rot and get missed by implementation agents. |
| "The mockup is on the page, so the digest is redundant" | The persisted text is what the caller's downstream sections cite, and a page URL cannot be cited — dropping the digest leaves those sections with nothing to author from. Emit both: the page carries the detail, the digest carries the record. |
