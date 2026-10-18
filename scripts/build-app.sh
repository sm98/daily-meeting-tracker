#!/bin/bash
# Builds a release binary and packages it as a real .app bundle in
# /Applications so Spotlight can find it and Launch at Login can register it.
set -e
cd "$(dirname "$0")/.."

echo "Building release binary..."
swift build -c release

APP="/Applications/MenuBar Calendar.app"
echo "Installing to $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MenuBarCalendar "$APP/Contents/MacOS/MenuBarCalendar"
cp Packaging/Info.plist "$APP/Contents/Info.plist"

echo "Code signing (ad-hoc)..."
codesign --force --deep -s - "$APP"

echo "Done. Quit any running dev instance, then launch \"MenuBar Calendar\" from Spotlight."
