#!/usr/bin/env bash
#
# Builds the spike to WASM (WASI reactor) + generates the JS glue, then assembles
# a static ./dist for local serving / Render.
#
# Prereqs (see README):
#   1. Toolchain: install & select a Swift 6.4 dev snapshot via swiftly, e.g.
#        swiftly install main-snapshot-2026-09-10 && swiftly use main-snapshot-2026-09-10
#      (swiftly puts the right `swift` on PATH — no TOOLCHAINS/xcrun needed).
#   2. wasm SDK (must match the snapshot DATE):
#        swift sdk install https://github.com/swiftwasm/swift/releases/download/\
#          swift-wasm-DEVELOPMENT-SNAPSHOT-2026-09-10-a/\
#          swift-wasm-DEVELOPMENT-SNAPSHOT-2026-09-10-a-wasm32-unknown-wasip1.artifactbundle.zip
#        swift sdk list   # copy the exact name it prints into SWIFT_WASM_SDK below
#   3. ./fetch-deps.sh    (checks out OpenSpriteKit + siblings into Deps/)
#
# The SDK name changes per snapshot; override via env if `swift sdk list` differs.
set -euo pipefail
cd "$(dirname "$0")"

: "${SWIFT_WASM_SDK:=DEVELOPMENT-SNAPSHOT-2026-09-10-a-wasm32-unknown-wasip1}"

echo "== HelloScene → WASM =="
echo "   swift:  $(swift --version 2>/dev/null | head -1)"
echo "   sdk:    $SWIFT_WASM_SDK"

rm -rf dist && mkdir -p dist

# JavaScriptKit ships the PackageToJS plugin, which builds the wasm AND emits the
# JS runtime/loader (runtime.mjs + an index.js/app.js harness) in one step. This
# is how a JavaScriptKit app is normally bundled; megaman does the equivalent.
# NOTE(spike): confirm the exact plugin flags for JavaScriptKit 0.50.2 — the `js`
# plugin subcommand and -o flag have shifted across versions.
swift package \
  --swift-sdk "$SWIFT_WASM_SDK" \
  --disable-sandbox \
  js \
  -c release \
  --use-cdn \
  --output dist

# PackageToJS emits a JS module (index.js/instantiate.js/runtime.js) but NO html,
# and does NOT wire WASI. Our page supplies WASI via the vendored shim and calls
# setup(). Copy both into the bundle.
cp Web/index.html dist/index.html
cp Web/wasi-shim.js dist/wasi-shim.js

echo
echo "== generated bundle (dist/) =="
ls -la dist

echo
echo "== done → ./dist =="
echo "Serve locally WITH cross-origin isolation (COOP/COEP) — required for"
echo "SharedArrayBuffer/threads; without it you get a blank page:"
echo
echo "   npx http-server dist -p 8000 -c-1 \\"
echo "     --cors \\"
echo "     -H 'Cross-Origin-Opener-Policy: same-origin' \\"
echo "     -H 'Cross-Origin-Embedder-Policy: require-corp'"
echo
echo "Then open http://localhost:8000 in a WebGPU-capable browser."
