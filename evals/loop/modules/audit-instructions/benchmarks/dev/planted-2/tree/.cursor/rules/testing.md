---
description: Testing conventions
globs: "**/*.test.ts"
alwaysApply: false
---

Every test file sits beside the module it covers. Use `describe` blocks named
after the exported symbol. No snapshot tests for anything with a date in it.
