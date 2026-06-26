#!/usr/bin/env bash
# Repo-profile detector — decides whether a code-graph index pays off for a
# repository, or whether plain grep/Read retrieval is already complete enough.
#
# Spec: skills/_shared/repo-profile.md
#
# WHY this exists: a code-graph / AST-index MCP (GitNexus, codebase-memory,
# Serena, ...) indexes the CALL GRAPH OF CODE — functions, classes, call edges.
# Two repo shapes defeat that:
#   1. Doc-heavy repos. Coupling lives in prose cross-references (a skill .md
#      naming a helper by path), which an AST graph structurally cannot see.
#      Measured on this very plugin: for the symbol `atomic_state_write`, grep
#      reaches 52/52 coupled files in one query; a code-graph reaches only the
#      10 shell call-sites (19% recall) — it is blind to the 42 markdown
#      contract references. A graph is worse than grep here.
#   2. Small / shallow code layers. The graph's only edge over grep is
#      transitive multi-hop reachability ("blast radius N hops deep") and
#      name-unknown semantic search. On a layer of a few dozen functions with
#      call-depth ~3, that edge is marginal and does not justify the index +
#      maintenance overhead.
#   Graph payoff is real on the inverse shape — large, code-dense repos whose
#   coupling IS code call edges (the published wins were on Django-scale and
#   kernel-scale codebases). This detector separates the two shapes so a skill
#   can spin up a graph MCP only where it helps, and fall back to grep elsewhere.
#
# API:
#   repo_profile [--root <dir>] [--json]
#       Prints the measured signals and a final verdict. Default root is the
#       resolved repo root. Returns 0 on a clean measurement; on any failure it
#       still prints `verdict=grep-sufficient` (fail-open — never force an MCP
#       onto a repo we could not measure) and returns 0.
#
#   Verdicts:
#       graph-beneficial  — code-dense and deep enough that a graph index likely
#                           beats grep on relational / blast-radius / semantic
#                           queries.
#       grep-sufficient   — doc-heavy, small, or shallow; grep/Read retrieval is
#                           already complete and cheaper. Do NOT spin up a graph.
#       borderline        — mixed signals; the caller decides (a cheap A/B or a
#                           user prompt), defaulting to grep when unsure.

if [ -z "${_RP_DEPS_LOADED:-}" ]; then
  if [ -n "${BASH_SOURCE:-}" ]; then
    _rp_self="${BASH_SOURCE[0]}"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    eval '_rp_self="${(%):-%x}"'
  else
    _rp_self="$0"
  fi
  _rp_script_dir="$(cd "$(dirname "$_rp_self")" && pwd)"
  # shellcheck disable=SC1091
  source "$_rp_script_dir/repo-root.sh"
  _RP_DEPS_LOADED=1
fi

# Languages whose call graph a Tree-sitter / LSP code-graph MCP indexes well.
# Shell is included (codebase-memory and peers do parse it) but is a weak-graph
# language — it contributes to code volume yet rarely yields deep call chains.
_RP_CODE_EXT="ts tsx js jsx mjs cjs py go rs java kt kts scala c cc cpp cxx h hh hpp cs rb php swift m mm sh bash zsh"

# Documentation / prose — coupling here is invisible to a code graph.
_RP_DOC_EXT="md mdx markdown rst txt adoc asciidoc org"

# Thresholds — derived from the benchmark in the spec, not tuned to fit.
#   code_share : fraction of (code+doc) lines that is code. Doc-heavy repos
#                like this plugin (~0.36) fall below the grep bar.
#   code_lines : absolute code volume. Graph overhead amortizes only on large
#                codebases; a few-thousand-line repo is faster to grep+Read.
#   symbols    : rough definition count — a depth proxy. A shallow layer (this
#                plugin's shell helpers: ~tens) gets no transitive-query edge.
_RP_BENEFICIAL_SHARE="55"      # percent; >= triggers the code-density gate
_RP_BENEFICIAL_LINES="20000"   # OR-gated with symbols for the size requirement
_RP_BENEFICIAL_SYMBOLS="800"
_RP_GREP_SHARE="40"            # percent; < forces grep-sufficient
_RP_GREP_LINES="5000"          # < forces grep-sufficient
_RP_GREP_SYMBOLS="150"         # < forces grep-sufficient

# List repo files for a set of extensions. Prefers `git ls-files` (fast, honors
# .gitignore so vendored / build output does not skew the profile); falls back
# to `find` outside a git repo. Emits NUL-separated paths.
_rp_list_files() {
  local root="$1"; shift
  local -a globs=()
  local ext
  for ext in "$@"; do
    globs+=("*.$ext")
  done
  if git -C "$root" rev-parse --show-toplevel >/dev/null 2>&1; then
    # ls-files paths are relative to the repo root; downstream wc/grep run from
    # the caller's cwd. Re-emit them absolute so the profile is correct for any
    # target root, not only when cwd happens to equal it.
    git -C "$root" ls-files -z -- "${globs[@]}" 2>/dev/null \
      | while IFS= read -r -d '' f; do printf '%s\0' "$root/$f"; done
  else
    local -a find_args=()
    local first=1
    for ext in "$@"; do
      [ "$first" -eq 1 ] || find_args+=(-o)
      find_args+=(-name "*.$ext")
      first=0
    done
    find "$root" -type f \( "${find_args[@]}" \) -not -path '*/.git/*' -print0 2>/dev/null
  fi
}

# Sum line counts over a NUL-separated file list on stdin. Always echoes an
# integer (0 when the list is empty).
_rp_sum_lines() {
  local total=0 n
  n=$(xargs -0 -r wc -l 2>/dev/null | tail -1 | awk '{print $1}')
  [ -n "$n" ] && total="$n"
  printf '%d' "$total"
}

# Count NUL-separated paths on stdin.
_rp_count_files() {
  tr -dc '\0' | wc -c | awk '{print $1}'
}

# Rough symbol/definition count across the code files — a call-graph-depth
# proxy. A single ERE union over common definition forms (def / class / func /
# fn / function / interface / struct / impl / trait, plus shell `name() {`).
# Intentionally approximate: it only needs to separate a shallow layer (tens)
# from a deep one (thousands), not to be an exact parser.
_rp_count_symbols() {
  local root="$1"; shift
  # Pipe the NUL list straight into xargs — capturing it in a variable would
  # strip the NUL separators (command substitution drops null bytes) and
  # collapse the whole list into one unsplittable blob.
  local n
  n=$(_rp_list_files "$root" "$@" | xargs -0 -r grep -hcE \
    '(^|[^[:alnum:]_])(def|class|func|fn|function|interface|struct|impl|trait)[[:space:]]|^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{' \
    2>/dev/null | awk '{s+=$1} END{print s+0}')
  printf '%d' "${n:-0}"
}

repo_profile() {
  local root="" json=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --root) root="$2"; shift 2 ;;
      --json) json=true; shift ;;
      *) echo "repo_profile: unknown flag '$1'" >&2; return 64 ;;
    esac
  done
  [ -n "$root" ] || root="$(_geniro_repo_root)"

  # Fail-open: an unreadable root yields grep-sufficient, never a forced graph.
  if [ ! -d "$root" ]; then
    if [ "$json" = true ]; then
      printf '{"verdict":"grep-sufficient","reason":"root-unreadable"}\n'
    else
      echo "verdict=grep-sufficient"
      echo "reason=root-unreadable"
    fi
    return 0
  fi

  local code_lines doc_lines code_files doc_files symbols
  # shellcheck disable=SC2086  # word-splitting the ext lists is intentional
  code_lines=$(_rp_list_files "$root" $_RP_CODE_EXT | _rp_sum_lines)
  # shellcheck disable=SC2086
  doc_lines=$(_rp_list_files "$root" $_RP_DOC_EXT | _rp_sum_lines)
  # shellcheck disable=SC2086
  code_files=$(_rp_list_files "$root" $_RP_CODE_EXT | _rp_count_files)
  # shellcheck disable=SC2086
  doc_files=$(_rp_list_files "$root" $_RP_DOC_EXT | _rp_count_files)
  # shellcheck disable=SC2086
  symbols=$(_rp_count_symbols "$root" $_RP_CODE_EXT)

  local denom=$((code_lines + doc_lines))
  local share=0
  [ "$denom" -gt 0 ] && share=$(( 100 * code_lines / denom ))

  # Verdict. grep-sufficient wins on ANY disqualifying signal (doc-heavy OR
  # small OR shallow) — the failure modes are independent, so any one is fatal
  # to graph payoff. graph-beneficial requires code density AND scale.
  local verdict reason
  if [ "$share" -lt "$_RP_GREP_SHARE" ] \
     || [ "$code_lines" -lt "$_RP_GREP_LINES" ] \
     || [ "$symbols" -lt "$_RP_GREP_SYMBOLS" ]; then
    verdict="grep-sufficient"
    if [ "$share" -lt "$_RP_GREP_SHARE" ]; then
      reason="doc-heavy (code is ${share}% of lines; graph is blind to prose coupling)"
    elif [ "$code_lines" -lt "$_RP_GREP_LINES" ]; then
      reason="small (${code_lines} code lines; grep+Read is cheaper than indexing)"
    else
      reason="shallow (~${symbols} symbols; no transitive-query edge over grep)"
    fi
  elif [ "$share" -ge "$_RP_BENEFICIAL_SHARE" ] \
     && { [ "$code_lines" -ge "$_RP_BENEFICIAL_LINES" ] || [ "$symbols" -ge "$_RP_BENEFICIAL_SYMBOLS" ]; }; then
    verdict="graph-beneficial"
    reason="code-dense (${share}% code) and large (${code_lines} lines / ~${symbols} symbols)"
  else
    verdict="borderline"
    reason="mixed signals (${share}% code, ${code_lines} lines, ~${symbols} symbols)"
  fi

  if [ "$json" = true ]; then
    printf '{"verdict":"%s","code_share_pct":%d,"code_lines":%d,"doc_lines":%d,"code_files":%d,"doc_files":%d,"symbols_est":%d,"reason":"%s"}\n' \
      "$verdict" "$share" "$code_lines" "$doc_lines" "$code_files" "$doc_files" "$symbols" "$reason"
  else
    echo "verdict=$verdict"
    echo "code_share_pct=$share"
    echo "code_lines=$code_lines"
    echo "doc_lines=$doc_lines"
    echo "code_files=$code_files"
    echo "doc_files=$doc_files"
    echo "symbols_est=$symbols"
    echo "reason=$reason"
  fi
  return 0
}

# Allow direct CLI invocation for tests and ad-hoc checks:
#   repo-profile.sh [--root <dir>] [--json]
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  repo_profile "$@"
fi
