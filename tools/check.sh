#!/usr/bin/env bash
# Type-check every Luau file. Prints errors only.
# Baseline: 31 "TypeError" lines (nonstrict, forward-declared module functions: known
# noise) and 0 other errors. Anything new means something broke.
#   tools/check.sh [max_lines]
set -uo pipefail
cd "$(dirname "$0")/.."
ROJO="${ROJO:-rojo}"
LSP="${LUAU_LSP:-luau-lsp}"
"$ROJO" sourcemap default.project.json -o sourcemap.json >/dev/null 2>&1
"$LSP" analyze --sourcemap=sourcemap.json --definitions=tools/globalTypes.d.luau --no-strict-dm-types src 2>&1 \
  | grep -E "Error|error" | head -"${1:-60}"
