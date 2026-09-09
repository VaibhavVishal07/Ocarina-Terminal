#!/bin/bash
# Builds the universal app and packages it for a GitHub release.
#
#   Scripts/make-release.sh 0.1.0
#
# Unset, the two variables below produce the same ad-hoc build as before, which
# Gatekeeper will refuse on any machine but this one — fine for a build you
# hand to someone who will run `xattr -d com.apple.quarantine`, not for a
# release page. Set both to ship something that opens on a double-click:
#
#   OCARINA_SIGN_IDENTITY="Developer ID Application: NAME (TEAMID)" \
#   OCARINA_NOTARY_PROFILE=ocarina-notary Scripts/make-release.sh 0.1.0
#
# The profile is a keychain item holding the App Store Connect credentials,
# made once with:
#
#   xcrun notarytool store-credentials ocarina-notary \
#     --apple-id ADDRESS --team-id TEAMID --password APP-SPECIFIC-PASSWORD
#
# The zip is made with `ditto`, not `zip`: a .app is a bundle with symlinks and
# an embedded signature, and `zip` flattens enough of that to break the
# signature on the way out.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
ZIP="dist/Ocarina-$VERSION-macOS-universal.zip"
SIGN_IDENTITY="${OCARINA_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${OCARINA_NOTARY_PROFILE:-}"

# Checked here rather than after the build: notarisation is a service that only
# accepts a Developer ID signature, so the two go together, and finding that
# out at the end costs the universal build twice over.
if [ -n "$NOTARY_PROFILE" ] && [ -z "$SIGN_IDENTITY" ]; then
  echo "OCARINA_NOTARY_PROFILE is set but OCARINA_SIGN_IDENTITY is not."
  echo "The notary service rejects an ad-hoc signature; there is nothing to submit."
  exit 1
fi

OCARINA_VERSION="$VERSION" Scripts/make-app.sh release universal

echo "==> Verifying the bundle"
lipo -archs "build/Ocarina.app/Contents/MacOS/Ocarina"
codesign --verify --deep --strict "build/Ocarina.app"
if [ -n "$SIGN_IDENTITY" ]; then
  echo "signature ok ($SIGN_IDENTITY)"
else
  echo "signature ok (ad-hoc — Gatekeeper will refuse this on other machines)"
fi

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

if [ -n "$NOTARY_PROFILE" ]; then
  echo "==> Notarising (a few minutes; Apple's queue decides how many)"
  # A throwaway zip, not the one in dist/. Notarisation returns a ticket that
  # `stapler` writes *into the bundle*, so the archive that ships has to be
  # built after this step and not before — otherwise the download carries no
  # ticket and every machine that opens it has to ask Apple over the network,
  # which is exactly what stapling exists to avoid.
  SUBMISSION="$(mktemp -d)/Ocarina.zip"
  ditto -c -k --sequesterRsrc --keepParent "build/Ocarina.app" "$SUBMISSION"
  # The status is read out of the output rather than taken from the exit code:
  # `--wait` has returned 0 on submissions it rejected. And the log is fetched
  # here, because a rejection names its reasons only in that log — otherwise
  # this fails with "not accepted" and the one command that would say why is
  # left for someone to remember.
  SUBMIT_LOG="$(mktemp)"
  xcrun notarytool submit "$SUBMISSION" \
    --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee "$SUBMIT_LOG" || true
  if ! grep -q "status: Accepted" "$SUBMIT_LOG"; then
    echo
    echo "FAIL: Apple did not accept the build."
    SUBMISSION_ID="$(awk '/^ *id: /{print $2; exit}' "$SUBMIT_LOG")"
    if [ -n "$SUBMISSION_ID" ]; then
      xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE"
    fi
    exit 1
  fi

  xcrun stapler staple "build/Ocarina.app"

  # What a machine that has never seen this app will decide about it. Anything
  # but `source=Notarized Developer ID` means the download will be refused.
  echo "==> Gatekeeper"
  spctl -a -vvv -t exec "build/Ocarina.app"
fi

echo "==> Packaging $ZIP"
mkdir -p dist
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "build/Ocarina.app" "$ZIP"

# The same bytes under a name with no version in them.
#
# The site's Download button has to be a URL that never goes stale, and
# GitHub only offers one: /releases/latest/download/<asset>. It resolves to
# whichever release is newest, but the asset name has to be identical in every
# release for that to work, and the versioned name is not. So both go up: the
# versioned one is what a person picks off the releases page and finds in
# their Downloads folder six months later, and this one is what the button
# points at.
STABLE="dist/Ocarina-macOS-universal.zip"
cp "$ZIP" "$STABLE"

echo
echo "$ZIP"
echo "  size   $(du -h "$ZIP" | cut -f1)"
echo "  sha256 $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo
echo "Upload BOTH, or the site's Download button keeps serving the old build:"
echo "  gh release create v$VERSION $ZIP $STABLE --title \"Ocarina $VERSION\" --notes ..."
