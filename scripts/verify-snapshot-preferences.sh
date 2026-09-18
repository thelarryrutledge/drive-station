#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
swiftc -parse-as-library Sources/DriveStation/DriveService.swift Sources/DriveStation/DriveSnapshot.swift \
    Sources/DriveStation/FileExplorer.swift Sources/DriveStation/PinnedLocations.swift Sources/DriveStation/StationTheme.swift \
    Tests/DriveStationTests/SnapshotPreferenceChecks.swift -o "$scratch/snapshot-preference-checks"
DRIVE_STATION_SNAPSHOT_CACHE="$scratch/snapshots" "$scratch/snapshot-preference-checks"
