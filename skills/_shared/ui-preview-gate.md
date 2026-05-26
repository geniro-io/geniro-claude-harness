# UI Preview Gate

A pre-approval procedure that produces a textual description of how the UI will look after a change, lets the user critique or rewrite it in their own words, and only then returns control to the caller's approval flow. Callers invoke this when a change touches UI files so the user shapes visual intent BEFORE any code is written.

## When to run

Skip entirely unless at least one file in the predicted affected-files list matches the UI-file detection rule in `skills/review/SKILL.md` §UI-file detection rule (the globs for `components/pages/app/views/ui` directories plus JSX/TSX/Vue/Svelte/CSS/SCSS/styled extensions). Callers must check this condition before entering the procedure — do NOT re-check here.

## Procedure

### Step 1: Spawn the UI description agent

Spawn a general-purpose subagent with `model="haiku"` (mechanical transformation of spec/plan into a structured description — not reasoning work).

```
Agent(model="haiku", prompt="""
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

### Step 2: Present to user

Present the agent's output verbatim. Then use `AskUserQuestion` (do NOT print options as plain text) with header "UI preview":

- A) **Looks right — approve** — matches my intent, proceed to the caller's approval flow
- B) **Describe differently — I'll explain** — I want to describe how the UI should look in my own words
- C) **Adjust the plan instead** — the description is fine but the underlying plan is wrong

### Step 3: Revision loop (only if user picked B)

1. Fire a follow-up `AskUserQuestion` with header "Your version" offering two meaningful options: "Rewrite the whole description — I'll describe it fresh" / "Add targeted changes — I'll list specific edits". The user can also type freely via "Other". Capture the user's text from whichever option they pick.
2. Re-spawn the UI description agent with the captured text appended as `USER GUIDANCE: <text>` in the "Prior user guidance" input. If the user picked "Add targeted changes", instruct the agent to apply those edits to the prior description rather than starting over.
3. Re-present (Step 2) with the revised description.
4. **Max 3 revision rounds.** After round 3, fire `AskUserQuestion` with header "UI preview" and options: "Proceed with latest version" / "Adjust the plan instead". Do NOT loop a 4th time.

### Step 4: Emit approved description

Write the approved description to the caller-designated path (e.g., `<task-dir>/ui-preview.md` for `/geniro:implement`, or hold in-memory for `/geniro:follow-up`). Return control to the caller along with the file path or content.

## Caller contract

- **Callers provide:** predicted affected-files list, spec/change-request, 1-2 exemplar UI files, destination path for the approved description.
- **Callers receive:** approved UI description content (or path), OR a routing signal "adjust plan" when the user picked option C at any round.
- **Callers are responsible for:** feeding the approved description into every Phase-4/Phase-2 implementation agent that touches UI files under a `## UI Intent` section of that agent's prompt.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The plan already describes the UI, skip the preview" | Plans describe files and steps. They do not describe what the user will see. The preview gate surfaces visual intent BEFORE code is written — that is its whole job. |
| "No UI files matched — skip" | Correct — skip. The gate is conditional by design, enforced by the caller. |
| "The user will approve anyway — skip" | Preview is cheap. Rebuilding UI after approval is expensive. Never skip when the rule matches. |
| "I'll describe the UI myself as the orchestrator" | Delegate to the haiku agent. Orchestrator tokens are the most expensive resource. |
| "3 revision rounds isn't enough, keep looping" | If 3 rounds did not converge, the real issue is plan-level, not preview-level. Route to plan adjustment. |
| "I'll tack on a 'also note X' after the approved description" | Rewrite the description in full via another revision round. Appended notes rot and get missed by implementation agents. |
