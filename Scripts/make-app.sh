#!/bin/bash
# Builds Ocarina.app (release) or "Ocarina Test Build.app" (debug).
#
# A bare SwiftPM executable has no bundle, so macOS has nowhere to read an icon
# from and the Dock falls back to the generic Unix-executable picture.
# `applicationIconImage` is the only lever without a bundle, and it does not
# reach Finder, ⌘-Tab or Get Info. This assembles a real .app instead.
#
# The debug build is a *separate app*, not the same one rebuilt: its own name,
# its own bundle identifier, its own executable name. Sharing any of the three
# meant Launch Services, the Dock and ⌘-Tab could not tell a test build from
# the installed one — and `open -a Ocarina` could hand back either.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
# native | universal. Universal is for what other people download; a local
# build has no reason to spend twice the time.
ARCHS="${2:-native}"
VERSION="${OCARINA_VERSION:-0.1.0}"

if [ "$CONFIG" = "debug" ]; then
  APP_NAME="Ocarina Test Build"
  BUNDLE_ID="com.vaibhavvishal.ocarina.test"
else
  APP_NAME="Ocarina"
  BUNDLE_ID="com.vaibhavvishal.ocarina"
fi

APP="build/$APP_NAME.app"
ICON_SRC="Icons/AppIcon.png"

echo "==> Building ($CONFIG, $ARCHS)"
if [ "$ARCHS" = "universal" ]; then
  # Not `--arch arm64 --arch x86_64`: that switches SwiftPM to the Xcode build
  # system, which cannot resolve SwiftTerm's build-tool plugin and fails with
  # "missing target ... SwiftTermBuildInfoPlugin". Two single-arch builds and a
  # lipo produce the same file without going near it.
  swift build -c "$CONFIG" --triple arm64-apple-macosx >/dev/null
  swift build -c "$CONFIG" --triple x86_64-apple-macosx >/dev/null
  PRODUCTS=".build/arm64-apple-macosx/$CONFIG"
  BIN="$(mktemp -d)/Ocarina"
  lipo -create "$PRODUCTS/Ocarina" ".build/x86_64-apple-macosx/$CONFIG/Ocarina" \
    -output "$BIN"
else
  swift build -c "$CONFIG" >/dev/null
  # The explicit triple, not `.build/$CONFIG`: that is a symlink to whichever
  # architecture was built last, so a preceding cross-compile would otherwise
  # be packaged as if it were this machine's.
  PRODUCTS=".build/$(uname -m)-apple-macosx/$CONFIG"
  BIN="$PRODUCTS/Ocarina"
fi
[ -x "$BIN" ] || { echo "no binary at $BIN"; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# The executable carries the app's name too, so Activity Monitor, `pgrep` and
# `pmset -g assertions` name which of the two is running.
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# Contents/Resources, where `codesign` can seal them; `PackagedResources` is
# what finds them there. See its comment for why `Bundle.module` cannot.
for b in "$PRODUCTS"/*.bundle; do
  [ -e "$b" ] || continue
  cp -R "$b" "$APP/Contents/Resources/"
done

echo "==> Icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
  sips -z $((size * 2)) $((size * 2)) "$ICON_SRC" \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS treats it as a real app rather than a quarantined blob.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
touch "$APP"

echo "==> Built $APP"
