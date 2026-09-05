#!/bin/bash
# Builds Ocarina.app.
#
# A bare SwiftPM executable has no bundle, so macOS has nowhere to read an icon
# from and the Dock falls back to the generic Unix-executable picture.
# `applicationIconImage` is the only lever without a bundle, and it does not
# reach Finder, ⌘-Tab or Get Info. This assembles a real .app instead.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Ocarina.app"
ICON_SRC="Icons/AppIcon.png"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" >/dev/null

BIN=".build/$CONFIG/Ocarina"
[ -x "$BIN" ] || { echo "no binary at $BIN"; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ocarina"

# Bundle.module looks beside the executable and in Contents/Resources.
for b in .build/"$CONFIG"/*.bundle; do
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

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Ocarina</string>
  <key>CFBundleDisplayName</key><string>Ocarina</string>
  <key>CFBundleIdentifier</key><string>com.vaibhavvishal.ocarina</string>
  <key>CFBundleExecutable</key><string>Ocarina</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
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
