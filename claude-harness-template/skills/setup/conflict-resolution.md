# Existing File Conflict Resolution

This file is read by the `/setup` skill when existing `.claude/` files are found that were not created by this template. Read this file using the Read tool and follow these instructions.

---

**When:** `.claude/` directory exists but contains files NOT created by this template (no recognizable harness agents/skills/hooks).

This handles the case where the project already has some skills, agents, or hooks — possibly with the same names as template files but different content. The goal is to **merge the best of both**: preserve project-specific content while ensuring template structural quality.

**Guiding principle:** Always start from the **template file** and merge the user's project-specific content **into** it. Never the other direction. The template is the base because it already contains all structural patterns (compliance tables, git constraints, Definition of Done, state persistence, mid-flow handling, backpressure, context budget). Starting from the template guarantees nothing is missing — you only need to identify and port over the user's project-specific additions.

**Why template-as-base beats user-as-base:**
When you start from the user's file and try to add missing template patterns, you inevitably miss some — a 600-line project-specific file has so much content that it's easy to overlook a missing compliance table or state persistence section. When you start from the template and add the user's project-specific sections, the structural completeness is guaranteed by construction. The merge task becomes simpler: "what project-specific content does the user have?" rather than "which of 9+ structural patterns are missing?"

**Why AI-powered merge beats traditional tools:**
Traditional template updaters (Cruft, Yeoman) work at line-level diffs and fall back to `.rej` files when files diverge too much. We operate at **section level** — reading both files semantically, understanding that a "Keycloak Safety" section is project-specific (port it over) while "Phase 4: Validate" is structural (already in template). This is the key advantage of AI-driven setup over script-based generators.

**File classification precedence** (inspired by Helm's layered values):
1. **Template structural patterns** — the base (compliance tables, git constraints, Definition of Done, pipeline phases)
2. **User's project-specific content** — merged into the template (framework paths, module names, domain rules, custom commands, safety rules)
3. **Template default/generic content** — replaced by user's project-specific equivalent where it exists

**Step 1: Scan existing files**

```
Glob(".claude/agents/*.md")
Glob(".claude/skills/*/SKILL.md")
Glob(".claude/hooks/*.sh")
Glob(".claude/rules/*.md")
```

Also check for root `CLAUDE.md`. If the project has one, **leave it untouched** — the setup skill does not generate or modify CLAUDE.md.

**Step 2: Match against template files**

For each existing file, check if the template has a file at the same path. Build a comparison table:

| Existing File | Template Match? | Relationship |
|---|---|---|
| `agents/reviewer-agent.md` | Yes | ? (needs comparison) |
| `agents/custom-agent.md` | No | User-only (keep) |
| `skills/implement/SKILL.md` | Yes | ? (needs comparison) |

**Step 3: Spawn analysis subagents (parallel)**

For each file that exists in both the user's project and the template, spawn a **dedicated subagent** to analyze the overlap and recommend a resolution. All subagents run in parallel.

```
Agent(prompt: "<see subagent prompt below>", description: "Analyze overlap: {file_path}")
```

Spawn one subagent per matched file. Files with no template match (user-only) skip this — they're automatically kept.

**Subagent prompt template:**

```
You are analyzing a file overlap between a user's existing project file and a template
file during harness setup. The merge direction is: TEMPLATE is the base, user's
project-specific content gets merged INTO the template. Your job is to extract
exactly what needs to be ported from the user's file into the template.

USER'S FILE: {user_file_path}
TEMPLATE FILE: {template_file_path}

Read both files fully. Then perform this analysis:

## 1. Purpose match
Read the frontmatter/headers of both. Do they describe the same purpose?

## 2. Extract project-specific content from user's file
Go section by section through the USER'S file and identify content that is
project-specific (not present in the template's generic version):

- **Project context sections** — monorepo structure, app descriptions, tech stack specifics
  (e.g., "apps/api/ — NestJS backend with MikroORM" or "React frontend with Ant Design")
- **Custom commands** — project-specific validation, build, test commands
  (e.g., `pnpm run full-check`, `pnpm --filter @geniro/web generate:api`)
- **Framework-specific patterns** — NestJS decorators, React hooks, library-specific conventions
- **Project-specific file paths and module names** — actual paths, not placeholders
- **Safety rules** — domain-specific safety constraints
  (e.g., "NEVER run docker volume rm", Keycloak safety rules)
- **Custom agent routing** — project-specific agent names and delegation rules
  (e.g., route API issues to `api-agent`, web issues to `web-agent`)
- **Domain knowledge** — entity flows, API contracts, module responsibilities
- **Custom scope boundaries** — project-specific escalation signals, complexity criteria
- **Custom examples** — project-specific workflow examples, false positive lists
- **Custom phases or steps** — user added phases/steps not in the template
  (e.g., "Codegen Rule", "Runtime Startup Check" with project-specific ports)

For each piece of project-specific content, note:
- WHAT it is (the content itself or a summary)
- WHERE in the user's file it lives (section name)
- WHERE in the template it should go (which template section it maps to,
  or "new section" if the template has no equivalent)

## 3. Identify template sections the user's content replaces
For each template section that has generic/placeholder content, check if the
user's file has a project-specific equivalent that should REPLACE the template's
generic version. Example: template says "Run the project's build command" →
user's version says "Run `pnpm run full-check`" → the user's specific command
replaces the template's generic instruction.

## 4. Skill/Agent coherence check (only for agents with a corresponding skill)
The template architecture:
- **Skills** = orchestrators (multi-phase pipelines, spawn agents, coordinate)
- **Agents** = leaf workers (focused on one task, no orchestration)

If this is an agent file: does the user's agent contain orchestration logic
(spawning sub-agents, multi-phase pipelines, triage, batching, judge pass)?
If yes → the agent absorbed its skill's job. This is a structural mismatch.

If this is a skill file: does the user's skill contain work that belongs in a
DIFFERENT skill? (e.g., a review skill that also fixes issues — fixing belongs
in implement/follow-up, not review)

## 5. Classification (pick exactly one)

- **identical** — Same content, no project-specific additions worth porting.
- **merge** — User has project-specific content to port into the template.
  This is the most common result.
- **replace** — User's version has no project-specific content. Use template as-is.
- **restructure** — Architecture mismatch (agent duplicates skill's orchestration,
  or skill absorbs another skill's responsibility).

CRITICAL: There is NO "keep user's file" category. The template is ALWAYS the
base. Even a 600-line project-specific file gets its content ported INTO the
template, not the other way around. This guarantees all structural patterns
(compliance tables, state persistence, mid-flow handling, Definition of Done,
backpressure, context budget) are present — because they're already in the base.

## 6. Return structured output

CLASSIFICATION: <identical|merge|replace|restructure>
PROJECT_SPECIFIC_CONTENT:
  - <content summary> | FROM: <user section> | TO: <template section>
  - <content summary> | FROM: <user section> | TO: <template section>
  ...
TEMPLATE_SECTIONS_TO_REPLACE:
  - <template section> → replace generic content with <user's specific version>
  ...
COHERENCE_ISSUE: <none | description of mismatch>
RECOMMENDED_ACTION: <1-2 sentence summary>
```

**Step 4: Collect subagent results**

Wait for all subagents to complete. Build the resolution table from their structured outputs:

| File | Classification | Project Content to Port | Coherence Issue | Action |
|---|---|---|---|---|
| `agents/architect-agent.md` | merge | monorepo paths, framework patterns | none | Template base + port content |
| `agents/reviewer-agent.md` | restructure | 5 review dimensions | agent absorbed skill's orchestration | Extract criteria into files, use template agent |
| `skills/implement/SKILL.md` | merge | codegen rule, validation cmds, agent routing, startup ports | none | Template base + port content |
| `skills/review/SKILL.md` | restructure | monorepo context, data safety rule, false positives | skill has fix loop from implement | Template base + port context only |
| `skills/follow-up/SKILL.md` | merge | codegen rule, agent routing, startup ports | none | Template base + port content |
| `skills/refactor/SKILL.md` | replace | (none) | none | Template as-is |

**Step 5: Present findings to user**

Use `AskUserQuestion` with a grouped summary built from the subagent results:

```
I found existing .claude/ files. Here's how they compare to the template:

Will merge (template as base + your project-specific content):
  • skills/implement/SKILL.md — porting: your codegen rule, validation commands,
    agent routing (api-agent/web-agent), startup check ports, feature backlog flow
  • skills/follow-up/SKILL.md — porting: your codegen rule, agent routing,
    startup check ports
  • agents/architect-agent.md — porting: your monorepo paths, framework patterns

Architecture mismatch (needs restructuring):
  • agents/reviewer-agent.md — your agent has orchestration logic that belongs
    in the review skill. Fix: extract your review criteria into criteria files,
    use template's focused leaf agent
  • skills/review/SKILL.md — your review skill has a fix loop (Phases 2-3) that
    belongs in implement/follow-up. Fix: use template's pure review skill,
    port your monorepo context, false positive list, and data safety rule into it

No project-specific content (install template as-is):
  • skills/refactor/SKILL.md, skills/deep-simplify/SKILL.md

New from template (will install):
  • 6 new agents, 4 new skills, 9 hooks

User-only files (won't touch):
  • agents/api-agent.md, skills/analyze-thread/

How should I proceed?
A) Merge all — use template as base, port my project content in (Recommended)
B) Let me decide one by one
C) Keep mine as-is, only add new files
```

For "Architecture mismatch" files, explain the issue and proposed fix — never silently restructure.

**Step 6: Execute merges**

**Merge direction: template is ALWAYS the base.** This is the most important rule.

For files classified as **merge**:
1. **Start with the template file** as the base — Write it to the project path
2. Use the subagent's `PROJECT_SPECIFIC_CONTENT` and `TEMPLATE_SECTIONS_TO_REPLACE` outputs
3. For each project-specific item:
   - If it maps to an existing template section → **replace** the template's generic content
     with the user's project-specific version (e.g., template says "run your build command"
     → replace with `pnpm run full-check`)
   - If it's a new section with no template equivalent → **insert** it at the appropriate
     location (e.g., "Codegen Rule" section inserted after the relevant phase)
   - If it's project context (monorepo description, tech stack) → **insert** at the top,
     after the frontmatter and before the first phase
4. Update the frontmatter: keep the template's `allowed-tools` and structural fields,
   merge in the user's `description` if it's more specific
5. **Verify**: Read the final merged file and confirm:
   - All template structural patterns are present (they should be — they were in the base)
   - All project-specific content from the subagent's list has been ported
   - No template placeholder/generic content remains where project-specific content exists

**Why this order matters:** Starting from the template guarantees structural completeness.
You cannot accidentally miss a compliance table, state persistence section, or Definition
of Done — they're already in the base. The only work is porting project-specific content,
which the subagent has already itemized.

For files classified as **restructure**:
1. Explain the architectural issue to the user (already shown in Step 5)
2. Extract project-specific content (criteria, domain rules) into appropriate supporting files
3. Install the template's version of the agent/skill
4. Port any project-specific constraints into the template version
5. Verify the extracted content is accessible to the skill/agent

For files classified as **replace**:
1. Install template version directly (no project content to port)

**Step 7: Proceed to Phase 2**

After resolving all conflicts, proceed to Phase 2 (User Interview) as normal. The conflict resolution is complete — all files are now either merged from template + user content, replaced with template versions, or kept as user originals.
