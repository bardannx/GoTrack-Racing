#!/usr/bin/env bash
# Build the Roblox place (src/ + assets/) with Rojo.
#   tools/build.sh                 -> GoTrackRacing.rbxlx (the file Studio opens)
#   tools/build.sh out.rbxlx       -> somewhere else
# CLOSE THE PLACE IN STUDIO FIRST: Studio auto-saves on close and would overwrite this build.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-GoTrackRacing.rbxlx}"
ROJO="${ROJO:-rojo}"
"$ROJO" build default.project.json -o "$OUT"
ls -la "$OUT"
