#!/usr/bin/env bash
# Strip Geniro plugin doctrine + slash-command mentions from a project's CLAUDE.md.
#
# Spec: skills/_shared/strip-geniro-tags.md
#
# A project's CLAUDE.md is meant to hold only project-specific content
# (stack / commands / conventions / domain). Geniro plugin doctrine
# (skill tables, hook summaries, memory-layer descriptions, path rules,
# MCP-dependency tables) is loaded automatically by the plugin and
# should never live in a project's CLAUDE.md. This helper removes any
# such sections that may have leaked in via copy-paste from the plugin's
# own CLAUDE.md, via pre-v2.4 setup runs, or via manual user edits.
#
# Strip rules (applied in order):
#   1. Drop the H1 line "# Geniro Plugin" if present.
#   2. Drop any H2 section whose heading is in the plugin-doctrine list
#      OR whose body contains ${CLAUDE_PLUGIN_ROOT} / geniro-claude-plugin
#      / geniro-claude-harness.
#   3. In surviving sections, drop individual lines containing /geniro:
#      slash-command references.
#   4. If a surviving section's body becomes empty after line-level
#      strip, drop the section heading too.
#   5. Collapse 3+ consecutive blank lines to a single blank line.
#
# API:
#   strip_geniro_tags [--dry-run]
#
# Exit codes:
#   0 — success (stripped N sections or M lines, or dry-run completed)
#   1 — no CLAUDE.md present OR nothing to strip (no-op)
#   2 — IO error

if [ -z "${_SGT_DEPS_LOADED:-}" ]; then
  _sgt_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck disable=SC1091
  source "$_sgt_script_dir/repo-root.sh"
  _SGT_DEPS_LOADED=1
fi

strip_geniro_tags() {
  local dry_run=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=true; shift ;;
      *)
        echo "strip_geniro_tags: unknown flag '$1'" >&2
        return 2
        ;;
    esac
  done

  local root claude_md
  root=$(_geniro_repo_root)
  claude_md="$root/CLAUDE.md"

  if [ ! -f "$claude_md" ] || [ ! -s "$claude_md" ]; then
    echo "strip-geniro-tags: no CLAUDE.md found (nothing to strip)" >&2
    return 1
  fi

  # Cheap idempotency gate: anything to strip?
  if ! grep -qE '^# Geniro Plugin$|^## (Available Skills|Memory Layers|Memory Layers \(M2\)|Custom Agent Invocation|Safety Hooks|Safety Hooks \(Active\)|Optional MCP Dependencies|State Files|Path Rules)$|\$\{CLAUDE_PLUGIN_ROOT\}|geniro-claude-plugin|geniro-claude-harness|/geniro:' "$claude_md" 2>/dev/null; then
    echo "strip-geniro-tags: no plugin doctrine or /geniro: mentions found in CLAUDE.md (no-op)" >&2
    return 1
  fi

  local tmp="${claude_md}.tmp.$$"
  local stats_file="${tmp}.stats"

  awk '
    BEGIN {
      section = ""
      stripped_sections = 0
      stripped_lines = 0
    }

    function flush_section() {
      if (section == "") return

      n = split(section, lines, "\n")
      first = lines[1]

      # Rule 1: drop the entire "# Geniro Plugin" H1 block (heading + body).
      if (first == "# Geniro Plugin") {
        stripped_sections++
        section = ""
        return
      }

      # Rule 2: drop H2 sections matching plugin-doctrine or containing plugin markers.
      is_plugin_section = 0
      if (first ~ /^## (Available Skills|Memory Layers|Memory Layers \(M2\)|Custom Agent Invocation|Safety Hooks|Safety Hooks \(Active\)|Optional MCP Dependencies|State Files|Path Rules)[[:space:]]*$/) {
        is_plugin_section = 1
      } else {
        for (i = 2; i <= n; i++) {
          if (index(lines[i], "${CLAUDE_PLUGIN_ROOT}") > 0 || \
              index(lines[i], "geniro-claude-plugin") > 0 || \
              index(lines[i], "geniro-claude-harness") > 0) {
            is_plugin_section = 1
            break
          }
        }
      }

      if (is_plugin_section) {
        stripped_sections++
        section = ""
        return
      }

      # Otherwise: line-level filter (rule 3).
      # Build cleaned section body; track whether any non-blank, non-heading
      # body content survives.
      cleaned = ""
      body_has_content = 0
      for (i = 1; i <= n; i++) {
        if (i == n && lines[i] == "") continue  # trailing empty from split-by-newline
        if (index(lines[i], "/geniro:") > 0) {
          stripped_lines++
          continue
        }
        cleaned = cleaned lines[i] "\n"
        # Track body content (skip heading line at i==1)
        if (i > 1 && lines[i] !~ /^[[:space:]]*$/) {
          body_has_content = 1
        }
      }

      # Rule 4: drop heading if body became empty (only matters for ## H2 sections).
      if (first ~ /^## / && !body_has_content) {
        stripped_sections++
        section = ""
        return
      }

      printf "%s", cleaned
      section = ""
    }

    /^## / || /^# / {
      flush_section()
      section = $0 "\n"
      next
    }

    {
      section = section $0 "\n"
    }

    END {
      flush_section()
      printf "%d %d", stripped_sections, stripped_lines > "/dev/stderr"
    }
  ' "$claude_md" > "$tmp" 2>"$stats_file" || {
    rm -f "$tmp" "$stats_file"
    echo "strip-geniro-tags: awk failed processing $claude_md" >&2
    return 2
  }

  local stats stripped_sections stripped_lines
  stats=$(cat "$stats_file" 2>/dev/null)
  rm -f "$stats_file"
  stripped_sections="${stats% *}"
  stripped_lines="${stats#* }"

  # Collapse 3+ consecutive blank lines to a single blank line (rule 5).
  awk 'BEGIN{blank=0} /^$/{blank++; if(blank<=1) print; next} {blank=0; print}' "$tmp" > "${tmp}.2" && mv "${tmp}.2" "$tmp"

  if [ "${stripped_sections:-0}" = "0" ] && [ "${stripped_lines:-0}" = "0" ]; then
    rm -f "$tmp"
    echo "strip-geniro-tags: nothing matched strip rules (no-op)" >&2
    return 1
  fi

  if [ "$dry_run" = "true" ]; then
    echo "strip-geniro-tags: would strip ${stripped_sections} plugin section(s) and ${stripped_lines} /geniro: line(s) from CLAUDE.md (dry-run — no changes written)" >&2
    echo "Run without --dry-run to apply." >&2
    rm -f "$tmp"
    return 0
  fi

  mv "$tmp" "$claude_md" || {
    rm -f "$tmp"
    echo "strip-geniro-tags: failed to rename tmp to $claude_md" >&2
    return 2
  }

  echo "strip-geniro-tags: removed ${stripped_sections} plugin section(s) and ${stripped_lines} /geniro: line(s) from CLAUDE.md" >&2
  echo "Project CLAUDE.md now contains only project-specific content. Plugin doctrine is loaded automatically by the plugin itself." >&2
  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0:-}" ]; then
  strip_geniro_tags "$@"
  exit $?
fi
