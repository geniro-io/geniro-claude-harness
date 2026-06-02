# Security Review Criteria

OWASP-aligned security analysis: injection attacks, authentication/authorization, secrets management, crypto, input validation, and data exposure.

## Contents

- What to Check
- Output Format
- Common False Positives
- Stack-Agnostic Patterns
- Review Checklist
- Severity Guidelines

---

## What to Check

### 1. Injection Vulnerabilities
- SQL injection: unsanitized queries, string concatenation
- Command injection: shell execution with user input
- NoSQL injection: object construction from untrusted sources
- LDAP/XML injection: unsafe external data handling
- Template injection: dynamic template rendering

**How to detect:**
```bash
# SQL string concatenation patterns
grep -n "SELECT.*\+" file.js | grep -v "parameterized\|?"
grep -n "INSERT.*\+" file.js | grep -v "VALUES\s*\?"
# Shell execution
grep -n "exec\|system\|spawn" file.js | grep -v "escape\|quote\|shellwords"
# Dynamic queries
grep -n "query.*\+" file.js
```

**Red flags:**
- String concatenation with user input in queries
- Shell commands built with user data
- Database operations without parameterized statements
- Dynamic code evaluation (`eval`, `Function`)
- Template strings in SQL/command contexts

### 2. Authentication & Authorization
- Weak password validation (< 8 chars, no complexity)
- Missing authentication checks on protected endpoints
- Missing authorization (user A accessing user B's data)
- Session/token management issues
- API authentication bypasses
- Role-based access control (RBAC) gaps

**How to detect:**
```bash
# Password validation
grep -n "password\|pwd" file.js | grep -i "length\|regex\|check"
# Protected endpoints
grep -n "function\|app\." file.js | grep -v "auth\|verify\|jwt\|token"
# Token checks
grep -n "req\.\|jwt\|session" file.js | grep -v "verify\|validate\|decode"
```

**Red flags:**
- Routes without authentication middleware
- Missing user ID validation (using user-supplied ID vs verified session)
- Hardcoded credentials or keys
- Disabled security checks in code
- Temporary security disablement commented out but not removed

### 3. Secrets Management
- Hardcoded credentials (passwords, API keys, tokens)
- Secrets in logs or error messages
- Secrets in comments or version control
- Weak secret storage/encryption
- Secrets exposed in responses

**How to detect:**
```bash
# Look for hardcoded values
grep -in "password\|secret\|api[_-]?key\|token\|credential" file.js | grep -v "config\|env\|process"
# Check for secrets in logs
grep -n "console\|log\|print" file.js | grep -i "password\|secret\|key\|token"
# Environment variable usage
grep -n "process.env\|import.meta.env" file.js
```

**Red flags:**
- String literals matching credential patterns
- Secrets hardcoded in source
- Environment variables not being read
- Secrets logged or returned in error messages
- API keys in URLs or query parameters

### 4. Cryptography
- Weak hashing algorithms (MD5, SHA1)
- Encryption without authentication (ECB mode, no HMAC)
- Broken random number generation for security purposes
- Outdated crypto libraries
- Missing key rotation
- Weak key derivation

**How to detect:**
```bash
# Weak hashing
grep -in "md5\|sha1\|crc" file.js | grep -v "comment\|description"
# Crypto library calls
grep -n "crypto\|encrypt\|hash\|cipher" file.js
# Random number generation
grep -n "Math.random\|random" file.js | grep -v "seed"
```

**Red flags:**
- MD5 or SHA1 for passwords/tokens
- Encryption without HMAC or authentication
- Using `Math.random` for security tokens
- No key management strategy visible
- Deprecated crypto modules

### 5. Input Validation & Output Encoding
- Missing input validation (type, length, format, range)
- Insufficient validation (only client-side)
- Missing output encoding for XSS prevention
- File upload validation gaps
- Path traversal vulnerabilities

**How to detect:**
```bash
# Input handling without checks
grep -n "req\.\|params\|query\|body\|input" file.js | grep -v "validate\|check\|assert"
# Output rendering
grep -n "innerHTML\|eval\|dangerouslySetInnerHTML" file.js
# File operations
grep -n "readFile\|writeFile" file.js | grep -v "path.resolve\|join"
```

**Red flags:**
- User input used directly in queries/commands
- Form input not validated on server-side
- HTML output not escaped
- File paths not normalized/resolved
- Missing type coercion for security checks

### 6. Sensitive Data Exposure
- Sensitive data in clear text (no encryption in transit/at rest)
- Overly verbose error messages exposing internals
- Sensitive data in URLs or cache
- Unencrypted communications
- Exposure through timing attacks

**How to detect:**
- Check if HTTP used instead of HTTPS
- Look for error messages revealing system details
- Find sensitive data in logs
- Check cache headers and cookie settings
- Identify data exposure in responses

**Red flags:**
- PII (email, phone, SSN) returned unencrypted
- System paths in error messages
- Stack traces shown to users
- Sensitive data in cookies without HttpOnly flag
- No encryption for sensitive endpoints

### 7. Security Headers & Configuration
- Missing security headers (CSP, X-Frame-Options, HSTS)
- CORS misconfiguration (overly permissive)
- Missing CSRF protection
- Debug mode enabled in production
- Security.txt/configuration issues

**How to detect:**
```bash
# CORS configuration
grep -n "Access-Control\|cors\|CORS" file.js | grep -i "allow"
# Headers
grep -n "setHeader\|header\|\.set(" file.js | grep -v "Content-Type\|Authorization"
# Debug flags
grep -in "debug\|development\|process.env.NODE_ENV" file.js
```

**Red flags:**
- `Access-Control-Allow-Origin: *`
- Missing CSP header
- CSRF tokens not validated
- Debug/verbose logging in production code
- Security checks disabled with env vars

### 8. Dependency Security
- Known vulnerabilities in dependencies (check npm audit, cargo audit)
- Outdated packages with security patches
- Untrusted dependencies
- Unmaintained packages
- Supply chain risks

**How to detect:**
```bash
# Check lock files for outdated packages
# Review new dependencies in package.json/Cargo.toml
# Look for version pinning on vulnerable packages
```

### 9. Suppression Rule Audit

Scan the diff for newly added suppression directives that silence a previously-active security check. These are dangerous because they un-audit a flagged risk without a paper trail:

- Inline suppression comments adjacent to code (`# noqa`, `# nosec`, `# type: ignore`, `# pylint: disable=`, `# pragma: no cover`, `// eslint-disable-next-line`, `/* eslint-disable */`, `// @ts-ignore`, `// @ts-expect-error`, `// nosemgrep`, `@SuppressWarnings(...)`, `# rubocop:disable`).
- Configuration-level disables (`.eslintrc` `rules: { 'rule-name': 'off' }`, tsconfig `ignoreDeprecations` / `exclude`, `.bandit` skips, `.semgrepignore`, `.gitleaksignore`, `.rubocop.yml` `Enabled: false`, scanner CLI flags `--skip` / `--ignore-paths`).
- Aggregate suppression that hides unrelated active risk (a single `# noqa` on a line that violates multiple rules; a config block that disables a rule for an entire directory when one file needs the exception).

**How to detect:**

```bash
# Inline directives added by the diff
git diff --unified=0 | grep -E '^\+' | grep -E '(# *(noqa|nosec|pylint: *disable|type: *ignore|pragma)|// *(eslint-disable|@ts-ignore|@ts-expect-error|nosemgrep)|@SuppressWarnings|# *rubocop:disable)'

# Config-level disables added by the diff
git diff -- '*.eslintrc*' '.semgrepignore' '.gitleaksignore' '.bandit' '.rubocop.yml' 'tsconfig*.json' | grep -E '^\+.*(off|disabled|Enabled: false|exclude|skip)'
```

**Red flags:**

- Suppression directive added WITHOUT an inline comment naming the specific risk it suppresses AND a linked issue / ADR / commit explaining why the rule does not apply here.
- Broad suppression (file-level `/* eslint-disable */`, directory-level config disable) when only one line needs the exception — masks future regressions on the same rule.
- Suppression that silences the SAME rule the diff is otherwise expanding (e.g., adds `# nosec` on a new `subprocess.run(..., shell=True)` while expanding shell-exec coverage elsewhere).
- Removal of an existing `## Suppression Notice` block from active scanner output (the suppression-notice itself is being un-audited).
- Aggregate-findings flag (e.g., `--quiet`, `--severity HIGH`) added to a scanner CLI that previously surfaced lower-severity findings.

Emit HIGH severity by default. When the suppression carries a documented justification with a linked tracker issue AND the suppressed rule is narrow (single rule, single line), demote to MEDIUM.

## Output Format

Emit findings in the standard reviewer-agent output format defined in `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format.

## Common False Positives

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

## Stack-Agnostic Patterns

Works across languages/frameworks:
- JavaScript: parameterized queries (prepared statements)
- Python: `execute` with tuple parameters, not f-strings in SQL
- Go: `database/sql` with placeholders
- Rust: ORM libraries with query builders
- Java: PreparedStatement, not string concatenation

## Review Checklist

- [ ] No SQL/command injection vulnerabilities
- [ ] Authentication required on protected endpoints
- [ ] Authorization validated for user data access
- [ ] No hardcoded credentials or secrets
- [ ] Strong hashing/encryption algorithms used
- [ ] All user input validated server-side
- [ ] Output properly encoded/escaped
- [ ] No sensitive data in logs or errors
- [ ] Security headers configured
- [ ] CORS properly restricted
- [ ] Dependencies checked for vulnerabilities
- [ ] No debug/development code in production
- [ ] Suppression directives (`# noqa`, `# nosec`, eslint-disable, config-level rule off) carry inline justification and do not hide unrelated active risk

## Severity Guidelines

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/review/severity-calibration-reference.md` §1.

- **CRITICAL** — SQL injection with user-controlled input reaching a raw query; XSS via unsanitized field reaching HTML output; secret or credential committed to the repo; broken authentication (e.g., role check missing entirely); broken authorization (e.g., user-A can access user-B's data); RCE via unsafe deserialization; insecure cryptography on a production code path.
- **HIGH** — Missing input validation that REACHES a downstream consumer (trace the input to its sink — speculative "this might be exploited" is MEDIUM); IDOR or mass-assignment with a documented attack path; sensitive data in logs that's actively written; CSRF gap on a state-changing endpoint with no compensating defense; new suppression directive (`# noqa`, `eslint-disable`, `@SuppressWarnings`, config-level rule disable) added in the diff without an in-comment justification linking to a tracked issue or ADR (silently un-audits a previously-flagged risk).
- **MEDIUM** — Defense-in-depth gap that an existing layer covers (e.g., output encoding missing but the framework auto-escapes); informational disclosure that requires authenticated access; rate-limit gap on a non-critical path; weak crypto on a non-production code path.
- **LOW** — Hardening suggestions without an exploit path ("add CSP headers" when none exist but no known XSS sink); convention-style "use the safe wrapper here" without demonstrating the unsafe path is reachable; documentation or PR-description nits about a security area.
