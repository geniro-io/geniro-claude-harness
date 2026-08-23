#!/usr/bin/env bash
# Verification-checks batteries for /geniro:setup Phase Validate.
#
# Runs the three literal-token grep batteries from verification-checks.md
# (§Cross-language contamination, §Template artifact, §Generic-placeholder)
# against the given generated file(s) and prints one hit per line:
#
#   <CHECK-LABEL>|<file>:<line-number>:<line-text>
#
# CROSS-LANG hits still need the judgment call verification-checks.md §Cross-
# language contamination step 2 describes (legitimate multi-language project
# vs. generation artifact) — everything else is reported as-is; the caller
# turns every hit into a DRIFT item unless that judgment says otherwise.
#
# Usage: verification-grep.sh <language> <file> [<file> ...]
#   <language>: python | typescript | javascript | go | rust | ruby | java

set -euo pipefail

lang="${1:-}"
shift || true

if [ -z "$lang" ] || [ "$#" -eq 0 ]; then
  echo "usage: verification-grep.sh <language> <file> [<file> ...]" >&2
  exit 2
fi
files=("$@")

# --- §Cross-language contamination: wrong-stack tokens by detected language ---
cross_lang_tokens() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    python)
      printf '%s\n' 'npm' 'yarn' 'pnpm' 'tsc' 'jest' 'vitest' ' tsx' 'package.json' 'node_modules' '```typescript' '```javascript'
      ;;
    typescript | javascript | ts | js)
      printf '%s\n' 'pip' 'pytest' 'ruff' 'pyproject' 'requirements.txt' 'venv' '__init__' '```python'
      ;;
    go)
      printf '%s\n' 'npm' 'pip' 'cargo' 'gem' '```typescript' '```python' '```rust' '```ruby'
      ;;
    rust)
      printf '%s\n' 'npm' 'pip' 'go mod' '```typescript' '```python' '```go'
      ;;
    ruby)
      printf '%s\n' 'npm' 'pip' 'cargo' '```typescript' '```python' '```rust'
      ;;
    java)
      printf '%s\n' 'npm' 'pip' 'cargo' 'gem' '```typescript' '```python' '```rust' '```ruby'
      ;;
    *)
      echo "unknown language: $1 (want python|typescript|javascript|go|rust|ruby|java)" >&2
      exit 2
      ;;
  esac
}

# --- §Template artifact: fixed phrases, language-independent ---
template_tokens() {
  printf '%s\n' 'customize this' 'replace with' 'fill in' 'TEMPLATE NOTICE' 'customizable for' 'e.g.,' 'such as' 'for example'
}

# --- §Generic-placeholder: unfilled placeholders + generator residue tokens ---
placeholder_tokens() {
  printf '%s\n' '<TODO>' '<your-' 'example.com' '{{' '$TEMPLATE_DIR' '$PROJECT_KNOWLEDGE' 'PLACEHOLDER' 'TODO' 'FIXME' '<!-- geniro-setup-managed -->' '<!-- geniro-setup-end -->'
}

run_literal_battery() {
  label="$1"
  shift
  while IFS= read -r token; do
    [ -z "$token" ] && continue
    for f in "${files[@]}"; do
      [ -f "$f" ] || continue
      grep -n -F -- "$token" "$f" 2>/dev/null | while IFS= read -r hit; do
        printf '%s|%s:%s\n' "$label" "$f" "$hit"
      done || true
    done
  done < <("$@")
}

run_literal_battery "CROSS-LANG" cross_lang_tokens "$lang"
run_literal_battery "TEMPLATE" template_tokens
run_literal_battery "PLACEHOLDER" placeholder_tokens

# §Template artifact: parenthetical framework lists, e.g. "(Django, Rails, FastAPI, Spring, etc.)"
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  grep -n -E -- '\([A-Za-z][A-Za-z0-9._ ]*(, [A-Za-z][A-Za-z0-9._ ]*){2,}, etc\.?\)' "$f" 2>/dev/null | while IFS= read -r hit; do
    printf 'TEMPLATE|%s:%s\n' "$f" "$hit"
  done || true
done

exit 0
