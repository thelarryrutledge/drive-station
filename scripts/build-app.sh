#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_args=(-c release)
if [[ -n "${SDKROOT:-}" ]]; then build_args+=(--sdk "$SDKROOT"); fi
swift build "${build_args[@]}"
bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
app="dist/Drive Station.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/DriveStation" "$app/Contents/MacOS/DriveStation"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$app/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app"
printf 'Built: %s/dist/Drive Station.app\n' "$PWD"
