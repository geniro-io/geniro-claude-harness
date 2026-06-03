#!/usr/bin/env bash
# Portable SHA-256 helper.
#
# Stock macOS ships `shasum` (Perl-based, always present) but NOT `sha256sum`
# (that arrives only with GNU coreutils). Linux ships `sha256sum`. A bare
# `sha256sum` therefore fails on a default macOS host — and because callers
# pipe through `2>/dev/null` it fails SILENTLY, yielding an empty digest that
# downstream code mistakes for a real hash (false drift / false checksum
# mismatch). Route every hash through this helper instead.
#
# Both tools emit the same `<hex>  <name>` line, so existing extraction
# (`awk '{print $1}'`, `cut -c1-12`, `cut -d' ' -f1`, `head -c N`) is unchanged.
#
# Usage — both stdin and file-argument forms work:
#   printf '%s' "$x" | _geniro_sha256
#   _geniro_sha256 "$file"

_geniro_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}
