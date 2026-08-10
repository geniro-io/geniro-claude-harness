## D7 — Magic numbers & duplicated constants

**Scope:** `skills/`, `agents/`, `.claude/skills/`, `hooks/`, `lib/`. **Method:** LLM reviewer seeded with a number-density grep.

Seed grep (orchestrator runs, pastes matches into the prompt): `grep -rhoE '(≤|>=|<=|≥|max |cap |within )[0-9]+|[0-9]+ (retries|rounds|lines|files|questions|attempts|seconds|chars|tokens)' skills/ agents/ .claude/skills/ | sort | uniq -c | sort -rn | head -80` — `-h`, not `-n`: a `file:line:` prefix makes every line unique, so `uniq -c` would count nothing and the multi-homed-constant signal vanishes; the reviewer greps locations for the candidates it pursues. Plus `grep -rnE '[0-9]{3,}' hooks/ lib/ --include='*.sh' | grep -v ':[[:space:]]*#'` (POSIX class, not `\s` — BSD grep treats `\s` as a literal `s`).

Checks:
**Two dispositions, and the split is the whole discipline of this dimension.** A number that lives in exactly one place and explains itself is doing its job — the fix is an inline WHY or a citation, and the number stays. A number that is *restated*, or that *counts something the repo changes*, or that *ordinals a list an edit can reorder*, cannot stay correct: it has no single home to be fixed in. The keep-the-number group and the remove-the-number group below split this way — do not blur the two: stripping a self-explaining single-homed threshold costs a rationale the model was relying on and buys nothing.

Keep-the-number checks:

1. **Unexplained thresholds.** A numeric limit with no adjacent rationale and no citation to a canonical source. The fix is an inline WHY or a citation — keep the number itself.
2. **Contradicting constants.** The same concept with DIFFERENT values in different files (this is a T1, not T4).
3. **Shell literals.** Hardcoded sizes/timeouts in hooks/lib without a comment or env-override; duplicated literals that must move in lockstep.

Remove-the-number checks — the drift-prone classes. For these, "add a WHY" is not an acceptable fix, because the defect is that the value exists in more than one place at all:

4. **Multi-homed constants.** The same threshold stated in ≥2 files, **even while the values agree** — agreement today is drift tomorrow. Fix: one home keeps the number, every other site cites it. A file that names another file as the owner and then restates the value anyway is this check's most common shape, and the restatement is what to delete.
5. **Prose counts of repo contents.** A count of things the repo contains — skills, agents, helpers, test suites, dimensions, reviewers, assertions, bypass IDs, load-set files. Hook counts are excluded: `lint-hook-wiring.sh` decides those, including the Cursor-unwired gap that has already drifted once. Measure each against reality, then **reword so the count is not stated**: the list lives elsewhere, so the sentence should point at it rather than tally it. "the seven per-skill scopes" becomes "the per-skill scopes"; "the same batch as the 7-10 built-ins" becomes "the same batch as the consumer's built-in dimensions". Re-stating the corrected number only resets the clock on the same defect.
6. **Drifting ordinals.** A hardcoded step, phase, check, sub-phase, or invariant NUMBER used as a cross-reference. Inserting or removing one item silently invalidates every reference past it, and a renumbering pass that misses one site produces a citation that resolves to the wrong step — worse than one that dangles, because nothing detects it. Fix: content anchors per `.claude/rules/skill-structure.md` §Cross-skill references ("the F→P invariant", not "step 4.3"). Two carve-outs stay numeric: a number that is part of a **contract** other files grep for (a schema version, a phase-enum value, an exit code), and a **contiguity requirement** a validator enforces (a check set that must run 1..N). Flag the reference, not the heading it points at.

Tier mapping: contradicting constants → T1; multi-homed / unexplained / drifting ordinals → T4; stale prose counts → T3.

