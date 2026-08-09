# Security review criteria
## Contents
## What to check
### 1. Injection Vulnerabilities
# SQL built by concatenation. Use -E: in a basic-regex grep, `.*\+` is an invalid repetition
# operand and the command aborts with an error instead of searching.
# Shell execution
# Dynamic queries
### 2. Authentication & Authorization
### 3. Secrets Management
# Look for hardcoded values. Use -E: in a basic-regex grep `?` is a literal, so
# `api[_-]?key` matches none of apiKey / api_key / api-key, and the surviving
# alternatives make the probe look like it works.
### 4. Cryptography
### 5. Input Validation & Output Encoding
# Input handling without checks
# Output rendering
# File operations
### 6. Sensitive Data Exposure
### 7. Security Headers & Configuration
# CORS configuration
# Headers
# Debug flags
### 8. Dependency Security
### 9. Suppression Rule Audit
# Inline directives added by the diff
# Config-level disables added by the diff
### 10. Composition & Abuse Cases
**Severity.** Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1 — this check only tightens them, never loosens:
## Common false positives
## Review checklist
## Severity guidelines
