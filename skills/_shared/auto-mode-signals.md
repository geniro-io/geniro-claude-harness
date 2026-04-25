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
