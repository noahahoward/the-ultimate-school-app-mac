#!/bin/bash
# Builds Locker for release and packages it the way the in-app updater expects:
# a zip containing Locker.app, attached to a GitHub release tagged v<version>.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION=$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' project.yml)
fi

echo "==> Locker $VERSION"

command -v xcodegen >/dev/null || { echo "xcodegen not found (brew install xcodegen)"; exit 1; }
xcodegen generate

echo "==> Testing"
xcodebuild -project Locker.xcodeproj -scheme Locker -configuration Debug \
  -destination 'platform=macOS' test | grep -E "Executed .* tests, with" | tail -1

echo "==> Building"
rm -rf "$BUILD"
mkdir -p "$BUILD"
xcodebuild -project Locker.xcodeproj -scheme Locker -configuration Release \
  -derivedDataPath "$BUILD/dd" \
  MARKETING_VERSION="$VERSION" \
  -destination 'platform=macOS' build > "$BUILD/build.log"

APP="$BUILD/dd/Build/Products/Release/Locker.app"
[ -d "$APP" ] || { echo "build produced no app; see $BUILD/build.log"; exit 1; }

cp -R "$APP" "$BUILD/Locker.app"

# Ad-hoc signature: enough for the app to run locally. Replace "-" with a
# Developer ID identity to ship something Gatekeeper won't warn about.
codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" "$BUILD/Locker.app"
codesign --verify --deep --strict "$BUILD/Locker.app" && echo "==> Signature OK"

ZIP="$BUILD/Locker-$VERSION.zip"
( cd "$BUILD" && ditto -c -k --keepParent --sequesterRsrc Locker.app "$ZIP" )

# Keep Spotlight out of the build folder. Without this, every build leaves
# another launchable "Locker" for Spotlight to find, and opening the wrong one
# looks exactly like the app having broken.
touch "$BUILD/.metadata_never_index"
rm -rf "$BUILD/dd"

echo
echo "==> Done"
echo "    App: $BUILD/Locker.app  (staging copy — install from here)"
echo "    Zip: $ZIP"
echo
echo "To publish an update students can install from inside the app:"
echo "    gh release create v$VERSION \"$ZIP\" --title \"Locker $VERSION\" --notes \"What changed\""
