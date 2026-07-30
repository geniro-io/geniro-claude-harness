#!/usr/bin/env bash
# Mechanical half of the /geniro:plan Phase 7 spec validator.
#
# Spec: skills/plan/validator-checks.md
# Template being validated: skills/_shared/spec-template.md
#
# Runs the nine deterministic checks of the thirteen-check set — 1
# single_objective, 2 bounded_scope, 4 allowed_tools, 6 budget, 7 checkpoints,
# 10 placeholder_scan, 11 schema_completeness, 12 workflow_refs_consistency,
# 13 launch_config_consistency. Checks 3, 5, 8 and 9 rest on judgment no command
# can make (is this citation load-bearing, is this area sensitive, is this a real
# verification method, is this an observable signal) and stay prose in
# validator-checks.md, run orchestrator-side.
#
# API: validate_plan_spec <spec-path>
#   Prints one TAB-separated `check_id  status  finding_text  fix_hint` row per
#   check, in check-number order. status is one of pass / fail / warn / skip.
#   rc 0  — no check returned `fail`
#   rc 1  — at least one check returned `fail`
#   rc 64 — no spec path passed (EX_USAGE)
#   rc 65 — spec path is not a readable file
#
# Portability: POSIX-ish bash that also survives being sourced under zsh (the
# Bash tool runs zsh in some environments). No arrays, no process substitution,
# no GNU-only tool flags, no `\t` inside an awk bracket expression — works on
# bash 3.2 / BSD userland as well as GNU. Sourcing is side-effect free; the
# direct-run guard at the bottom is what makes the same file usable as a command.

# Exit codes — guarded so a second `source` in one shell doesn't trip
# `readonly variable` (every peer helper in lib/ carries the same guard; under a
# caller's `set -e` an unguarded re-source aborts the whole Bash block).
if [ -z "${_VPS_DEPS_LOADED:-}" ]; then
  readonly _VPS_OK=0
  readonly _VPS_CHECK_FAILED=1
  readonly _VPS_NO_TARGET=64        # EX_USAGE — caller passed no spec path
  readonly _VPS_UNREADABLE=65
  _VPS_DEPS_LOADED=1
fi

_VPS_FAILED=0
_VPS_TAB="$(printf '\t')"

# --- generic text helpers ---------------------------------------------------

# Strip a YAML scalar down to its value: leading whitespace, a trailing
# ` # comment` (only where the `#` follows whitespace, so a URL fragment
# survives), trailing whitespace, and one balanced outer quote pair.
_vps_clean() {
  local v="$1"
  while :; do
    case "$v" in
      ' '*) v="${v# }" ;;
      "$_VPS_TAB"*) v="${v#"$_VPS_TAB"}" ;;
      *) break ;;
    esac
  done
  case "$v" in
    '"'*'"') v="${v#\"}"; v="${v%%\"*}" ;;
    "'"*"'") v="${v#\'}"; v="${v%%\'*}" ;;
    *)
      v="${v%% #*}"
      v="${v%%"$_VPS_TAB"#*}"
      ;;
  esac
  while :; do
    case "$v" in
      *' ') v="${v% }" ;;
      *"$_VPS_TAB") v="${v%"$_VPS_TAB"}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$v"
}

# Frontmatter body — the lines between a line-1 `---` and the next `---`.
# Empty when the file has no frontmatter.
_vps_frontmatter() {
  awk '
    NR == 1 { if ($0 == "---") { infm = 1 } else { exit } ; next }
    infm && $0 == "---" { exit }
    infm { print }
  ' "$1"
}

# Everything after the closing `---` (the whole file when there is none).
_vps_body() {
  awk '
    NR == 1 { if ($0 == "---") { infm = 1 } else { print; body = 1 } ; next }
    infm { if ($0 == "---") { infm = 0; body = 1 } ; next }
    body { print }
  ' "$1"
}

# Line count the frontmatter occupies, so a body-relative line number can be
# reported as a file line number.
_vps_body_offset() {
  awk '
    NR == 1 { if ($0 != "---") { print 0; done = 1; exit } ; next }
    $0 == "---" { print NR; done = 1; exit }
    END { if (!done) print 0 }
  ' "$1"
}

# Lines of one `## <header>` section of the body, header line excluded.
_vps_section() {
  printf '%s\n' "$1" | awk -v h="## $2" '
    $0 == h { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
  '
}

# Section text joined into a single line, blank lines dropped.
_vps_join() {
  printf '%s\n' "$1" | awk '
    {
      line = $0
      gsub(/^[[:space:]]+/, "", line); gsub(/[[:space:]]+$/, "", line)
      if (line != "") out = (out == "" ? line : out " " line)
    }
    END { print out }
  '
}

_vps_count_bullets() {
  printf '%s\n' "$1" | awk '
    /^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]+[^[:space:]]/ { n++ }
    END { print n + 0 }
  '
}

# --- frontmatter accessors --------------------------------------------------

_vps_fm_has() {
  printf '%s\n' "$1" | grep -qE "^$2:"
}

_vps_fm_value() {
  local raw
  raw="$(printf '%s\n' "$1" | awk -v k="$2" '$0 ~ "^" k ":" { sub("^" k ":", ""); print; exit }')"
  _vps_clean "$raw"
}

# Value of a sub-key inside the indented block under a top-level key.
_vps_block_value() {
  local raw
  raw="$(printf '%s\n' "$1" | awk -v k="$2" -v s="$3" '
    !inb && $0 ~ "^" k ":" { inb = 1; next }
    inb && /^[^[:space:]-]/ { exit }
    inb && $0 ~ "^[[:space:]]+" s ":" { sub("^[[:space:]]+" s ":", ""); print; exit }
  ')"
  _vps_clean "$raw"
}

_vps_block_has() {
  printf '%s\n' "$1" | awk -v k="$2" -v s="$3" '
    !inb && $0 ~ "^" k ":" { inb = 1; next }
    inb && /^[^[:space:]-]/ { exit }
    inb && $0 ~ "^[[:space:]]+" s ":" { found = 1; exit }
    END { exit(found ? 0 : 1) }
  '
}

# List-shaped field state: `absent` / `empty` / `nonempty`. `empty` covers an
# explicit `null`, `~`, `[]`, and a key whose block carries no `- ` item.
_vps_fm_list_state() {
  printf '%s\n' "$1" | awk -v k="$2" '
    !seen && $0 ~ "^" k ":" {
      seen = 1; rest = $0
      sub("^" k ":[[:space:]]*", "", rest)
      sub(/[[:space:]]+#.*$/, "", rest); gsub(/[[:space:]]+$/, "", rest)
      if (rest != "" && rest != "null" && rest != "~" && rest != "[]") { print "nonempty"; done = 1; exit }
      if (rest != "") { print "empty"; done = 1; exit }
      inb = 1; next
    }
    inb {
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 ~ /^[[:space:]]*-[[:space:]]/) { print "nonempty"; done = 1; exit }
      if ($0 ~ /^[[:space:]]/) next
      print "empty"; done = 1; exit
    }
    END { if (!done) { if (!seen) print "absent"; else print "empty" } }
  '
}

# Primary worktree root, mirroring skills/_shared/primary-worktree.md Mode A.
_vps_primary_root() {
  local toplevel primary
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"
  primary="$(git worktree list --porcelain 2>/dev/null | awk '
    /^worktree / { path = $0; sub(/^worktree /, "", path) }
    /^bare$/     { path = "" }
    /^$/         { if (path != "") { seen = 1; print path; exit } }
    END          { if (!seen && path != "") print path }
  ')"
  if [ -z "$toplevel" ] || [ -z "$primary" ] || [ "$toplevel" = "$primary" ]; then
    printf '%s' "."
  else
    printf '%s' "$primary"
  fi
}

# --- result emission --------------------------------------------------------

_vps_emit() {
  case "$2" in fail) _VPS_FAILED=1 ;; esac
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
}

# --- checks -----------------------------------------------------------------

# 1. single_objective
_vps_check_single_objective() {
  local body="$1" sec joined sentences
  local fix="Section 1 must be exactly one goal sentence ending in a period. Rewrite as a single goal statement."
  sec="$(_vps_section "$body" "1. Objective")"
  joined="$(_vps_join "$sec")"
  if [ -z "$joined" ]; then
    _vps_emit single_objective fail "Section 1 (Objective) has no body content." "$fix"
    return
  fi
  case "$joined" in
    *'?') _vps_emit single_objective fail "Section 1 (Objective) is interrogative — it ends in a question mark." "$fix"; return ;;
  esac
  case "$joined" in
    *'.') ;;
    *) _vps_emit single_objective fail "Section 1 (Objective) does not end in a period." "$fix"; return ;;
  esac
  # Sentence boundary = a terminator at end of text, or one followed by
  # whitespace and a capital. Keeps `constants.ts:12` from counting as a break.
  sentences="$(printf '%s\n' "$joined" | awk '{ print gsub(/[.!?]([[:space:]]+[A-Z]|$)/, "&") }')"
  if [ "$sentences" -ne 1 ]; then
    _vps_emit single_objective fail "Section 1 (Objective) reads as $sentences sentences; exactly one is required." "$fix"
    return
  fi
  _vps_emit single_objective pass "" ""
}

# 2. bounded_scope
_vps_check_bounded_scope() {
  local body="$1" sec2 sec3 b2 b3
  local fix="Either section 2 or section 3 has zero bullets and no \"none with rationale\" note. Add bullets, or state \"none — open scope\" with a one-line rationale in section 3."
  sec2="$(_vps_section "$body" "2. Scope — Included")"
  sec3="$(_vps_section "$body" "3. Scope — Excluded")"
  b2="$(_vps_count_bullets "$sec2")"
  b3="$(_vps_count_bullets "$sec3")"
  if [ "$b2" -lt 1 ]; then
    _vps_emit bounded_scope fail "Section 2 (Scope — Included) has zero bullets." "$fix"
    return
  fi
  if [ "$b3" -lt 1 ]; then
    # The one escape hatch: an explicit open-scope note carrying a rationale.
    if printf '%s\n' "$sec3" | awk '
         { line = tolower($0); sub(/^[[:space:]]*[-*+][[:space:]]*/, "", line)
           if (line ~ /^none/) found = 1
           words += NF }
         END { exit((found && words >= 5) ? 0 : 1) }
       '; then
      _vps_emit bounded_scope pass "Section 3 declares open scope with a rationale." ""
      return
    fi
    _vps_emit bounded_scope fail "Section 3 (Scope — Excluded) has zero bullets and no open-scope note with a rationale." "$fix"
    return
  fi
  _vps_emit bounded_scope pass "" ""
}

# 4. allowed_tools
_vps_check_allowed_tools() {
  local fm="$1" body="$2" sec7 state body_is_none
  local fix="Sync them: a \"none\" body pairs with a null (or absent) tools_required field; a non-empty body pairs with a matching list."
  sec7="$(_vps_section "$body" "7. Tools Required")"
  body_is_none=0
  if printf '%s\n' "$sec7" | awk '
       { line = tolower($0); sub(/^[[:space:]]*[-*+][[:space:]]*/, "", line); gsub(/^[[:space:]]+/, "", line)
         if (line != "") { seen = 1; if (line ~ /^none/) none = 1; exit } }
       END { exit((!seen || none) ? 0 : 1) }
     '; then
    body_is_none=1
  fi
  state="$(_vps_fm_list_state "$fm" tools_required)"
  if [ "$body_is_none" -eq 1 ]; then
    if [ "$state" = "nonempty" ]; then
      _vps_emit allowed_tools fail "Section 7 (Tools Required) says none, but frontmatter tools_required carries a non-empty list." "$fix"
      return
    fi
  elif [ "$state" != "nonempty" ]; then
    _vps_emit allowed_tools fail "Section 7 (Tools Required) has content, but frontmatter tools_required is $state." "$fix"
    return
  fi
  _vps_emit allowed_tools pass "" ""
}

# 6. budget
_vps_check_budget() {
  local fm="$1" sub missing=""
  local fix="Add each missing key with value null if unbounded — the check reads key presence, not value."
  if ! _vps_fm_has "$fm" budget; then
    _vps_emit budget fail "Frontmatter has no budget block." "$fix"
    return
  fi
  for sub in max_files_to_edit max_lines_changed time_budget; do
    if ! _vps_block_has "$fm" budget "$sub"; then
      missing="$missing $sub"
    fi
  done
  if [ -n "$missing" ]; then
    _vps_emit budget fail "Frontmatter budget block is missing key(s):${missing}." "$fix"
    return
  fi
  _vps_emit budget pass "" ""
}

# 7. checkpoints
_vps_check_checkpoints() {
  local fm="$1" body="$2" sec6 steps state anchors a num unresolved=""
  sec6="$(_vps_section "$body" "6. Steps")"
  steps="$(printf '%s\n' "$sec6" | awk '/^[[:space:]]*-[[:space:]]*\[[ xX]\][[:space:]]*[0-9]+\./ { n++ } END { print n + 0 }')"
  if [ "$steps" -eq 0 ]; then
    steps="$(printf '%s\n' "$sec6" | awk '{ n += gsub(/<!--[[:space:]]*step-[0-9]+[[:space:]]*-->/, "&") } END { print n + 0 }')"
  fi
  if [ "$steps" -lt 5 ]; then
    _vps_emit checkpoints pass "Section 6 has $steps steps; checkpoints bind only at 5 or more." ""
    return
  fi
  state="$(_vps_fm_list_state "$fm" checkpoints)"
  if [ "$state" != "nonempty" ]; then
    _vps_emit checkpoints fail "Section 6 has $steps steps but frontmatter checkpoints is $state." \
      "Add at least one {step_anchor: step-N, name: ...} entry at a natural pause point (after a migration, at a test gate)."
    return
  fi
  anchors="$(printf '%s\n' "$fm" | awk -v qq="\"'" '
    !inb && /^checkpoints:/ { inb = 1 }
    inb && /^[^[:space:]-]/ && !/^checkpoints:/ { exit }
    inb && /step_anchor:/ {
      line = $0
      sub(/^.*step_anchor:[[:space:]]*/, "", line)
      sub(/[,}].*$/, "", line)
      gsub("[" qq "]", "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line != "") print line
    }
  ')"
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    case "$a" in
      step-[0-9]*)
        num="${a#step-}"
        if printf '%s\n' "$body" | grep -q -- "<!-- step-$num -->"; then
          continue
        fi
        if printf '%s\n' "$sec6" | grep -qE "^ *- *\[[ xX]\] *$num\."; then
          continue
        fi
        unresolved="$unresolved $a"
        ;;
      *) : ;;   # a section-name reference — the reader resolves that one
    esac
  done <<VPS_ANCHORS
$anchors
VPS_ANCHORS
  if [ -n "$unresolved" ]; then
    _vps_emit checkpoints fail "Frontmatter checkpoints reference step anchor(s) no section 6 step defines:${unresolved}." \
      "Point each step_anchor at a step that exists, or add the missing step and its <!-- step-N --> anchor."
    return
  fi
  _vps_emit checkpoints pass "" ""
}

# 10. placeholder_scan
_vps_check_placeholder_scan() {
  local spec="$1" hit token lineno
  hit="$(awk '
    NR == 1 { if ($0 == "---") { infm = 1; next } }
    infm { if ($0 == "---") infm = 0; next }
    {
      if ($0 ~ /TODO/) tok = "TODO"
      else if ($0 ~ /XXX/) tok = "XXX"
      else if ($0 ~ /FIXME/) tok = "FIXME"
      else if ($0 ~ /<placeholder>/) tok = "<placeholder>"
      else if (tolower($0) ~ /\[fill in\]/) tok = "[fill in]"
      else if ($0 ~ /(^|[[:space:]])\.\.\.([[:space:]]|$)/) tok = "..."
      else next
      print NR "\t" tok
      exit
    }
  ' "$spec")"
  if [ -n "$hit" ]; then
    lineno="${hit%%"$_VPS_TAB"*}"
    token="${hit#*"$_VPS_TAB"}"
    _vps_emit placeholder_scan fail "Found placeholder token '$token' at line $lineno." \
      "Replace it with real content, or remove the line."
    return
  fi
  _vps_emit placeholder_scan pass "" ""
}

# 11. schema_completeness
_vps_check_schema_completeness() {
  local body="$1" offset="$2" required optional missing="" extra="" found=0 h headers lineno title
  required='1. Objective
2. Scope — Included
3. Scope — Excluded
4. Assumptions
5. Risks
6. Steps
7. Tools Required
8. Approval Points
9. Validation
10. Rollback-Recovery
11. Done Condition'
  optional='Considered Alternatives
Milestones
Problem & Evidence
Comment Resolution Map'

  while IFS= read -r h; do
    [ -n "$h" ] || continue
    if ! printf '%s\n' "$body" | grep -qxF "## $h"; then
      missing="$missing; $h"
    fi
  done <<VPS_REQUIRED
$required
VPS_REQUIRED
  if [ -n "$missing" ]; then
    _vps_emit schema_completeness fail "Missing or misnamed section header(s): ${missing#; }." \
      "Restore each header with its exact canonical text from the spec template."
    return
  fi

  # Any `## ` header outside the 11 required plus the 4 allowed-optional fails.
  headers="$(printf '%s\n' "$body" | awk -v off="$offset" '/^## / { print NR + off "\t" substr($0, 4) }')"
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    lineno="${h%%"$_VPS_TAB"*}"
    title="${h#*"$_VPS_TAB"}"
    if printf '%s\n' "$required" | grep -qxF "$title"; then continue; fi
    if printf '%s\n' "$optional" | grep -qxF "$title"; then continue; fi
    found=1
    extra="$title (line $lineno)"
    break
  done <<VPS_HEADERS
$headers
VPS_HEADERS
  if [ "$found" -eq 1 ]; then
    _vps_emit schema_completeness fail "Top-level section outside the schema: $extra." \
      "Remove it, or fold its content into one of the 11 required sections — only Considered Alternatives / Milestones / Problem & Evidence / Comment Resolution Map are allowed beyond them."
    return
  fi
  _vps_emit schema_completeness pass "" ""
}

# 12. workflow_refs_consistency
_vps_check_workflow_refs() {
  local fm="$1" version parsed kinds="" kind missing_files="" bad="" row tag n field primary=""
  version="$(_vps_fm_value "$fm" geniro_schema_version)"
  if [ "$version" = "m5-v1" ] || ! _vps_fm_has "$fm" workflow_refs; then
    _vps_emit workflow_refs_consistency skip "No workflow_refs[] to check (schema version '${version:-unset}')." ""
    return
  fi

  parsed="$(printf '%s\n' "$fm" | awk -v qq="\"'" '
    function ind(s) { match(s, /^[[:space:]]*/); return RLENGTH }
    function clean(v) {
      sub(/[[:space:]]+#.*$/, "", v)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      gsub("^[" qq "]|[" qq "]$", "", v)
      return v
    }
    function handlekey(line,   k, v) {
      gsub(/^[[:space:]]+/, "", line)
      if (!match(line, /^[A-Za-z_][A-Za-z0-9_]*:/)) return
      k = substr(line, 1, RLENGTH - 1); v = clean(substr(line, RLENGTH + 1))
      if (k == "kind")                  { has_kind = (v != ""); kindv = v }
      else if (k == "issue_id")         { has_id  = (v != "") }
      else if (k == "url")              { has_url = (v != "") }
      else if (k == "fetched_at")       { has_at  = (v != "") }
      else if (k == "siblings")         { sib = 1; nsib = 0; sibid = 0 }
      else if (k == "chain_fetched_at") { if (v == "") print "CHAINEMPTY\t" nent "\t-" }
    }
    function handlesib(line,   k, v) {
      gsub(/^[[:space:]]+/, "", line)
      if (!match(line, /^[A-Za-z_][A-Za-z0-9_]*:/)) return
      k = substr(line, 1, RLENGTH - 1); v = clean(substr(line, RLENGTH + 1))
      if (k == "issue_id" && v != "") sibid = 1
    }
    function flushsib() { if (sib && nsib > 0 && !sibid) print "SIBMISSING\t" nent "\t" nsib }
    function flushentry() {
      flushsib()
      if (nent > 0) {
        if (!has_kind) print "MISSING\t" nent "\tkind"
        if (!has_id)   print "MISSING\t" nent "\tissue_id"
        if (!has_url)  print "MISSING\t" nent "\turl"
        if (!has_at)   print "MISSING\t" nent "\tfetched_at"
        if (kindv != "") print "KIND\t" nent "\t" kindv
      }
    }
    BEGIN { ei = -1; ki = -1; nent = 0 }
    !seenfw && /^workflow_refs:/ { seenfw = 1; inb = 1; next }
    inb {
      if ($0 ~ /^[[:space:]]*$/) next
      i = ind($0)
      isdash = ($0 ~ /^[[:space:]]*-[[:space:]]/)
      if (i == 0 && !isdash) { flushentry(); inb = 0; next }
      if (ei < 0) { if (!isdash) next; ei = i; ki = ei + 2 }
      if (isdash && i == ei) {
        flushentry()
        nent++; has_kind = 0; has_id = 0; has_url = 0; has_at = 0
        kindv = ""; sib = 0; nsib = 0; sibid = 0
        line = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", line)
        if (line != "") handlekey(line)
        next
      }
      if (sib && isdash && i >= ki) {
        flushsib(); nsib++; sibid = 0
        line = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", line)
        if (line != "") handlesib(line)
        next
      }
      if (sib && i > ki) { handlesib($0); next }
      if (i == ki && !isdash) { flushsib(); sib = 0; handlekey($0); next }
      next
    }
    END { if (inb) flushentry() }
  ')"

  while IFS= read -r row; do
    [ -n "$row" ] || continue
    tag="${row%%"$_VPS_TAB"*}"
    row="${row#*"$_VPS_TAB"}"
    n="${row%%"$_VPS_TAB"*}"
    field="${row#*"$_VPS_TAB"}"
    case "$tag" in
      MISSING)    bad="$bad; entry $n is missing required field \`$field\`" ;;
      SIBMISSING) bad="$bad; entry $n siblings[$field] is missing required field \`issue_id\`" ;;
      CHAINEMPTY) bad="$bad; entry $n declares an empty \`chain_fetched_at\`" ;;
      KIND)       kinds="$kinds
$field" ;;
    esac
  done <<VPS_PARSED
$parsed
VPS_PARSED

  if [ -n "$bad" ]; then
    _vps_emit workflow_refs_consistency fail "Broken workflow_refs[] entries: ${bad#; }." \
      "Re-run /geniro:plan with the tracker URL or ID in the arguments so Phase 1 can re-fetch, or hand-edit the entry to add the field."
    return
  fi

  while IFS= read -r kind; do
    [ -n "$kind" ] || continue
    [ -f "./.geniro/workflow/$kind.md" ] && continue
    [ -n "$primary" ] || primary="$(_vps_primary_root)"
    [ -f "$primary/.geniro/workflow/$kind.md" ] && continue
    case "$missing_files" in *" $kind "*) continue ;; esac
    missing_files="$missing_files $kind "
  done <<VPS_KINDS
$kinds
VPS_KINDS

  if [ -n "$missing_files" ]; then
    _vps_emit workflow_refs_consistency warn "workflow_refs[] references kind(s)${missing_files}but no matching .geniro/workflow/<kind>.md exists in cwd or the primary worktree — downstream skills will skip workflow on-task-start hooks for them." \
      "Create the workflow file (copy an existing one as a template), or remove the workflow_refs entry from the spec frontmatter."
    return
  fi
  _vps_emit workflow_refs_consistency pass "" ""
}

# 13. launch_config_consistency
_vps_check_launch_config() {
  local fm="$1" key value bad=""
  if ! _vps_fm_has "$fm" launch_config; then
    _vps_emit launch_config_consistency skip "No launch_config block — its absence is the default and never fails a spec." ""
    return
  fi
  for key in workspace deep_mode branch_freshness ship_mode tracker_status; do
    value="$(_vps_block_value "$fm" launch_config "$key")"
    if [ -z "$value" ]; then
      # tracker_status is key-presence-guarded: written only for a spec with a
      # linked tracker ticket, so its absence is legal.
      if [ "$key" = "tracker_status" ]; then continue; fi
      bad="$bad; \`$key\` is missing"
      continue
    fi
    case "$key:$value" in
      workspace:new-branch|workspace:current-branch|workspace:worktree|workspace:here) ;;
      deep_mode:true|deep_mode:false) ;;
      branch_freshness:merge|branch_freshness:rebase|branch_freshness:skip) ;;
      ship_mode:commit-no-push|ship_mode:draft-pr|ship_mode:ready-for-review|ship_mode:stop-after-review) ;;
      tracker_status:move-to-in-progress|tracker_status:leave-unchanged) ;;
      *) bad="$bad; \`$key\` is '$value', outside its enum" ;;
    esac
  done
  if [ -n "$bad" ]; then
    _vps_emit launch_config_consistency fail "launch_config problems: ${bad#; }." \
      "Set each key to a valid enum value, or remove the launch_config block to fall back to interactive /geniro:implement setup."
    return
  fi
  _vps_emit launch_config_consistency pass "" ""
}

# --- entry point ------------------------------------------------------------

validate_plan_spec() {
  local spec="${1:-}"   # default so a zero-arg call under `set -u` reaches the guard
  if [ -z "$spec" ]; then
    echo "validate_plan_spec: spec path required" >&2
    return "$_VPS_NO_TARGET"
  fi
  if [ ! -f "$spec" ] || [ ! -r "$spec" ]; then
    echo "validate_plan_spec: $spec — not a readable file" >&2
    return "$_VPS_UNREADABLE"
  fi

  _VPS_FAILED=0
  local fm body offset
  fm="$(_vps_frontmatter "$spec")"
  body="$(_vps_body "$spec")"
  offset="$(_vps_body_offset "$spec")"

  _vps_check_single_objective "$body"
  _vps_check_bounded_scope "$body"
  _vps_check_allowed_tools "$fm" "$body"
  _vps_check_budget "$fm"
  _vps_check_checkpoints "$fm" "$body"
  _vps_check_placeholder_scan "$spec"
  _vps_check_schema_completeness "$body" "$offset"
  _vps_check_workflow_refs "$fm"
  _vps_check_launch_config "$fm"

  if [ "$_VPS_FAILED" -ne 0 ]; then
    return "$_VPS_CHECK_FAILED"
  fi
  return "$_VPS_OK"
}

# Direct CLI invocation, for the Phase 7 call site and the test suite:
#   validate-plan-spec.sh .geniro/planning/<slug>/spec.md
# bash: executed means BASH_SOURCE[0] == $0. zsh: sourcing appends ":file" to
# ZSH_EVAL_CONTEXT; direct execution leaves it "toplevel" (the bash test would
# mis-read both zsh cases as sourced, since BASH_SOURCE is empty there — and an
# unguarded ${BASH_SOURCE[0]} aborts the whole source under `set -u`).
_vps_direct=0
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-toplevel}" in *:file*) ;; *) _vps_direct=1 ;; esac
elif [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
  _vps_direct=1
fi
if [ "$_vps_direct" = "1" ]; then
  validate_plan_spec "${1:-}"
  exit $?
fi
