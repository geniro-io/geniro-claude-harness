# Skill-authoring research: positive-guidance evidence pack

**Purpose.** Evidence gathered for authoring 2-3 positive-guidance rule files complementing the existing `.claude/rules/skill-authoring.md` (negative-space list). All claims are cited; sections are grouped by source-of-truth and ordered by authority.

---

## 1. Authoritative Anthropic sources (Tier 1)

### 1a. Anthropic — "Skill authoring best practices" (the canonical document)

URL: <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>

**Direct quotes (load-bearing):**

- **Token economy as the foundation.** "The context window is a public good. Your Skill shares the context window with everything else Claude needs to know... Not every token in your Skill has an immediate cost. At startup, only the metadata (name and description) from all Skills is pre-loaded. Claude reads SKILL.md only when the Skill becomes relevant... However, being concise in SKILL.md still matters: once Claude loads it, every token competes with conversation history and other context."
- **Default assumption.** "Claude is already very smart. Only add context Claude doesn't already have. Challenge each piece of information: 'Does Claude really need this explanation?' 'Can I assume Claude knows this?' 'Does this paragraph justify its token cost?'"
- **Hard line cap.** "Keep SKILL.md body under 500 lines for optimal performance. If your content exceeds this, split it into separate files using progressive disclosure patterns." (Repeated verbatim in the "Token budgets" section.)
- **References stay one level deep.** "Keep references one level deep from SKILL.md. All reference files should link directly from SKILL.md to ensure Claude reads complete files when needed... When encountering nested references, Claude might use commands like `head -100` to preview content rather than reading entire files, resulting in incomplete information."
- **TOC for long references.** "For reference files longer than 100 lines, include a table of contents at the top. This ensures Claude can see the full scope of available information even when previewing with partial reads."
- **Degrees-of-freedom model.** High freedom = text instructions (multiple valid approaches); medium = pseudocode/parameterized scripts (preferred pattern, some variation acceptable); low = exact scripts (fragile, error-prone, consistency critical). Analogy: "narrow bridge with cliffs on both sides" vs "open field with no hazards".
- **Descriptions must be third-person.** "Always write in third person. The description is injected into the system prompt, and inconsistent point-of-view can cause discovery problems. Good: 'Processes Excel files and generates reports.' Avoid: 'I can help you process Excel files.' Avoid: 'You can use this to process Excel files.'"
- **Descriptions must include both what AND when.** "Each Skill has exactly one description field. The description is critical for skill selection: Claude uses it to choose the right Skill from potentially 100+ available Skills. Your description must provide enough detail for Claude to know when to select this Skill, while the rest of SKILL.md provides the implementation details."
- **Terminology consistency.** "Choose one term and use it throughout the Skill. Good: Always 'API endpoint'. Bad: Mix 'API endpoint', 'URL', 'API route', 'path'. Consistency helps Claude understand and follow instructions."
- **Avoid offering too many options.** "Don't present multiple approaches unless necessary. Bad: 'You can use pypdf, or pdfplumber, or PyMuPDF, or pdf2image, or...' Good: 'Use pdfplumber for text extraction... For scanned PDFs requiring OCR, use pdf2image with pytesseract instead.'"
- **No time-sensitive content in main body.** Wrap deprecated content in collapsible `<details><summary>Legacy v1 API (deprecated 2025-08)</summary>` sections.
- **Frontmatter limits.** `name`: max 64 chars, lowercase + numbers + hyphens, no XML, no reserved words ("anthropic", "claude"). `description`: max 1024 chars, non-empty, no XML.
- **Naming.** Prefer gerund form (`processing-pdfs`, `analyzing-spreadsheets`); avoid vague names (`helper`, `utils`, `tools`).
- **Tables.** No mention. The doc itself uses bullets + prose + code blocks; no tables in its body.

### 1b. Anthropic — "Equipping agents for the real world with Agent Skills"

URL: <https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills>

- "Progressive disclosure is the core design principle that makes Agent Skills flexible and scalable." Three levels: metadata → SKILL.md → linked files.
- "When the SKILL.md file becomes unwieldy, split its content into separate files and reference them. If certain contexts are mutually exclusive or rarely used together, keeping the paths separate will reduce the token usage."
- "Code can serve as both executable tools and as documentation. It should be clear whether Claude should run scripts directly or read them into context as reference."
- "Sorting a list via token generation is far more expensive than simply running a sorting algorithm." (Justifies utility-script bias over inline pseudocode.)

### 1c. Anthropic — "Effective context engineering for AI agents"

URL: <https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents>

- **The north-star metric:** "Find the smallest possible set of high-signal tokens that maximize the likelihood of some desired outcome." Every unnecessary word "actively degrades agent performance."
- **The right altitude:** prompts should be "specific enough to guide behavior effectively, yet flexible enough to provide the model with strong heuristics." Avoid brittle hardcoded logic AND vague high-level guidance.
- **Just-in-time over upfront retrieval:** "Use lightweight identifiers (file paths, stored queries, web links, etc.) and dynamically load data into context at runtime using tools rather than pre-processing all data upfront."
- **Structure:** "distinct sections like `<background_information>`, `<instructions>`, and `## Tool guidance` with XML tagging or Markdown headers."
- **Curated examples beat edge cases:** "A set of diverse, canonical examples that effectively portray the expected behavior rather than stuffing edge cases into prompts."

### 1d. Anthropic — "Writing tools for agents" (the tool-description article)

URL: <https://www.anthropic.com/engineering/writing-tools-for-agents>

- Unambiguous naming: prefer `user_id` over `user`.
- "Consider the context that you might implicitly bring... and make it explicit."
- Errors must be actionable: "clearly communicate specific and actionable improvements, rather than opaque error codes or tracebacks."
- "Even small refinements to tool descriptions can yield dramatic improvements." (Mirror: small refinements to skill descriptions matter.)
- Anti-pattern: bloated tool sets where engineers can't clearly identify which tool to use (mirror: bloated skill sets).

### 1e. Anthropic — "Building effective agents"

URL: <https://www.anthropic.com/research/building-effective-agents> · <https://www.anthropic.com/engineering/building-effective-agents>

- "Start with simple prompts optimized through evaluation before adding complexity."
- "Invest as much effort in agent-computer interfaces (ACI) as human-computer interfaces (HCI)."
- "Workflows offer predictability and consistency for well-defined tasks, whereas agents are the better option when flexibility and model-driven decision-making are needed at scale."

### 1f. Claude Code skill docs (Claude-Code-specific extensions)

URL: <https://code.claude.com/docs/en/skills>

- **The CLAUDE.md vs SKILL.md heuristic (load-bearing for this plugin):** "Create a skill when you keep pasting the same instructions, checklist, or multi-step procedure into chat, or when a section of CLAUDE.md has grown into a procedure rather than a fact. Unlike CLAUDE.md content, a skill's body loads only when it's used, so long reference material costs almost nothing until you need it."
- **State what, not why:** "Keep the body itself concise. Once a skill loads, its content stays in context across turns, so every line is a recurring token cost. State what to do rather than narrating how or why, and apply the same conciseness test you would for CLAUDE.md content."
- **Frontmatter fields:** `description`, `arguments`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, `model`, `effort`, `context: fork`, `agent`, `hooks`, `paths`, `shell`.
- **Subagent skill preload exception:** "In a regular session, skill descriptions are loaded into context so Claude knows what's available, but full skill content only loads when invoked. Subagents with preloaded skills work differently: the full skill content is injected at startup."

### 1g. Anthropic's own `skill-creator` SKILL.md (the canonical example)

URL: <https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md>

- Line count: 485-1247 (different fetch tools report different numbers; the doc itself caps at "under 500 lines" but the canonical example exceeds it — interesting contradiction worth flagging).
- Uses hierarchical H1/H2/H3, NO TABLES, mix of prose + bullets + code blocks + JSON schemas.
- **Verbatim authoring rules:**
  - "Prefer using the imperative form in instructions."
  - "Try to explain to the model why things are important in lieu of heavy-handed musty MUSTs. Use theory of mind."
  - "If you find yourself writing ALWAYS or NEVER in all caps, or using super rigid structures, that's a yellow flag — if possible, reframe and explain the reasoning so that the model understands why the thing you're asking for is important."
  - "Rather than put in fiddly overfitty changes, or oppressively constrictive MUSTs, if there's some stubborn issue, you might try branching out and using different metaphors."
- **On descriptions (verbatim):** "This is the primary triggering mechanism - include both what the skill does AND specific contexts for when to use it. All 'when to use' info goes here, not in the body... Currently Claude has a tendency to 'undertrigger' skills... please make the skill descriptions a little bit 'pushy'."

---

## 2. Production-quality plugin examples (Tier 2)

### 2a. obra/superpowers (Jesse Vincent — most-installed third-party marketplace)

URL: <https://github.com/obra/superpowers-skills> · <https://github.com/obra/superpowers>

Skill directories: `architecture`, `collaboration`, `debugging`, `meta`, `problem-solving`, `research`, `testing`, `using-skills`. Total 142 skills, 36 agents across the marketplace.

Representative SKILL.md sizes (measured):
- `testing/test-driven-development/SKILL.md` — ~650 lines, ~65% prose / 35% structured. Sections: Overview / When to Use / The Iron Law / Red-Green-Refactor / Good Tests / Why Order Matters / Common Rationalizations / Red Flags / Example / Checklist / When Stuck / Debugging Integration / Final Rule. Tone: "deliberately confrontational toward common objections."
- `debugging/root-cause-tracing/SKILL.md` — ~320 lines, ~65% prose / 35% structured. Sections include When to Use (with flowchart), 5-substep process, Real Example, Stack Trace Tips.

**Key structural conventions visible:**
- Every skill has an explicit "When to Use" section (extension of frontmatter description into body).
- Anti-rationalization tables ARE used — the TDD skill has a "Common Rationalizations" section that confronts objections directly.
- Sections are organized around the lifecycle of the operation, not by feature listing.
- Frontmatter includes non-standard fields (`when_to_use`, `version`, `languages`) — these are author-conventional, not Anthropic-blessed.

### 2b. anthropics/skills (the official Anthropic-curated marketplace)

URL: <https://github.com/anthropics/skills>

Categories: Creative & Design, Development & Technical, Enterprise & Communication, Document Skills. 141k stars, 16.7k forks.

Convention: every SKILL.md starts with frontmatter `name` + `description`, then H1 title, then unstructured markdown — no enforced section schema.

### 2c. anthropics/claude-plugins-official

URL: <https://github.com/anthropics/claude-plugins-official>

The Anthropic-managed directory of "high-quality" Claude Code plugins. Used as the quality bar but doesn't publish a style guide of its own.

---

## 3. Adjacent-ecosystem patterns (Tier 3)

### 3a. Cursor rules

URL: <https://cursor.com/docs/rules>

- **"Keep rules under 500 lines"** + "split large rules into multiple, composable rules." (Independent confirmation of Anthropic's 500-line cap.)
- "Keep always-apply rules under 200 words to avoid the 'token tax', every token loads in every single request, consuming your context window budget." (<https://www.vibecodingacademy.ai/blog/cursor-rules-complete-guide>)
- "Keep rules focused, actionable, and scoped."
- "Avoid vague guidance. Write rules like clear internal docs."
- "Reference files instead of copying their contents — this keeps rules short and prevents them from becoming stale."
- **Anti-patterns:** copying entire style guides (use a linter), documenting every command (the agent knows common tools), instructions for rare edge cases, duplicating what's already in code.
- "Telling the AI what not to do is sometimes more effective than telling it what to do."

### 3b. Aider CONVENTIONS.md

URL: <https://aider.chat/docs/usage/conventions.html>

Aider's official guidance is minimal: bullet list of preferences (library choices, type-hint requirements). Load as read-only with prompt caching enabled. No file-size guidance. The 4-percentage-point improvement claim from human-curated conventions cited at <https://www.augmentcode.com/guides/how-to-build-agents-md>.

### 3c. AGENTS.md open standard

URL: <https://agents.md/> · <https://github.com/agentsmd/agents.md>

- "Require only what agents cannot discover independently."
- Agents read the nearest file in the directory tree; closest one wins.
- "Human-curated files yield roughly a 4-percentage-point improvement in agent performance" (cited by Augment Code, sources Stack Overflow's 2026 guidance).

---

## 4. Academic / industry research on prompt-length degradation (Tier 4)

### 4a. "Lost in the Middle" — Liu et al., 2024 TACL

URLs: <https://aclanthology.org/2024.tacl-1.9/> · <https://cs.stanford.edu/~nfliu/papers/lost-in-the-middle.arxiv2023.pdf>

- **Key finding:** "Performance is often highest when relevant information occurs at the beginning or end of the input context, and significantly degrades when models must access relevant information in the middle of long contexts, even for explicitly long-context models."
- U-shaped attention bias confirmed by "Found in the Middle" (2024) follow-up.

### 4b. Context-rot / prompt-bloat findings (2025)

URLs:
- <https://www.understandingai.org/p/context-rot-the-emerging-challenge>
- <https://mlops.community/blog/the-impact-of-prompt-bloat-on-llm-output-quality>
- <https://particula.tech/blog/optimal-prompt-length-ai-performance>

**Numerical thresholds:**
- **Reasoning degradation begins around 3,000 tokens** "well below the context windows of LLMs" (Goldberg et al., cited via mlops.community).
- **Accuracy plateaus 2k-4k tokens, measurable drop past 4k.** GPT-5: -12% past 4,000 tokens. Claude: holds until ~5,500 tokens. (particula.tech)
- **Adobe Feb-2025 study** on single-hop reasoning with growing context:
  - GPT-4o: 99% → 70%
  - Claude 3.5 Sonnet: 88% → 30%
  - Gemini 2.5 Flash: 94% → 48%
  - Llama 4 Scout: 82% → 22%
- **Use only 70-80% of advertised context window** for accuracy preservation.
- **Chain-of-Thought does NOT mitigate** long-context reasoning degradation.

### 4c. Context Length Alone Hurts (arxiv 2510.05381, Oct 2025)

URL: <https://arxiv.org/html/2510.05381v1>

"Performance still degrades substantially as input length increases even when a model can perfectly retrieve all the evidence with 100% exact match." This separates the retrieval problem from the reasoning-degradation problem — relevant for skills where the orchestrator finds the right skill but then must reason inside its body.

---

## 5. Concrete heuristic rules (synthesized from above, with source-of-truth)

| Rule | Threshold / Heuristic | Primary source |
|---|---|---|
| SKILL.md body line cap | ≤ 500 lines | Anthropic best-practices 1a; Cursor 3a (independent) |
| Reference graph depth | ≤ 1 hop from SKILL.md | Anthropic 1a |
| Reference file TOC | required if file > 100 lines | Anthropic 1a |
| Description max length | ≤ 1024 chars | Anthropic 1a frontmatter spec |
| Description structure | what + when (third person) | Anthropic 1a + skill-creator 1g |
| Description tone | slightly "pushy" to combat under-triggering | Anthropic skill-creator 1g; Generative Programmer 1b-derived |
| Description exclusions | end with explicit "Do NOT use for…" if real adjacencies | skill-creator + Generative Programmer ("the single most important line") |
| Tone in body | imperative form; explain WHY, not heavy MUSTs | skill-creator 1g verbatim |
| Anti-rationalization tables | acceptable per superpowers TDD; reframe with reasoning per skill-creator | Tension between 2a and 1g — 1g wins for canonical guidance |
| Token-cost framing | every line in loaded SKILL.md is recurring per turn | Claude Code skill docs 1f verbatim |
| When to inline vs reference | mutually exclusive / rarely co-used content → separate files | Anthropic 1b |
| Inline vs subagent | use `context: fork` for skills with large supporting context that shouldn't pollute main context | Claude Code docs 1f |
| Terminology consistency | one term per concept across the whole skill | Anthropic 1a |
| Options presentation | one default + escape hatch; avoid menus of equivalent choices | Anthropic 1a |
| Naming | gerund form (`processing-x`); lowercase + hyphens; no `helper`/`utils`/`tools` | Anthropic 1a |
| Time-sensitive content | wrap in collapsible "old patterns" section | Anthropic 1a |
| Token budget for instructions | reasoning degrades past ~3k; -10-12% past 4k | mlops.community / particula.tech 4b |
| Lost-in-the-middle | put critical rules at top and bottom of file, not in the middle | Liu et al. 4a |
| Cross-skill references | refer by skill slug (`/geniro:plan`), not by line/section numbers | Existing `.claude/rules/skill-authoring.md` + Anthropic 1a (one-level-deep) |
| Frontmatter description hygiene | no XML tags, no reserved words, no first/second person | Anthropic 1a |
| Validation / feedback loops | every quality-critical operation gets a validate-and-retry loop | Anthropic 1a; Generative Programmer #11 |
| Plan-validate-execute | required for batch / destructive / high-stakes ops | Anthropic 1a; Generative Programmer #12 |
| Tool description rule | unambiguous names; explicit error guidance | Anthropic 1d |
| Examples | 2-3 diverse canonical examples, not edge-case dumps | Anthropic 1c |

---

## 6. Contradictions to flag

1. **500-line cap vs Anthropic's own skill-creator (~485-1247 lines).** Anthropic's canonical guidance says ≤500; their canonical example arguably exceeds it. The user's project memory note "Line caps are guidelines" already encodes the right read: 500 is target, not strict.
2. **"Heavy-handed MUSTs are a yellow flag" (skill-creator 1g) vs "Anti-rationalization tables work" (superpowers TDD 2a).** Resolution: anti-rationalization is fine when each row provides a reasoned counter, not when it's just NEVER/ALWAYS in caps.
3. **"Just-in-time retrieval" (context-engineering 1c) vs "in-skill examples improve quality" (Anthropic 1a + 1c examples pattern).** Examples are upfront context, JIT retrieval pulls runtime data. They aren't in conflict but a writer might over-apply one principle.
4. **Cursor's "telling AI what NOT to do is more effective" (3a) vs Anthropic's "explain the why instead of MUSTs" (1g).** Reconcile: negative rules with reasoning ("don't X because Y") satisfy both.

---

## 7. Open questions the report does NOT resolve

- No quantified data on optimal anti-rationalization table size. (Authors must rely on judgment.)
- No empirical comparison of table vs bullet vs prose for the same content. The Anthropic skill-creator uses NO tables; superpowers skills use them; both are production-quality.
- No specific token-count threshold for the user's plugin's 11-skill ensemble. Plugin-wide load is metadata only at startup (Anthropic 1a), so skill count matters less than per-skill loaded size when the orchestrator selects one.

---

## 8. Source manifest (every URL cited)

Anthropic primary:
- <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>
- <https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills>
- <https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents>
- <https://www.anthropic.com/engineering/writing-tools-for-agents>
- <https://www.anthropic.com/research/building-effective-agents>
- <https://code.claude.com/docs/en/skills>
- <https://github.com/anthropics/skills>
- <https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md>
- <https://github.com/anthropics/claude-plugins-official>

Production-quality third-party plugins:
- <https://github.com/obra/superpowers>
- <https://github.com/obra/superpowers-skills>
- <https://github.com/obra/superpowers-marketplace>

Adjacent ecosystems:
- <https://cursor.com/docs/rules>
- <https://www.vibecodingacademy.ai/blog/cursor-rules-complete-guide>
- <https://aider.chat/docs/usage/conventions.html>
- <https://agents.md/>
- <https://github.com/agentsmd/agents.md>
- <https://www.augmentcode.com/guides/how-to-build-agents-md>

Research:
- <https://aclanthology.org/2024.tacl-1.9/> ("Lost in the Middle")
- <https://cs.stanford.edu/~nfliu/papers/lost-in-the-middle.arxiv2023.pdf>
- <https://www.understandingai.org/p/context-rot-the-emerging-challenge>
- <https://mlops.community/blog/the-impact-of-prompt-bloat-on-llm-output-quality>
- <https://particula.tech/blog/optimal-prompt-length-ai-performance>
- <https://arxiv.org/html/2510.05381v1> (Context Length Alone Hurts, Oct 2025)
- <https://arxiv.org/html/2511.23271v1> (Behavior-Equivalent Token, Nov 2025)

Synthesizing commentary:
- <https://generativeprogrammer.com/p/skill-authoring-patterns-from-anthropics> (14 patterns derived from Anthropic's docs)
