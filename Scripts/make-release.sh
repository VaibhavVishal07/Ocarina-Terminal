#!/bin/bash
# Builds the universal app and packages it for a GitHub release.
#
#   Scripts/make-release.sh 0.1.0
#
# The zip is made with `ditto`, not `zip`: a .app is a bundle with symlinks and
# an embedded signature, and `zip` flattens enough of that to break the
# signature on the way out.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
ZIP="dist/Ocarina-$VERSION-macOS-universal.zip"

OCARINA_VERSION="$VERSION" Scripts/make-app.sh release universal

echo "==> Verifying the bundle"
lipo -archs "build/Ocarina.app/Contents/MacOS/Ocarina"
codesign --verify --deep --strict "build/Ocarina.app" && echo "signature ok (ad-hoc)"

# The one failure this script exists to prevent. `Bundle.module` falls back to an
# absolute `.build` path baked in at compile time, so an app missing its
# resources runs fine here and dies on the first machine that downloads it.
for required in Ocarina_OcarinaUI SwiftTerm_SwiftTerm; do
  if [ ! -d "build/Ocarina.app/Contents/Resources/$required.bundle" ]; then
    echo "FAIL: $required.bundle is not in Contents/Resources."
    echo "      It would load from .build on this machine and crash on every other one."
    exit 1
  fi
done
echo "resources are inside the app, not borrowed from .build"

echo "==> Packaging $ZIP"
mkdir -p dist
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "build/Ocarina.app" "$ZIP"

echo
echo "$ZIP"
echo "  size   $(du -h "$ZIP" | cut -f1)"
echo "  sha256 $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
