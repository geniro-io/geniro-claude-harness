# Security Review Criteria

OWASP-aligned security analysis: injection attacks, authentication/authorization, secrets management, crypto, input validation, and data exposure.

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
- Dynamic code evaluation (`eval`, `Function()`)
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
- Using `Math.random()` for security tokens
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

## Output Format

```json
{
  "type": "security",
  "severity": "critical|high|medium",
  "title": "Brief vulnerability title",
  "file": "path/to/file.js",
  "line_start": 42,
  "line_end": 48,
  "description": "Detailed description of security risk",
  "code_snippet": "Vulnerable code",
  "vulnerability_type": "injection|auth|secrets|crypto|validation|exposure|headers|dependencies",
  "owasp_category": "A01|A02|A03|A04|A05|A06|A07|A08|A09|A10",
  "impact": "What attacker can do with this vulnerability",
  "recommendation": "How to fix it securely",
  "confidence": 90
}
```

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
- Python: `execute()` with tuple parameters, not f-strings in SQL
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

## Severity Guidelines

- **CRITICAL**: Injection vulnerability, hardcoded credentials, auth bypass, RCE path
- **HIGH**: Missing authentication, weak crypto, CSRF gap, data exposure
- **MEDIUM**: Missing security headers, validation gap, weak validation, missing HTTPS
