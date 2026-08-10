## D2 — Accuracy vs repo reality

**Scope:** every surface. **Method:** reviewer seeded with D1's command and path candidates. Where a cited path is absent, check git history before flagging blind — a rename with a known survivor yields a better fix instruction than a deletion notice, and a recently removed dependency confirms a stale claim.

A wrong instruction doesn't fail once — it misleads every run until someone notices, which is why this dimension tiers high.

Checks:
1. **Dead commands.** Documented build/test/lint/deploy commands absent from the repo's manifests, scripts, and CI (adjudicate the D1 candidates; check whether the command is a global tool the repo's toolchain evidence supports before flagging).
2. **Moved or removed paths.** Cited files and directories that no longer exist. Distinguish load-bearing ("config lives in `src/config.ts`") from illustrative ("e.g. a file like `foo/bar.ts`").
3. **Stack and version claims.** Framework, language, and tool claims contradicted by lockfiles and manifests — "we use React 17" against a v19 lockfile entry; a described package manager the repo's lockfile format contradicts; described APIs the pinned framework version has dropped; year references that visibly date the text.
4. **Described workflow vs reality.** Documented processes (migrations, release steps, codegen) whose scripts or tools are gone or renamed; conventions stated as current that the codebase visibly abandoned.
5. **Cross-surface pointers.** An instruction file citing another instruction file or section that no longer exists.
6. **Stale counts and ordinals.** A stated count of things the repo contains ("our five services") and numbered cross-references ("see step 3") decay silently as the repo or the file changes. Verify each against reality; the fix removes the number — point at the list, anchor by name — rather than refreshing it, which only resets the clock.

Tier mapping: actively misleads an agent → T1; decayed but ignorable → T3.

