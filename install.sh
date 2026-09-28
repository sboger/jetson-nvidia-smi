#!/usr/bin/env bash
#
# Install the numpy-smi shim onto a Jetson board as /usr/bin/nvidia-smi.
# Safe to re-run (backs up any existing binary to nvidia-smi.orig.bak).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nvidia-smi"
DEST="/usr/bin/nvidia-smi"

if [[ ! -f "$SRC" ]]; then
  echo "error: $SRC not found (run this from the repo root)" >&2
  exit 1
fi

if [[ -e "$DEST" ]] && [[ ! -e "$DEST.orig.bak" ]]; then
  cp -a "$DEST" "$DEST.orig.bak"
  echo "backed up existing $DEST -> $DEST.orig.bak"
fi

install -m 0755 "$SRC" "$DEST"
echo "installed $SRC -> $DEST"

# Smoke test against the exact query SparkDash uses.
echo "--- smoke test ---"
"$DEST" --query-gpu=temperature.gpu,utilization.gpu,power.draw,power.limit,clocks.current.sm,clocks.max.sm --format=csv,noheader,nounits
echo "ok"
