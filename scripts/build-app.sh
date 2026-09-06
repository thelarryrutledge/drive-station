#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app="dist/Drive Station.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/DriveStation "$app/Contents/MacOS/DriveStation"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$app/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app"
printf 'Built: %s/dist/Drive Station.app\n' "$PWD"
