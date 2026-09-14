#!/usr/bin/env bash
#
# Checks out OpenSpriteKit and its sibling OpenCore* packages into Deps/ so the
# local-path dependencies in OpenSpriteKit's Package.swift (../OpenCoreGraphics,
# etc.) resolve. OpenSpriteKit is NOT consumable as a plain remote SwiftPM
# dependency — it expects its siblings checked out next to it.
#
# Run once from web-spike/:  ./fetch-deps.sh
set -uo pipefail

cd "$(dirname "$0")"
mkdir -p Deps
cd Deps

ORG="https://github.com/1amageek"

# Ordered by the dependency chain. OpenFoundation is the uncertain one — the
# repo search did not surface a standalone repo, only OpenFoundationModels.
# If it 404s, that's a finding: the local-path dep may point at an unpublished
# package and OpenSpriteKit isn't externally buildable yet.
REPOS=(
  OpenSpriteKit
  OpenCoreGraphics
  OpenCoreAnimation
  OpenCoreImage
  OpenImageIO
  OpenFoundation
  swift-webgpu   # OpenCoreGraphics depends on ../swift-webgpu (local path)
)

fail=0
for repo in "${REPOS[@]}"; do
  if [ -d "$repo/.git" ]; then
    echo "== $repo already present, pulling =="
    (cd "$repo" && git pull --ff-only) || echo "!! pull failed for $repo"
  else
    echo "== cloning $repo =="
    if ! git clone --depth 1 "$ORG/$repo.git"; then
      echo "!! FAILED to clone $repo — it may not be a public repo."
      fail=1
    fi
  fi
done

echo
if [ "$fail" -ne 0 ]; then
  echo "One or more repos failed to clone. See notes above — this is exactly the"
  echo "kind of blocker the spike exists to surface. Resolve before building."
  exit 1
fi
echo "All deps checked out under web-spike/Deps/."
