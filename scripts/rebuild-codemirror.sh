#!/usr/bin/env bash
# Rebuild Features/Editor/CodeMirror/editor.bundle.js from the CM6 entry source.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/HelmCode/Features/Editor/CodeMirror"
ENTRY="$OUT_DIR/editor-entry.mjs"
WORK="$(mktemp -d)"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if [[ ! -f "$ENTRY" ]]; then
  echo "Missing entry: $ENTRY" >&2
  exit 1
fi

cd "$WORK"
npm init -y >/dev/null
npm install \
  codemirror \
  @codemirror/lang-javascript \
  @codemirror/lang-json \
  @codemirror/lang-markdown \
  @codemirror/lang-cpp \
  @codemirror/language \
  @codemirror/legacy-modes \
  @codemirror/theme-one-dark \
  @codemirror/view \
  @codemirror/state \
  @codemirror/commands \
  @codemirror/autocomplete \
  @codemirror/search \
  @codemirror/lint \
  --silent
npm install -D esbuild --silent

cp "$ENTRY" ./editor-entry.mjs
npx esbuild editor-entry.mjs --bundle --format=iife --outfile=editor.bundle.js --minify
cp editor.bundle.js "$OUT_DIR/editor.bundle.js"
echo "Wrote $OUT_DIR/editor.bundle.js ($(wc -c < "$OUT_DIR/editor.bundle.js") bytes)"
