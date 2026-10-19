---
paths:
  - "tests/**"
---

# Tests

A test runs the code it protects and asserts what that code does: a hook on a crafted payload, a `lib/` helper on a scratch file, a generator against its output, a script in a scratch repo. Red without the fix, green with it.

A check that greps an instruction file for a phrase, a word list, a count or a heading is not a test. It pins wording, blocks the next correct edit, and proves nothing about a run. Do not add one, and do not extend one.

The exception is structural breakage a run actually hits, kept in the existing integrity checks: a path or `${CLAUDE_PLUGIN_ROOT}` reference that does not resolve, frontmatter that does not load, a generated copy out of sync with its generator, a hook registration naming a missing script.
