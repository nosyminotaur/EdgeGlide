#!/usr/bin/env bash
# Builds a release binary and wraps it in build/EdgeGlide.app, ad-hoc signed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="build/EdgeGlide.app"

echo "==> swift build -c release"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/EdgeGlide" "$APP/Contents/MacOS/EdgeGlide"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

echo "==> Ad-hoc signing"
codesign --force --deep -s - "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Built $ROOT/$APP"
