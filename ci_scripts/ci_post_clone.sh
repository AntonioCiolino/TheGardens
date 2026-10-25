#!/bin/sh
set -euo pipefail

# Xcode Cloud runs this after cloning. Resolve the local GardensCore package
# from the repo root (project lives in Gardens/).

echo "ci_post_clone: resolving Swift packages for Gardens…"

cd "$CI_PRIMARY_REPOSITORY_PATH/Gardens"

xcodebuild -resolvePackageDependencies \
  -project Gardens.xcodeproj \
  -scheme Gardens

echo "ci_post_clone: done."
