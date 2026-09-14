#!/usr/bin/env bash
#
# Builds Foretold's web target to WASM + JS glue and assembles ./dist.
#
# Prereqs: swiftly-selected Swift 6.4 snapshot on PATH + the matching wasm SDK
# (same setup as web-spike). Deps are reused from ../web-spike/Deps.
set -euo pipefail
cd "$(dirname "$0")"

# swiftly puts the selected snapshot's `swift` on PATH.
. "${SWIFTLY_HOME_DIR:-$HOME/.swiftly}/env.sh" 2>/dev/null || true

: "${SWIFT_WASM_SDK:=DEVELOPMENT-SNAPSHOT-2026-09-10-a-wasm32-unknown-wasip1}"

echo "== FortoldWeb → WASM =="
echo "   swift: $(swift --version 2>/dev/null | head -1)"
echo "   sdk:   $SWIFT_WASM_SDK"

rm -rf dist && mkdir -p dist

swift package \
  --swift-sdk "$SWIFT_WASM_SDK" \
  --disable-sandbox \
  js \
  -c release \
  --use-cdn \
  --output dist

# PackageToJS emits the JS module but no html/WASI wiring — supply ours.
cp Web/index.html dist/index.html
cp Web/wasi-shim.js dist/wasi-shim.js

echo
echo "== bundle → ./dist =="
ls -la dist
echo
echo "Serve:  python3 serve.py    # http://localhost:8000 (COOP/COEP + wasm MIME)"
