---
globs:
  - "src/**/*.{js,ts,py,go,java,rb}"
  - "lib/**/*.{js,ts,py,go,java,rb}"
  - "api/**/*.{js,ts,py,go,java,rb}"
  - "!src/**/*.test.{js,ts}"
  - "!src/**/*.spec.{js,ts}"
---

# Backend Conventions

> `/setup` tailors this file to your detected stack: removes non-matching language examples, narrows glob patterns, and adds framework-specific conventions.

## Naming Conventions

### Functions and Methods

**Pattern**: Use camelCase for JavaScript/TypeScript, snake_case for Python/Ruby, PascalCase for types

```typescript
// TypeScript - GOOD
function getUserById(userId: string): User { }
const calculateTotal = (items: Item[]): number => { }

// TypeScript - BAD
function get_user_by_id(userId: string): User { }
```

```python
# Python - GOOD
def get_user_by_id(user_id: str) -> User:
    pass

def calculate_total(items: List[Item]) -> float:
    pass

# Python - BAD
def getUserById(userId: str) -> User:
    pass
```

### Variables

**Pattern**: Use descriptive names; avoid single-letter variables except in loops

```typescript
// GOOD
const maxRetries = 3;
const userCache = new Map();
for (let i = 0; i < items.length; i++) { }

// BAD
const m = 3;
const c = new Map();
```

### Constants

**Pattern**: Use UPPER_SNAKE_CASE for constants

```typescript
const DEFAULT_TIMEOUT = 30000;
const MAX_RETRIES = 3;
const API_VERSION = "v2";
```

## Error Handling

**Pattern**: Always handle errors explicitly; use typed exceptions/errors

```typescript
// GOOD
try {
  const user = await getUserById(id);
} catch (error) {
  if (error instanceof UserNotFoundError) {
    logger.warn(`User not found: ${id}`);
  } else {
    logger.error(`Failed to fetch user: ${error.message}`);
  }
  throw error; // Re-throw after logging
}

// BAD
try {
  const user = await getUserById(id);
} catch (error) {
  console.log(error); // Never use console.log in production code
}
```

## Async/Await vs Promises

**Pattern**: Prefer async/await for clarity; use Promise chains only when justified

```typescript
// GOOD
async function fetchUserData(userId: string): Promise<UserData> {
  const user = await getUser(userId);
  const profile = await getProfile(user.profileId);
  return { user, profile };
}

// BAD
function fetchUserData(userId: string): Promise<UserData> {
  return getUser(userId)
    .then(user => getProfile(user.profileId)
      .then(profile => ({ user, profile })));
}
```

## Logging

**Pattern**: Use structured logging with appropriate log levels (debug, info, warn, error)

```typescript
// GOOD
logger.info(`User login successful`, { userId, timestamp: new Date() });
logger.warn(`Retry attempt ${attempt}/${maxRetries} for operation ${opId}`);
logger.error(`Database connection failed`, { code, message: error.message });

// BAD
console.log("User login successful");
console.error(error); // Don't just dump the error object
```

## Database Access

**Pattern**: Use parameterized queries/ORM; never concatenate user input into SQL

```typescript
// GOOD (using ORM)
const user = await User.findById(userId);
const users = await User.find({ status: "active" });

// BAD
const users = await db.query(`SELECT * FROM users WHERE id = ${userId}`);
```

## Configuration Management

**Pattern**: Load config from environment variables; never hardcode secrets or env-specific values

```typescript
// GOOD
const config = {
  dbUrl: process.env.DATABASE_URL,
  apiKey: process.env.API_KEY,
  port: parseInt(process.env.PORT || "3000", 10),
  nodeEnv: process.env.NODE_ENV || "development",
};

// BAD
const dbUrl = "postgresql://user:pass@localhost/db";
const apiKey = "sk_live_abc123xyz";
```

## Testing

**Pattern**: Include unit and integration tests; maintain >80% code coverage

```typescript
// GOOD
describe("getUserById", () => {
  it("should return user when found", async () => {
    const user = await getUserById("123");
    expect(user.id).toBe("123");
  });

  it("should throw UserNotFoundError when not found", async () => {
    await expect(getUserById("nonexistent")).rejects.toThrow(UserNotFoundError);
  });
});

// BAD - No tests, or tests that don't cover edge cases
```

## Type Safety

**Pattern**: Always use type annotations in TypeScript; prefer strict mode

```typescript
// GOOD
interface User {
  id: string;
  name: string;
  email: string;
  createdAt: Date;
}

function processUser(user: User): void {
  // Implementation
}

// BAD
function processUser(user: any): void {
  // Type information lost
}
```
