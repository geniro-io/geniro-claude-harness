#!/usr/bin/env bash
# Single source of truth for removing a planning task-dir's T1 ephemeral
# transients (subagent scratch outputs) while preserving the T1.5 durable
# artifacts (spec.md, state.md, plan-*.md, milestone-*.md).
#
# Callers pass the dir that owns the scratch — a planning task-dir, or a slug dir
# under .geniro/state/<skill>/ for a producer that keeps its own (see /resolve).
# Both producer skills that write into .geniro/planning/<task-dir>/ call this at
# their terminal exit. /geniro:implement cleaned its own task-dir already;
# /geniro:plan is read-only on SOURCE but still owns the scratch it writes, so it
# must clean too — otherwise a plan-only run (or a milestone-sliced plan, where
# /geniro:implement later runs in a DIFFERENT task-dir) leaves .research-*.md
# behind, and those resurface as recurring /geniro:update migration warnings.
# Deleting a skill's own scratch is not a source mutation, so it does not breach
# the read-only-on-source boundary.
#
# The list mirrors skills/_shared/state-tier-spec.md §T1 — keep them in lockstep.
# Deliberately does NOT rm -rf the task-dir: the T1.5 durables must survive so
# /geniro:review, /geniro:debug, /geniro:refactor, and Adjustment Routing can
# read spec.md / state.md / plan-*.md / milestone-*.md after the producer exits.
#
# Usage:
#   source "$_script_dir/clean-task-transients.sh"
#   clean_task_transients ".geniro/planning/<task-dir>"    # or a state slug dir
#
# Best-effort: a missing dir or a non-matching glob is a no-op (rm -f ignores
# nonexistent paths), so it is safe to call on any terminal path, including early
# exits where no scratch was ever written.

clean_task_transients() {
  local task_dir="${1:-}"
  [ -n "$task_dir" ] || return 0
  [ -d "$task_dir" ] || return 0
  rm -f \
    "$task_dir"/.kr-out.md \
    "$task_dir"/.ce-out.md \
    "$task_dir"/.tr-out.md \
    "$task_dir"/.adversarial-out.md \
    "$task_dir"/.spec-challenge-out.md \
    "$task_dir"/notes.md \
    "$task_dir"/playwright-verify.png \
    2>/dev/null
  # .research-*.md covers .research-out.md, /geniro:plan's per-facet
  # .research-<facet>.md, and the Phase 4 .research-critique-*.md critiques.
  # Matched with find, not a glob: zsh sets NOMATCH by default, so an unmatched
  # glob aborts the WHOLE rm — which would silently skip every literal above it
  # too, making the helper a no-op under the shell the Bash tool often runs.
  find "$task_dir" -maxdepth 1 -name '.research-*.md' -type f -exec rm -f {} + 2>/dev/null
  return 0
}

# Allow direct CLI invocation for tests and ad-hoc cleanup:
#   clean-task-transients.sh .geniro/planning/<task-dir>
# bash: executed ⇔ BASH_SOURCE[0] == $0. zsh: sourcing appends ":file" to
# ZSH_EVAL_CONTEXT; direct execution leaves it "toplevel" (the bash test would
# mis-read both zsh cases as sourced, since BASH_SOURCE is empty there — and an
# unguarded ${BASH_SOURCE[0]} aborts the whole source under `set -u`).
_ctt_direct=0
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-toplevel}" in *:file*) ;; *) _ctt_direct=1 ;; esac
elif [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
  _ctt_direct=1
fi
if [ "$_ctt_direct" = "1" ]; then
  clean_task_transients "${1:-}"
fi
