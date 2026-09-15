#!/usr/bin/env bash
#
# Checks out OpenSpriteKit and its sibling OpenCore*/swift-webgpu packages into
# Deps/ so OpenSpriteKit's local-path dependencies (../OpenCoreGraphics, etc.)
# resolve, PINS each to the exact commit we validated against, and applies our
# local patches (../web/patches/*.patch) that fix OpenSpriteKit rendering bugs.
#
# Pinning + patching is what makes CI reproducible: a plain `git clone` of moving
# `main` would (a) drift and (b) drop our fixes, producing a broken build.
#
# Run from web-spike/:  ./fetch-deps.sh
set -uo pipefail

cd "$(dirname "$0")"
PATCH_DIR="$(cd .. && pwd)/web/patches"
mkdir -p Deps
cd Deps

ORG="https://github.com/1amageek"

# "repo pinned-sha" — SHAs recorded 2026-09-14 (the tree our patches target).
REPOS=(
  "OpenSpriteKit     635015a3d37ec93748c352b93d88c771333621e2"
  "OpenCoreGraphics  bf9c4bab8d48cb940602c52c0567e62cb4f44e70"
  "OpenCoreAnimation e0205a13d4b6bf952f961cc9608bcce38aaedeb8"
  "OpenCoreImage     359a440251dc35f5ed0c5112e16b20cfcdc8da56"
  "OpenImageIO       ec4ba375a37b6204afc0003ba679a4adcabd30d4"
  "OpenFoundation    70514cd296acd7832e04d10bfb48a728cb57e6c3"
  "swift-webgpu      4242a88e96ca811cccbc54d4e82564461cd4524a"
)

fail=0
for entry in "${REPOS[@]}"; do
  # shellcheck disable=SC2086
  set -- $entry
  repo="$1"; sha="$2"

  if [ ! -d "$repo/.git" ]; then
    echo "== cloning $repo =="
    git clone --filter=blob:none "$ORG/$repo.git" || { echo "!! clone failed: $repo"; fail=1; continue; }
  fi

  echo "== $repo → $sha =="
  git -C "$repo" fetch --quiet --filter=blob:none origin "$sha" 2>/dev/null || git -C "$repo" fetch --quiet origin || true
  # Reset hard to the pinned commit — also discards any previously-applied patch,
  # so re-running is idempotent.
  if ! git -C "$repo" reset --hard --quiet "$sha"; then
    echo "!! could not check out pinned $sha for $repo"; fail=1; continue
  fi

  patch="$PATCH_DIR/$repo.patch"
  if [ -f "$patch" ]; then
    if git -C "$repo" apply --check "$patch" 2>/dev/null; then
      git -C "$repo" apply "$patch" && echo "   applied patch: $repo.patch"
    else
      echo "!! patch does not apply cleanly to pinned $repo ($patch) — did upstream move? Re-capture the patch."
      fail=1
    fi
  fi
done

echo
if [ "$fail" -ne 0 ]; then
  echo "One or more deps failed to fetch/pin/patch. Resolve before building."
  exit 1
fi
echo "All deps pinned + patched under web-spike/Deps/."
