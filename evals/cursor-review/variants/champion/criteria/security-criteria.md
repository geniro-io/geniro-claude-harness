# Security review criteria

OWASP-aligned security analysis: injection attacks, authentication/authorization, secrets management, crypto, input validation, data exposure, and cross-boundary composition / abuse cases.

Find every real defect this dimension owns by reading the changed code and its callers directly — your own analysis is the detector. The sections below are the contract you are held to: what NOT to flag, and how severity is calibrated.

## Common false positives

1. **Legitimate concatenation** — String building isn't always injection
- Check if values are sanitized before use
- Parameterized queries with explicit binding aren't vulnerable

2. **Test/demo code** — Security can be relaxed in test context
- Verify code is in test directory, not production
- Check for skip/only markers

3. **Configuration-driven** — Behavior controlled by deployment config
- CORS allowlist might be injected at runtime
- Check if values come from secure config sources

4. **Intentional exposure** — Some data is meant to be public
- Public API endpoints intentionally expose certain data
- Check API documentation

5. **Defense in depth** — Multiple checks aren't always redundant
- May have both input validation and output encoding
- Check if each layer serves a purpose

6. **Framework defaults** — Some frameworks provide security by default
- Check if using framework-provided security mechanisms
- Don't flag if using framework's recommended patterns

7. **Composition routing** — Not every composed-looking failure belongs in §10
- Deterministically test-reproducible edge case (null/boundary/coercion) → route to the bugs/tests dimensions
- Classic single-hunk vulnerability-class hit → the matching section in §1-§9
- Chain with any unverified link → not emitted at all; an uncited link is speculation, not evidence

## Severity guidelines

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1.

- **CRITICAL** — SQL injection with user-controlled input reaching a raw query; XSS via unsanitized field reaching HTML output; secret or credential committed to the repo; broken authentication (e.g., role check missing entirely); broken authorization (e.g., user-A can access user-B's data); RCE via unsafe deserialization; insecure cryptography on a production code path.
- **HIGH** — Missing input validation that REACHES a downstream consumer (trace the input to its sink — speculative "this might be exploited" is MEDIUM); IDOR or mass-assignment with a documented attack path; sensitive data in logs that's actively written; CSRF gap on a state-changing endpoint with no compensating defense; new suppression directive (`# noqa`, `eslint-disable`, `@SuppressWarnings`, config-level rule disable) added in the diff without an in-comment justification linking to a tracked issue or ADR (silently un-audits a previously-flagged risk).
- **MEDIUM** — Defense-in-depth gap that an existing layer covers (e.g., output encoding missing but the framework auto-escapes); informational disclosure that requires authenticated access; rate-limit gap on a non-critical path; weak crypto on a non-production code path.
- **LOW** — Hardening suggestions without an exploit path ("add CSP headers" when none exist but no known XSS sink); convention-style "use the safe wrapper here" without demonstrating the unsafe path is reachable; documentation or PR-description nits about a security area.
