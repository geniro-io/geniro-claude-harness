# Auto-Mode Signal Detection — Canonical Rule

Single source of truth for detecting "auto mode" in `$ARGUMENTS` across skills that support it (`/geniro:implement`, `/geniro:decompose`).

## The rule

Match ONLY unambiguous urgency phrases — `"just do it"`, `"ASAP"`, `"no questions"`. Substring-match is case-insensitive but MUST include the full phrase. Single words `"auto"` and `"quick"` MUST NOT be used as triggers — they collide with common technical vocabulary (`auto-save`, `auto-retry`, `quick-action`, `autocomplete`) and produce accidental auto-mode activations.

## Signal table

| Phrase | Match type | Triggers auto-mode |
|---|---|---|
| `just do it` | Case-insensitive substring | Yes |
| `ASAP` | Case-insensitive substring | Yes |
| `no questions` | Case-insensitive substring | Yes |
| `auto` | Single word (NOT a valid trigger) | No — collides with `auto-save`, `autocomplete`, etc. |
| `quick` | Single word (NOT a valid trigger) | No — collides with `quick-action`, `quick-fix`, etc. |

## Matching procedure

1. Perform a case-insensitive substring check of `$ARGUMENTS` against the three valid phrases above.
2. If ANY of the three phrases appears, auto-mode is triggered — skip the Mode Selection `AskUserQuestion` and proceed with auto-mode behavior.
3. If none match, fall through to the skill's Mode Selection prompt (skill-specific).

## How skills reference this

Add this one-liner near the auto-mode detection rule in any skill that supports it:

> **Auto-mode signal detection:** Follow `skills/_shared/auto-mode-signals.md`.

## Not a per-skill trigger: harness "Auto Mode"

Claude Code (the CLI) has a runtime feature called **Auto Mode** that injects a system reminder ("## Auto Mode Active … Minimize interruptions — Prefer making reasonable assumptions over asking questions for routine decisions"). This is **NOT** a skill-level auto-mode signal.

Per Anthropic engineering ("Claude Code auto mode: a safer way to skip permissions"), the harness Auto Mode is a **permission classifier** — it scopes tool-use approvals, not skill control flow. The "minimize interruptions" line is a soft model nudge for *routine* decisions; it does NOT instruct the model to skip clarifying-question tools like `AskUserQuestion`, and it does NOT translate to a per-skill pipeline-mode answer.

**Rule (control flow):** Skills that support an `auto` pipeline-mode (`/geniro:implement`, `/geniro:decompose`) MUST detect it ONLY from the three canonical phrases above in `$ARGUMENTS`. Do NOT promote the harness "Auto Mode Active" reminder, the user's permission-mode setting, or any environment signal into a per-skill auto-mode trigger. The skill's Mode Selection / gray-area `AskUserQuestion` calls fire regardless of harness Auto Mode state.

**Rule (transcript framing):** In skills with no auto-mode concept (everything except `/geniro:implement` and `/geniro:decompose`), do NOT announce "Auto mode → proceeding without prompting" or similar harness-Auto-Mode framing in user-facing transcripts. When a deterministic rule (e.g., scope-anchor) resolves a target without a user gate, there is no question being skipped — just report the resolved target. Importing harness Auto Mode framing implies a non-existent gate and makes users think the skill has an auto mode it does not. This applies to both live transcripts and final reports.

**Edge case — empty AUQ answer:** Upstream Claude Code bugs (#29547, #30523, #47114) can cause `AskUserQuestion` to silently auto-resolve with an empty answer when the tool is in a skill's `allowed-tools`. An empty answer is **not** a user choice — fall back to plain-text and re-ask. Do NOT promote empty to "auto."
