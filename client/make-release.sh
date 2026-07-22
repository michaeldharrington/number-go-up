#!/bin/bash
# Build a signed, notarized, downloadable GlobalClick.zip in client/dist/.
#
# One-time setup (requires an Apple Developer account):
#   1. In Xcode (Settings → Accounts → Manage Certificates) or at
#      developer.apple.com, create a "Developer ID Application" certificate.
#      Find its name with:  security find-identity -v -p codesigning
#   2. Store notarization credentials once (app-specific password from
#      appleid.apple.com, team ID from developer.apple.com/account):
#      xcrun notarytool store-credentials globalclick \
#        --apple-id you@example.com --team-id TEAMID1234
#
# Then:  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID1234)" ./make-release.sh
set -euo pipefail
cd "$(dirname "$0")"

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your 'Developer ID Application: ...' certificate name}"
NOTARY_PROFILE="${NOTARY_PROFILE:-globalclick}"

swift build -c release --arch arm64 --arch x86_64   # universal binary

APP=GlobalClick.app
rm -rf "$APP" dist
mkdir -p "$APP/Contents/MacOS" dist
cp .build/apple/Products/Release/GlobalClick "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

# Hardened runtime is required for notarization. No entitlements needed —
# the app only uses URLSession, Keychain, and user notifications.
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"

# ditto (not zip) preserves the bundle metadata notarization expects.
ditto -c -k --keepParent "$APP" dist/GlobalClick.zip
xcrun notarytool submit dist/GlobalClick.zip --keychain-profile "$NOTARY_PROFILE" --wait

# Staple the ticket so Gatekeeper works offline, then re-zip the stapled app.
xcrun stapler staple "$APP"
ditto -c -k --keepParent "$APP" dist/GlobalClick.zip

echo "Notarized build ready: $PWD/dist/GlobalClick.zip"
