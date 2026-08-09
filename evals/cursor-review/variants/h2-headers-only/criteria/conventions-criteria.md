# Conventions review criteria
## Contents
## Methodology — modal pattern inference
## What to check
### 1. Sibling-File Consistency
# Sibling helper-placement modal
# Triplet-shape modal
# Apply the modal threshold (§Methodology step 5) and flag the diff that diverges.
### 2. Mixing of Code Kinds
# Are sibling files type-pure or mixed?
# Constants in dedicated files?
### 3. Declaration Order Within a File
# Section ordering across siblings — extract top-level kinds in order
# Apply the modal threshold (§Methodology step 5) and flag the diff if it reorders.
### 4. Naming Style — Modal Detection
# Filename casing modal
# Pick the variant ≥80% of N≥3 — flag the diff if it deviates.
# Private-method affix modal
### 5. Import Grouping Mode
# Skip if formatter/linter already enforces ordering
# Are import groups separated by blank lines?
# Apply the modal threshold (§Methodology step 5) and flag the diff that inlines them.
### 6. Error-Handling Pattern Modal
# Result vs try/catch in a service directory
# Pick the modal — flag if the diff introduces the minority pattern.
# Are errors typed?
### 7. Class Construction Pattern
# Factory vs constructor modal
# Class member ordering across siblings
### 8. Module / Layer Boundaries (Intra-File Grain)
# Do controllers import from db/ in this repo?
# Do UI components hit api/ directly?
# Reverse-direction sniff
# If 0 of 8 siblings cross the boundary — and the diff does — that is the finding.
### 9. Sibling File Sample — Step 0
# Always run this first for each changed file
# If fewer than 3 results, broaden to analogous directories before giving up.
## What this dimension does NOT cover
## How to detect — worked example
# Step 0: glob siblings of the same kind
# Output: Avatar.tsx Badge.tsx Banner.tsx Card.tsx Header.tsx Spinner.tsx Toast.tsx
# N=7 siblings — proceed.
# Category: export style modal
# 6/7 = 86% use named exports. Modal threshold met.
# Inspect the diff
# → export default function UserCard(...)
## [NEW] vs [PRE-EXISTING] tagging
## Common false positives
## Stack-agnostic patterns
## Cross-PR convention drift (peer-PR context)
## Review checklist
## Severity guidelines
