# Onboard — detailed reference

Detail sections extracted from `${CLAUDE_PLUGIN_ROOT}/skills/onboard/SKILL.md` to keep the main skill body lean. The orchestrator reads this file when SKILL.md references one of the sections below by name.

## Contents

1. _CODEBASE_MAP.md format example — full 8-section worked example
2. Discovery-learning emit payload — the `emit_learning` call SKILL.md §2.3 fires

---

## 1. _CODEBASE_MAP.md format example

The 8-section template in SKILL.md §Outputs is the operative spec; this skeleton illustrates the rendering form each section takes — a table, a fenced tree, a numbered flow, or bullets — not a specific stack.

````markdown
# Codebase Map: [Project Name]

**Generated:** [date]
**Language:** [primary language]
**Framework:** [primary framework(s)]

## Project Overview

Table: Aspect | Details — rows for Purpose, Language/Stack, Entry Point, [datastore if any].

## Directory Structure

Fenced tree of the real top-level layout, annotated with a one-line role per folder (`# comment`).

## Module Relationships

Fenced ASCII dependency diagram (top-level module → what it calls), followed by a **Key Flows** bullet list: `<Actor action> → <module.function> → <downstream call>`.

## Architecture Patterns

Table: Pattern | Usage | Files — one row per recurring pattern actually present (MVC, DDD, Hexagonal, DI, etc.), not a fixed set.

## Key Files & Configuration

Table: File | Role — the real config/build/manifest files. Followed by an **Entry points** bullet list (server/CLI entry, test command, any setup/migration command).

## Conventions & Defaults

Bullet list, one line per convention actually observed — naming, file layout, testing, error handling, logging, auth, or any other project-specific default worth naming.

## Critical Paths

One `### <flow name>` subsection per critical flow, each a numbered step list from trigger to result (e.g. a request path or a job pipeline), grounded in the code actually read.

## Tech Debt & Notes

Table: Issue | Impact | Workaround — real gotchas and legacy patterns found during the scan, not a placeholder set.
````

---

## 2. Discovery-learning emit payload

The exact `emit_learning` call SKILL.md §2.3 fires after `_CODEBASE_MAP.md` write, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §Caller contract:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
emit_learning <<'EOF'
{
"producer": "/geniro:onboard",
"type": "discovery",
"tags": ["onboard", "architecture", "<language>"],
"scope": "global",
"trust": "verified",
"summary": "<one-line architectural pattern>",
"ext": {
"area": "<top-level area, e.g. 'services', 'hexagonal-ports'>",
"insight": "<2-3 sentence non-obvious finding from the scan>"
}
}
EOF
```

After a successful emit, echo `Recorded learning: <summary>` to the user.
