#!/bin/bash
# Builds Ocarina.app (release) or Kazoo.app (debug).
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
#
# And it is called Kazoo, not "Ocarina Dev". The identifier was already
# separate, but the *name* was not: every list that sorts by name — Privacy &
# Security above all, where Screen Recording, Accessibility and Full Disk
# Access are each granted per app — put "Ocarina" and "Ocarina Dev" next to
# each other as near-identical rows with the same icon, and a grant toggled
# on one of them is impossible to tell from a grant on the other. A test build
# has to be unmistakable in that list at a glance, which means a name that
# shares no prefix with the real one. It is the cheap instrument you keep on
# the desk to check a tune with.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
# native | universal. Universal is for what other people download; a local
# build has no reason to spend twice the time.
ARCHS="${2:-native}"
# The fallback only. `Scripts/make-release.sh <version>` passes the real one
# through `OCARINA_VERSION`, and that script is what the version line is kept
# in — a second copy here is a second thing to forget.
VERSION="${OCARINA_VERSION:-0.1.0}"
# Empty means ad-hoc, which is what a local build wants. Set it to a
# "Developer ID Application: ..." identity — the name `security find-identity
# -v -p codesigning` prints — to produce a build that can be notarised.
#
# Only the release build reads it. Kazoo never leaves this machine, so there is
# no Gatekeeper check for a certificate to satisfy, and signing it for real
# would only spend a timestamp round-trip on every rebuild.
SIGN_IDENTITY="${OCARINA_SIGN_IDENTITY:-}"

if [ "$CONFIG" = "debug" ]; then
  APP_NAME="Kazoo"
  # Not under `com.vaibhavvishal.ocarina.*` either: the designated requirement
  # is now `identifier "<this>"`, and keeping the test build out of the real
  # one's namespace keeps the two requirements from ever being confused for
  # one another by anything matching on a prefix.
  BUNDLE_ID="com.vaibhavvishal.kazoo"
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
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if [ -n "$SIGN_IDENTITY" ] && [ "$CONFIG" != "debug" ]; then
  echo "==> Signing with $SIGN_IDENTITY"
  # Inside-out, and without `--deep`. `--deep` re-signs whatever it finds
  # nested with the flags meant for the outer bundle, which is why the notary
  # service rejects what it produces and why Apple deprecated it.
  #
  # Nothing nested here needs signing today. SwiftPM's resource bundles are
  # flat directories that merely end in `.bundle` — no Contents/, no
  # Info.plist, no Mach-O — and `codesign` refuses them outright with "bundle
  # format unrecognized, invalid, or unsuitable". Correctly: there is no code
  # in them. The app's own signature seals them as ordinary resources.
  #
  # So the loop tests for a binary rather than assuming one, and stays instead
  # of being deleted. A dependency that one day ships a real nested bundle
  # with code in it *must* have it signed before the app, or the notary
  # rejects the submission — and this will sign it rather than leaving a hole
  # that only shows up as a rejection.
  for nested in "$APP"/Contents/Resources/*.bundle; do
    [ -e "$nested" ] || continue
    if find "$nested" -type f -exec file {} + 2>/dev/null | grep -q "Mach-O"; then
      echo "    nested code: $(basename "$nested")"
      codesign --force --timestamp --options runtime \
        --sign "$SIGN_IDENTITY" "$nested"
    fi
  done

  # `--options runtime` is the Hardened Runtime, which notarisation will not
  # proceed without. It does not come between forkpty and the login shell: the
  # child is a separate process with its own signature, and /bin/zsh carries
  # Apple's. `--timestamp` reaches Apple's timestamp server, so this needs the
  # network and fails rather than signing without one — a signature with no
  # trusted timestamp stops verifying the day the certificate expires.
  #
  # No `-r=` on this branch. The override below exists because an ad-hoc
  # signature has no certificate to name, leaving a bare cdhash that changes
  # every build. A Developer ID signature's derived requirement already names
  # the identifier *and* the team, neither of which changes on a rebuild, so
  # the requirement TCC stores keeps matching on its own — and it is the
  # stronger claim, satisfied only by builds signed with this certificate.
  codesign --force --timestamp --options runtime \
    --entitlements Ocarina.entitlements --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose "$APP"
else
  # Ad-hoc sign so macOS treats it as a real app rather than a quarantined blob.
  #
  # The second pass is what stops Screen Recording being asked for on every
  # build. A plain ad-hoc signature has no certificate to name, so the
  # designated requirement macOS derives is a bare `cdhash H"..."` — the hash of
  # this exact binary. TCC stores that requirement when permission is granted,
  # the next build hashes differently, the stored requirement no longer matches,
  # and macOS decides it is looking at an app it has never seen. Hence the
  # prompt, every time, however the app is named.
  #
  # Naming the requirement explicitly pins it to the bundle identifier instead,
  # which does not change between builds, so one grant holds. It is a weaker
  # claim than a certificate would make — anything ad-hoc signed under this
  # identifier satisfies it — but there is no certificate here to make the
  # stronger one, and the alternative is a permission dialog per build.
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  codesign --force --sign - --identifier "$BUNDLE_ID" \
    -r="designated => identifier \"$BUNDLE_ID\"" "$APP" >/dev/null 2>&1 || true
fi
touch "$APP"

echo "==> Built $APP"
