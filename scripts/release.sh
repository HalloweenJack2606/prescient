#!/usr/bin/env bash
# Build Prescient.app (Release) and package it into a distributable .dmg.
#
# Usage:  scripts/release.sh [version]
#   version defaults to the target's MARKETING_VERSION.
#
# Output: dist/Prescient-<version>.dmg  and prints its sha256 for the Homebrew cask.
#
# NOTE: This produces an UNSIGNED (ad-hoc) build. Until the app is signed with a
# Developer ID and notarized, users must install with:  brew install --cask --no-quarantine ...
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="prescient"
APP_NAME="Prescient"
DD="build/dd"
VERSION="${1:-$(xcodebuild -project prescient.xcodeproj -scheme "$SCHEME" -showBuildSettings 2>/dev/null | awk '/ MARKETING_VERSION =/{print $3; exit}')}"

echo "==> Building $APP_NAME $VERSION (Release)"
xcodebuild -project prescient.xcodeproj -scheme "$SCHEME" -configuration Release -destination "generic/platform=macOS" -derivedDataPath "$DD" build >/dev/null

APP="$DD/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "error: $APP not found"; exit 1; }

echo "==> Staging .dmg contents"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
DMG="dist/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"

echo "==> Creating $DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo
echo "==> Done: $DMG"
echo "    version: $VERSION"
echo -n "    sha256:  "; shasum -a 256 "$DMG" | awk '{print $1}'
