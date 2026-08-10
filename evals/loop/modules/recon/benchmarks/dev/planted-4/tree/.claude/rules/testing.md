# Testing conventions

Every behavioral change ships with a test in the same commit. Tests live beside
the module under test with a `.test.ts` suffix. No snapshot tests for API
responses — assert the fields that matter.
