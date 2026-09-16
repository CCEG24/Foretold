#!/usr/bin/env bash
#
# Builds the spike to WASM (WASI reactor) + generates the JS glue, then assembles
# a static ./dist for local serving / Render.
#
# Prereqs (see README):
#   1. Toolchain: install & select Swift 6.4 via swiftly, e.g.
#        swiftly install 6.4 && swiftly use 6.4
#      (swiftly puts the right `swift` on PATH — no TOOLCHAINS/xcrun needed).
#   2. wasm SDK — first-party, from swift.org:
#        swift sdk install https://download.swift.org/swift-6.4.0-release/wasm-sdk/\
#          swift-6.4.0-RELEASE/swift-6.4.0-RELEASE_wasm.artifactbundle.tar.gz \
#          --checksum f07b7be3c586d92d7a07051fc6d303b87ebea67eadc40640ba59d5a8b79aa86d
#   3. ./fetch-deps.sh    (checks out OpenSpriteKit + siblings into Deps/)
#
# Override SWIFT_WASM_SDK via env to force a specific id.
set -euo pipefail
cd "$(dirname "$0")"

# The bundle installs two SDKs (full + Embedded Swift subset), both matching the
# wasm32-unknown-wasip1 triple — pick the full one rather than letting SwiftPM guess.
if [ -z "${SWIFT_WASM_SDK:-}" ]; then
  SWIFT_WASM_SDK="$(swift sdk list 2>/dev/null | grep -i wasm | grep -vi embedded | head -1 | tr -d '[:space:]' || true)"
fi
if [ -z "${SWIFT_WASM_SDK:-}" ]; then
  echo "!! No wasm Swift SDK found — see prereq 2 above." >&2
  exit 1
fi

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
