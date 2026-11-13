# "Call the Skill tool" phrasing

Tell a skill to hand off with "call the Skill tool with ...", as Pocock's skills do.

## Why this is out of scope

Skills instruct by capability, not by tool name (`.claude/rules/skill-authoring.md` §6). A host that registers skill invocation under another name, or has none (Cursor, Codex), reads a named tool it lacks as a missing step. Write "invoke `/geniro:<skill>`".

## Prior requests

- 2026-10-05: raised while comparing Pocock's skills with Geniro's; not adopted.
