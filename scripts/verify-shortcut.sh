#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
swiftc -parse-as-library Sources/DriveStation/GlobalShortcut.swift Sources/DriveStation/StationTheme.swift \
    Tests/DriveStationTests/ShortcutChecks.swift -o "$scratch/shortcut-checks"
"$scratch/shortcut-checks"
