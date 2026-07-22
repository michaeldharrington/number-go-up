#!/bin/bash
# Assemble GlobalClick.app from the SPM build product.
# A real .app bundle (vs `swift run`) is required for:
#   - UNUserNotificationCenter (milestone notifications) — crashes without
#     a bundle identifier
#   - LSUIElement — hides the Dock icon
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=GlobalClick.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/GlobalClick "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
# Ad-hoc signature so Keychain access + notifications behave consistently
# across rebuilds.
codesign --force --sign - "$APP"

echo "Built $PWD/$APP — launch with: open $APP"
