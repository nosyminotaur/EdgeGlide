#!/usr/bin/env bash
# Builds a versioned, ad-hoc signed release zip of EdgeGlide.
#
# Usage: scripts/release.sh [version]
# Without a version, it uses CFBundleShortVersionString from Resources/Info.plist.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "error: version '$VERSION' is not like 1.2 or 1.2.3" >&2
  exit 1
fi
# CFBundleVersion: the commit count when this is a git checkout, else 1.
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

APP="build/EdgeGlide.app"
ZIP="build/EdgeGlide-$VERSION.zip"

# build-app.sh stamps the version into Info.plist before it signs, so the
# signature covers the final Info.plist.
EDGEGLIDE_VERSION="$VERSION" EDGEGLIDE_BUILD="$BUILD" scripts/build-app.sh

STAMPED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [[ "$STAMPED" != "$VERSION" ]]; then
  echo "error: bundle says $STAMPED, expected $VERSION" >&2
  exit 1
fi
codesign --verify --strict "$APP"

echo "==> Zipping $ZIP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Version $VERSION (build $BUILD)"
echo "==> $ROOT/$ZIP"
shasum -a 256 "$ZIP"
