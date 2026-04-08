---
globs:
  - "src/**/*.{js,ts,py,go,java,rb,php,c,cpp,rust}"
  - "lib/**/*.{js,ts,py,go,java,rb,php,c,cpp,rust}"
  - "app/**/*.{js,ts,py,go,java,rb,php,c,cpp,rust}"
  - "*.{yml,yaml,json,xml,conf,config}"
  - "docker*"
  - "!**/*.test.*"
  - "!**/*.spec.*"
  - "!**/node_modules/**"
  - "!**/venv/**"
  - "!**/vendor/**"
---

# Security Patterns

> `/setup` tailors this file to your detected stack: removes non-matching language examples, narrows glob patterns, and adds framework-specific security checks.

## Input Validation

**Pattern**: Always validate and sanitize user input; never trust client-side validation

```typescript
// GOOD - Whitelist approach
function validateEmail(email: string): boolean {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email) && email.length <= 254;
}

// BAD - No validation
function processUserInput(input: string): void {
  const query = `SELECT * FROM users WHERE name = '${input}'`; // SQL injection!
}
```

```python
# GOOD
import re

def validate_username(username: str) -> bool:
    """Validate username: alphanumeric and underscore only, 3-20 chars."""
    if not isinstance(username, str) or len(username) > 20:
        return False
    return bool(re.match(r"^[a-zA-Z0-9_]{3,20}$", username))

# BAD
def process_user_input(user_input: str):
    query = f"SELECT * FROM users WHERE name = '{user_input}'"  # SQL injection!
    db.execute(query)
```

## SQL Injection Prevention

**Pattern**: Always use parameterized queries/prepared statements; never concatenate user input

```typescript
// GOOD - Using parameterized query
const user = await db.query(
  "SELECT * FROM users WHERE id = $1 AND status = $2",
  [userId, "active"]
);

// GOOD - Using ORM
const user = await User.findOne({ id: userId, status: "active" });

// BAD - String concatenation
const user = await db.query(`SELECT * FROM users WHERE id = ${userId}`);
```

```python
# GOOD - Parameterized query
cursor.execute("SELECT * FROM users WHERE id = %s AND status = %s", (user_id, "active"))

# GOOD - ORM
user = User.objects.get(id=user_id, status="active")

# BAD - F-string interpolation
cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")
```

## Authentication & Password Security

**Pattern**: Hash passwords with strong algorithms (bcrypt, scrypt, PBKDF2, Argon2); never store plaintext

```typescript
// GOOD - Using bcrypt
import bcrypt from "bcrypt";

async function registerUser(email: string, password: string): Promise<void> {
  const saltRounds = 12;
  const hashedPassword = await bcrypt.hash(password, saltRounds);
  await User.create({ email, passwordHash: hashedPassword });
}

// BAD - Plaintext storage
async function registerUser(email: string, password: string): Promise<void> {
  await User.create({ email, password }); // NEVER DO THIS
}
```

```python
# GOOD
from django.contrib.auth.hashers import make_password, check_password

def register_user(email: str, password: str):
    user = User(email=email, password_hash=make_password(password))
    user.save()

# BAD
def register_user(email: str, password: str):
    user = User(email=email, password=password)  # NEVER DO THIS
    user.save()
```

## Cross-Site Scripting (XSS) Prevention

**Pattern**: Always escape/sanitize user-controlled content; use template engines with auto-escaping

```typescript
// GOOD - Explicit HTML escaping
function escapeHTML(text: string): string {
  const map: { [key: string]: string } = {
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
  };
  return text.replace(/[&<>"']/g, (char) => map[char]);
}

// BAD - Direct HTML injection
element.innerHTML = userInput; // NEVER DO THIS
```

```python
# GOOD - Django templates auto-escape by default
# In template: <div>{{ user_comment }}</div>

# BAD - Marking as safe without sanitization
from django.utils.safestring import mark_safe
html = mark_safe(f"<div>{user_input}</div>")  # XSS vulnerability!
```

## Cross-Site Request Forgery (CSRF) Prevention

**Pattern**: Use CSRF tokens for state-changing operations; validate origin/referer headers

```typescript
// GOOD - Validate token on POST
app.post("/api/login", (req, res) => {
  if (!validateCSRFToken(req.body.csrf_token, req.session)) {
    return res.status(403).json({ error: "CSRF token invalid" });
  }
});

// BAD - No CSRF protection
app.post("/api/login", (req, res) => {
  // Process login without token validation
});
```

```python
# GOOD - Django's built-in CSRF protection
from django.middleware.csrf import csrf_protect

@csrf_protect
def login_view(request):
    if request.method == "POST":
        return process_login(request)

# BAD - CSRF protection disabled
@csrf_exempt
def login_view(request):
    pass
```

## Authorization Checks

**Pattern**: Always verify user has permission before allowing access; check on every sensitive operation

```typescript
// GOOD - Authorization check
async function deleteUser(userId: string, requestingUserId: string): Promise<void> {
  const requestingUser = await User.findById(requestingUserId);
  if (requestingUserId !== userId && requestingUser.role !== "admin") {
    throw new ForbiddenError("Not authorized to delete this user");
  }
  await User.deleteById(userId);
}

// BAD - No authorization check
async function deleteUser(userId: string): Promise<void> {
  await User.deleteById(userId); // Anyone can delete anyone!
}
```

## Secrets Management

**Pattern**: Never hardcode secrets; use environment variables or secrets management tools

```typescript
// GOOD - Using environment variables
const config = {
  dbUrl: process.env.DATABASE_URL,
  apiKey: process.env.API_KEY,
  jwtSecret: process.env.JWT_SECRET,
};

// BAD - Hardcoded secrets
const dbPassword = "super_secret_password_123";
const apiKey = "sk_live_abc123xyz";
```

```python
# GOOD - Using environment variables
from decouple import config

DATABASE_PASSWORD = config("DB_PASSWORD")
API_KEY = config("API_KEY")

# BAD - Hardcoded secrets
DB_PASSWORD = "super_secret_password_123"
```

## Dependency Security

**Pattern**: Regularly audit and update dependencies; remove unused packages

```bash
# JavaScript/TypeScript
npm audit
npm audit fix

# Python
pip-audit
pip check

# Go
govulncheck ./...

# Rust
cargo audit
```

## Data Exposure Prevention

**Pattern**: Minimize logging of sensitive data; redact passwords, tokens, and PII in logs

```typescript
// GOOD - Redacting sensitive data
logger.info("User login attempt", { userId: user.id, timestamp: new Date() });

// BAD - Logging sensitive data
logger.info("Login", { userId: user.id, password: password });

// BAD - Exposing internals to client
res.status(500).json({ error: error.toString() });
```

## Rate Limiting

**Pattern**: Implement rate limiting on authentication and sensitive endpoints

```typescript
// GOOD - Rate limiting on login
import rateLimit from "express-rate-limit";

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5,
  message: "Too many login attempts, please try again later",
});

app.post("/api/login", loginLimiter, async (req, res) => {
  // Process login
});
```

## HTTPS/TLS

**Pattern**: Always use HTTPS in production; enforce HSTS headers

```typescript
// GOOD - HSTS headers
app.use((req, res, next) => {
  res.setHeader("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
  next();
});
```
