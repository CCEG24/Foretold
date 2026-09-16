#!/usr/bin/env bash
#
# Builds Foretold's web target to WASM + JS glue and assembles ./dist.
#
# Prereqs: swiftly-selected Swift 6.4 release on PATH + the swift.org wasm SDK
# (same setup as web-spike/README.md). Deps are reused from ../web-spike/Deps.
set -euo pipefail
cd "$(dirname "$0")"

# swiftly puts the selected toolchain's `swift` on PATH.
. "${SWIFTLY_HOME_DIR:-$HOME/.swiftly}/env.sh" 2>/dev/null || true

# The 6.4 wasm artifact bundle installs TWO SDKs — the full one and an Embedded
# Swift subset — and both match the wasm32-unknown-wasip1 triple, so SwiftPM
# can't pick on its own (it warns and may choose embedded, which fails oddly).
# Resolve the full one by name rather than hardcoding a version string.
if [ -z "${SWIFT_WASM_SDK:-}" ]; then
  # `|| true` keeps a no-match grep from tripping `set -e`/pipefail before the
  # explicit check below can print something useful.
  SWIFT_WASM_SDK="$(swift sdk list 2>/dev/null | grep -i wasm | grep -vi embedded | head -1 | tr -d '[:space:]' || true)"
fi
if [ -z "${SWIFT_WASM_SDK:-}" ]; then
  echo "!! No wasm Swift SDK found. Install it (see web-spike/README.md):" >&2
  echo "   swift sdk install https://download.swift.org/swift-6.4.0-release/wasm-sdk/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE_wasm.artifactbundle.tar.gz \\" >&2
  echo "     --checksum f07b7be3c586d92d7a07051fc6d303b87ebea67eadc40640ba59d5a8b79aa86d" >&2
  exit 1
fi

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

# Assert the WASI-reactor contract. Package.swift passes `-mexec-model=reactor`
# plus three `--export=` linker flags via .unsafeFlags; index.html calls setup()
# on the instance. If a toolchain or build-system change quietly drops those
# flags the build still SUCCEEDS and the page just renders blank — the classic
# silent failure. Export names live as plain UTF-8 in the wasm export section,
# so grep is enough to catch it at build time instead of in the browser.
wasm="$(ls dist/*.wasm 2>/dev/null | head -1 || true)"
if [ -z "$wasm" ]; then
  echo "!! no .wasm in dist/ — PackageToJS produced no module" >&2
  exit 1
fi
missing=""
for sym in setup getCanvasWidth getCanvasHeight; do
  grep -qa "$sym" "$wasm" || missing="$missing $sym"
done
if [ -n "$missing" ]; then
  echo "!! reactor exports missing from $wasm:$missing" >&2
  echo "   The linker flags in Package.swift did not take effect. If this started" >&2
  echo "   after a toolchain bump, try: swift package --build-system native ... js" >&2
  exit 1
fi
echo "   exports: setup, getCanvasWidth, getCanvasHeight ✓"

# PackageToJS emits the JS module but no html/WASI wiring — supply ours.
cp Web/index.html dist/index.html
cp Web/wasi-shim.js dist/wasi-shim.js

echo
echo "== bundle → ./dist =="
ls -la dist
echo
echo "Serve:  python3 serve.py    # http://localhost:8000 (COOP/COEP + wasm MIME)"
