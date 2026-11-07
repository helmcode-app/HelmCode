#!/usr/bin/env bash
# Rebuild Features/Editor/Terminal/terminal.bundle.js from terminal-entry.mjs
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/HelmCode/Features/Editor/Terminal"
ENTRY="$OUT_DIR/terminal-entry.mjs"
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
  @xterm/xterm@5.5.0 \
  @xterm/addon-fit@0.10.0 \
  @xterm/addon-web-links@0.11.0 \
  @xterm/addon-search@0.15.0 \
  --silent
npm install -D esbuild --silent

cp "$ENTRY" ./terminal-core.mjs
cat > entry-shim.mjs <<'EOF'
import xtermCss from "@xterm/xterm/css/xterm.css";
const style = document.createElement("style");
style.textContent = xtermCss;
document.head.appendChild(style);
import "./terminal-core.mjs";
EOF

npx esbuild entry-shim.mjs \
  --bundle \
  --format=iife \
  --outfile=terminal.bundle.js \
  --loader:.css=text \
  --minify

cp terminal.bundle.js "$OUT_DIR/terminal.bundle.js"
echo "Wrote $OUT_DIR/terminal.bundle.js ($(wc -c < "$OUT_DIR/terminal.bundle.js") bytes)"
