#!/usr/bin/env bash
# Single source of truth for the branch -> state-file slug derivation.
#
# A skill writes state under a slug derived from the branch name
# (.geniro/state/tdd/state-<slug>.md, .geniro/planning/<slug>/...). The
# session-start-restore and enforce-tdd-order hooks must derive the SAME slug to
# read that state back. A divergent derivation (e.g. a different truncation
# length) computes a slug no producer ever wrote, so Tier-1 state resolution
# misses on every long branch. Keeping the derivation here is what guarantees
# producer and consumer agree.
#
# Rules (kept in lockstep with skills/_shared/within-skill-state-handoff.md
# §Slug rules): lowercase -> collapse non-alphanumeric runs to a single dash ->
# strip leading/trailing dashes -> truncate to 60 chars -> strip a dash the
# truncation may have left at the boundary.
#
# Usage:
#   source "$_script_dir/branch-slug.sh"
#   slug="$(_geniro_branch_slug "$branch")"   # from a given branch name
#   slug="$(_geniro_branch_slug)"             # from the current git branch
#
# Hooks source this with an inline fallback (so they still run on a vendored
# install without lib/); see hooks/session-start-restore.sh for the pattern.

_geniro_branch_slug() {
  local branch="${1:-}"
  if [ -z "$branch" ]; then
    branch="$(git branch --show-current 2>/dev/null || true)"
    [ -z "$branch" ] && branch="detached-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  fi
  local slug
  slug="$(printf '%s' "$branch" | tr '[:upper:]' '[:lower:]' | sed -E 's#[^a-z0-9]+#-#g; s#^-+##; s#-+$##' || true)"
  slug="${slug:0:60}"
  printf '%s' "${slug%-}"
}
