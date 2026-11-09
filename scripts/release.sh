#!/bin/bash
# Publishes a new Hatchling version that every installed copy picks up by itself.
#
#   scripts/release.sh 0.6.0 "O que mudou nesta versão"
#
# 1. Sets the version in Info.plist.
# 2. Builds, signs with the Developer ID and notarizes (build.sh --notarize).
# 3. Creates the GitHub release v<version> on MikaelDDavidd/hatchling with the DMG.
#
# The app checks that repository at launch and every six hours, downloads the DMG of a
# newer release, confirms it is signed by the same developer team and installs it when no
# session is busy. The DMG must be attached to the release: it is what the app looks for.
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version> [notes]}"
NOTES="${2:-Hatchling $VERSION}"
REPO="MikaelDDavidd/hatchling"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must look like 0.6.0" >&2
    exit 1
fi
if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    echo "Release v$VERSION already exists on $REPO" >&2
    exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" Info.plist

./build.sh --notarize

DMG="dist/Hatchling-$VERSION.dmg"
mkdir -p dist
cp .build/release/Hatchling.dmg "$DMG"
spctl -a -t install "$DMG"

gh release create "v$VERSION" "$DMG" --repo "$REPO" --title "Hatchling $VERSION" --notes "$NOTES"
echo "Published v$VERSION. Installed copies update within six hours, or at their next launch."
