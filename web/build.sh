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

# Assert the shipped module carries no DWARF.
#
# PackageToJS *says* "Stripping DWARF debug info..." — but it strips into a
# `.no-dwarf` intermediate and then feeds that to wasm-opt. When wasm-opt is
# missing it only warns, and the final artifact falls back to the UNSTRIPPED
# module, DWARF and all. That shipped an 88 MB wasm for months: the browser
# downloads, parses and holds every byte (Chrome was reloading the tab "for
# using significant memory"), and because dist/ is committed, each rebuild
# pushed another ~85 MB blob into git history.
#
# Package.swift now passes `-Xlinker --strip-debug` for release builds, which
# strips at link time and so can't be undone by that fallback. This check is
# here because the failure mode is silent — the build succeeds and the page
# still works, just enormous. DWARF section names are plain UTF-8 in the wasm's
# custom-section headers, so grep is enough.
#
# Not asserted: the `name` section is deliberately KEPT (it's what gives Swift
# frames readable names in browser stack traces, which the in-progress renderer
# work needs). Swapping `--strip-debug` for `--strip-all` drops it for ~9 MB
# more. Installing binaryen so wasm-opt actually runs is the bigger remaining
# win — PackageToJS warns above when it's absent.
dwarf=""
for section in .debug_info .debug_line .debug_str .debug_abbrev; do
  grep -qa "$section" "$wasm" && dwarf="$dwarf $section"
done
if [ -n "$dwarf" ]; then
  echo "!! $wasm still contains DWARF:$dwarf" >&2
  echo "   The release-only '-Xlinker --strip-debug' in Package.swift did not" >&2
  echo "   take effect, so this artifact is ~25% larger than it needs to be." >&2
  exit 1
fi
bytes="$(wc -c < "$wasm" | tr -d '[:space:]')"
echo "   no DWARF ✓  ($((bytes / 1048576)) MiB)"

# PackageToJS emits the JS module but no html/WASI wiring — supply ours.
cp Web/index.html dist/index.html
cp Web/wasi-shim.js dist/wasi-shim.js

# The sprites. There's no asset catalog in the browser, so the PNGs ship
# beside the wasm, flattened out of their .imageset folders, with a manifest
# naming them — WebArt fetches that list at boot and registers each one under
# the same name the mac build looks up. No art, no manifest, no problem: the
# board falls back to the shapes it always drew.
mkdir -p dist/assets
sprites=""
for imageset in ../Foretold/Assets.xcassets/*.imageset; do
  [ -d "$imageset" ] || continue
  name="$(basename "$imageset" .imageset)"
  [ -f "$imageset/$name.png" ] || continue
  cp "$imageset/$name.png" "dist/assets/$name.png"
  sprites="$sprites\"$name\","
done
printf '[%s]\n' "${sprites%,}" > dist/assets/manifest.json
echo "   sprites: $(ls dist/assets/*.png 2>/dev/null | wc -l | tr -d '[:space:]') copied"

echo
echo "== bundle → ./dist =="
ls -la dist
echo
echo "Serve:  python3 serve.py    # http://localhost:8000 (COOP/COEP + wasm MIME)"
