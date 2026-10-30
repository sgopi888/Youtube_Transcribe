#!/bin/bash
# One-time setup for the "Best quality" Roformer engine: a private Python venv + audio-separator.
# Installs into ~/Library/Application Support/YTScribe/roformer. Needs internet; Apple Silicon only.
set -euo pipefail
ROOT="$HOME/Library/Application Support/YTScribe/roformer"
PY=""
for c in /opt/homebrew/bin/python3.11 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.13 /usr/local/bin/python3.11; do
  [ -x "$c" ] && PY="$c" && break
done
[ -n "$PY" ] || { echo "No Homebrew Python 3.11-3.13 found. Run: brew install python@3.11" >&2; exit 1; }
mkdir -p "$ROOT/models"
[ -d "$ROOT/venv" ] || "$PY" -m venv "$ROOT/venv"
"$ROOT/venv/bin/pip" install --upgrade pip >/dev/null
"$ROOT/venv/bin/pip" install "audio-separator[cpu]"
"$ROOT/venv/bin/audio-separator" --version
echo "ROFORMER_SETUP_OK"
