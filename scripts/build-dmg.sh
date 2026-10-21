#!/bin/sh
# Builds "Music Dedup.app", then packages it as build/MusicDedup-<version>.dmg with an
# Applications shortcut so it installs by drag and drop.
set -eu
cd "$(dirname "$0")/.."

./scripts/build-app.sh

VERSION="$(tr -d '[:space:]' < VERSION)"
STAGING=build/dmg
DMG=build/MusicDedup-$VERSION.dmg

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "build/Music Dedup.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# APFS with LZFSE compression, as Sparkle recommends for disk images.
hdiutil create -volname "Music Dedup" -srcfolder "$STAGING" -fs APFS -format ULFO -ov "$DMG"
rm -rf "$STAGING"

echo "Built $DMG"
