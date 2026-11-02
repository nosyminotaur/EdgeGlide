#!/usr/bin/env bash
# Builds a release binary and wraps it in build/EdgeGlide.app, ad-hoc signed.
#
# Optional environment variables, stamped into Info.plist before signing:
#   EDGEGLIDE_VERSION  CFBundleShortVersionString, for example 0.1.0
#   EDGEGLIDE_BUILD    CFBundleVersion, for example 42
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
if [[ -n "${EDGEGLIDE_VERSION:-}" ]]; then
  plutil -replace CFBundleShortVersionString -string "$EDGEGLIDE_VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${EDGEGLIDE_BUILD:-}" ]]; then
  plutil -replace CFBundleVersion -string "$EDGEGLIDE_BUILD" "$APP/Contents/Info.plist"
fi
plutil -lint "$APP/Contents/Info.plist"

echo "==> Ad-hoc signing"
codesign --force --deep -s - "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Built $ROOT/$APP"
