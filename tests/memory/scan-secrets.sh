#!/usr/bin/env bash
# Behavior test for lib/scan-secrets.sh. Run: bash tests/memory/scan-secrets.sh
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCAN="$REPO_ROOT/lib/scan-secrets.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FAILED=0
check() { if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 — got '$2' want '$3'" >&2; FAILED=$((FAILED+1)); fi; }

AWS="AKIA$(printf 'A1B2C3D4E5F6G7H8')"
GH="ghp_$(printf 'abcdefghijklmnopqrstuvwx')"
SK="sk-ant-$(printf 'abcdefghijklmnop1234')"
mkdir -p "$T/d/sub"
printf 'clean line\nkey=%s\n' "$AWS" > "$T/d/a.md"
printf 'x\nx\ntoken %s\n' "$GH" > "$T/d/sub/b.md"
printf 'use %s here\n-----BEGIN RSA PRIVATE KEY-----\nzzz\n-----END RSA PRIVATE KEY-----\n' "$SK" > "$T/d/c.md"
printf 'url https://user:hunter2pw@example.com/x\nsk-your-key-here\n' > "$T/d/e.md"
printf 'nothing to see\ntask-dir disk-cache\n' > "$T/clean.md"

out=$(bash "$SCAN" "$T/d"); rc=$?
check "hits rc" "$rc" 1
for want in "a.md:2	aws-key" "b.md:3	api-key:ghp" "c.md:1	api-key:sk-ant" "c.md:2	private-key" "e.md:1	url-cred"; do
  case "$out" in *"$want"*) check "reports $want" ok ok ;; *) check "reports $want" missing ok ;; esac
done
for secret in "$AWS" "$GH" "$SK" hunter2pw; do
  case "$out" in *"$secret"*) check "value hidden" leaked hidden ;; *) check "value hidden" hidden hidden ;; esac
done
case "$out" in *"e.md:2"*) check "placeholder not flagged" flagged clean ;; *) check "placeholder not flagged" clean clean ;; esac

bash "$SCAN" "$T/clean.md" >/dev/null; check "clean file rc" "$?" 0
bash "$SCAN" >/dev/null 2>&1; check "no args rc" "$?" 2
bash "$SCAN" "$T/nope" >/dev/null 2>&1; check "missing path rc" "$?" 2
[ "$FAILED" -eq 0 ]
