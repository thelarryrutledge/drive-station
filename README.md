# Drive Station

A native macOS storage command deck: orbital drive map, volume telemetry, a persistent drive registry, a built-in file explorer, and a menu bar shortcut. Built with SwiftUI and AppKit; no third-party dependencies, server, or network access.

## Launch

Open `dist/Drive Station.app`. Drag it into Applications if you'd like, then keep it in the Dock. The menu bar drive icon also opens the command deck and exposes volume controls.

To rebuild (macOS 14+ and Xcode command line tools):

```sh
bash scripts/build-app.sh
open "dist/Drive Station.app"
```

If the selected macOS 27 command-line SDK reports a missing `SwiftUIMacros` plugin, build with an installed macOS 26 SDK, for example `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk bash scripts/build-app.sh`. The verification scripts also honor `SDKROOT`. The XCTest suite requires full Xcode; command-line tools alone can run the standalone checks below.

## Use

- **Appearance:** use the sun/moon button in either window header, or choose Light/Dark in Station Settings. The selection is saved and applies to the dashboard and explorer. Pinned locations use only the height of their rows, scrolling when the list grows long.
- **Menu bar panel:** click the menu bar drive icon for a compact dashboard with a connection summary, drive search, capacity bars, and online/standby/offline badges. Explore or wake a drive, eject it, and browse an offline snapshot directly from its card. The ellipsis keeps Finder, Standby, and snapshot preferences close by. Scan status, capture progress, cancellation, and errors appear in the panel; its sun/moon control shares the app appearance.
- **Menu bar and login:** close or use **Hide to Menu Bar** to leave Drive Station running from its drive icon in the macOS menu bar. Station Settings can launch the app directly into that menu bar and register it as a login item; choose **Open command deck** from the menu-bar icon whenever you need the dashboard.
- **Global shortcut / ⌃⌥D:** press Control–Option–D from any app to open the command deck while Drive Station is running, even after closing its window. In **Station Settings → Global keyboard shortcut**, choose **Change…** and press a new combination containing Control or Command (Option and Shift are optional). Escape cancels recording. You can disable the shortcut or reset it to the default. Changes persist across launches; if macOS refuses a replacement, the previous shortcut stays active and the setting shows an error.
- **Snapshot Library:** browse a saved catalog and cached media thumbnails even while the source drive is offline or on standby. The first snapshot of a mounted external volume without a capture is automatic when Scan Drives discovers it (disable this in Station Settings). Capture runs in the background, so the source volume remains available to Explore and Finder; its Standby control and all Eject controls stay unavailable until the capture finishes. Later refreshes are manual, via the volume options menu. The internal volume offers an explicit **Capture Home Folder Snapshot**, scoped to Home rather than all system files.
- **Snapshot Explorer:** switch between thumbnail grid and list, navigate saved folders, and search filenames/paths across the entire snapshot (first 500 matches). The capture timestamp, scope, item count, thumbnail count, and any partial-coverage warning are always shown. Opening a saved file displays a reconnect reminder; snapshot browsing never mounts or accesses the original drive.
- **Do not snapshot:** enable this in a drive's ellipsis, right-click, or menu-bar menu to exclude an SD card (such as EOS_DIGITAL) or any other volume from automatic and manual captures. Any capture in progress for that drive is cancelled; existing saved snapshots remain browsable. The drive card shows **Snapshots off**. This preference is saved by volume UUID across scans, renames, reconnects, and app restarts. Turn it off to allow captures again; the next scan can automatically capture an eligible drive without a saved snapshot. Reformatting a card can give it a new UUID, requiring the preference to be set again.
- **Scan Drives / ⌘R:** discover the internal startup volume plus external and removable filesystem volumes (including cards in built-in readers), updating capacity and mount status. Scan after connecting or disconnecting a drive. Internal startup storage appears once, rather than exposing macOS helper partitions.
- **Orbital map:** single-click a drive node to select it, right-click it for **Explore in Drive Station**, **Open in Finder**, **Eject**, or **Browse Saved Snapshot**, and double-click to open it. Choose the double-click action in Station Settings.
- **Standby / moon button:** safely unmount that volume. A busy-volume refusal is displayed; the app never forces an unmount.
- **Eject:** safely take an external or removable disk offline, including its other volumes. Available for online and standby drives from the right-click, volume options, and menu-bar menus. The registry remembers ejected drives and saved snapshots remain viewable; reconnect to access original files. Eject is unavailable during snapshot capture and never forces a busy disk to disconnect.
- **Explore / Wake & Explore:** open the built-in explorer, mounting an external volume first if needed. Navigate folders with double-click, breadcrumbs, back/forward, or the up button. Search filters the current folder; the options menu changes sorting and hidden-file visibility. Internal storage also has Home and Applications shortcuts.
- **Volume options / ellipsis menu:** Explore, Open in Finder, saved snapshots, Standby (external online volumes only), or Eject (connected external/removable volumes). These actions are also in the menu bar shortcut.
- **Explorer file options:** double-click a file to open its default app, or select it and use Open File / Reveal in Finder. Packages open in their app; symbolic links are revealed in Finder. The explorer offers no delete, move, or rename operations. Permission and disconnection errors offer retry and Finder access. Simulation browsing uses sample files only.
- **Pinned locations:** right-click a folder, breadcrumb, or regular location and choose Pin Location. Pins appear above the sidebar's separator. Drag a pin onto another pin to move it to that position; right-click and choose Remove Pin to remove the shortcut. Pins start empty and are saved per volume in `Application Support/DriveStation/pins.json`, using relative paths so remounted volumes still work. Simulation pins are held separately in memory. Renamed or deleted folders show the explorer's normal unavailable-folder error when opened.
- **Drive registry:** remembers disconnected volumes by UUID, including last-known capacity. The minus button forgets an offline record without touching files.
- **Simulation:** try a sample fleet from Station Settings or the empty-state button. Its commands never reach diskutil or Finder.
- **Activity log:** the most recent 100 events from this session.

Drive Station scans at launch, on an explicit scan, after a volume operation, and when returning from simulation. It does not repeatedly poll disks. Snapshot captures perform a bounded recursive inventory only when triggered as described above. Saved registry data lives at `~/Library/Application Support/DriveStation/registry.json`.

Snapshot catalogs and JPEG thumbnails live in `~/Library/Application Support/DriveStation/Snapshots/`. Captures read visible local items, exclude package contents and symlink traversal, and avoid crossing onto other mounted volumes. Cloud-managed items are cataloged as links and are not downloaded or thumbnailed. Each capture is limited to 100,000 items or two minutes of indexing, then up to 300 thumbnail attempts or 90 seconds of thumbnail generation. Photos are downsampled; macOS Quick Look supplies supported video and PDF previews. Missing or unsupported thumbnails use file-type icons. Partial catalogs and thumbnail limits are labeled. Cancel from the capture banner; the previous completed snapshot remains usable. Refreshes commit atomically and keep one previous generation as a recovery copy. Snapshots are a dated inventory, not backups of the original files, and are not guaranteed to represent one atomic filesystem instant.

## What standby and eject do

Standby is a regular macOS volume unmount. It makes the filesystem unavailable to ordinary file access until mounted again. It is not a hardware spin-down guarantee, and other volumes on the same physical disk may remain active. Reconnection, reboot, or another app can mount it again. The app does not alter Spotlight, power settings, `/etc/fstab`, or global automatic mounting behavior. Performance improvement depends on actual background disk activity.

Eject asks macOS to safely unmount the disk’s volumes and take the media offline. Saved snapshot catalogs and thumbnails stay on this Mac and remain browsable after ejection.

Mount/unmount/eject controls only accept external or removable filesystem volumes with a stable volume UUID. This includes removable media that macOS reports through an internal controller, such as a built-in SD-card reader. Internal startup storage supports browsing and Finder access only; it cannot be put on standby or ejected. Its APFS volume group ID keeps its identity stable across startup snapshots. Whole devices and fixed internal/helper volumes are excluded. Volume identity and removable/external status are checked again immediately before disk commands. Encrypted volumes may need to be unlocked in Disk Utility. Network shares and volumes without UUIDs are not managed. APFS capacity/free space reflects the shared container, so it should not be summed across volumes.

The app is locally ad-hoc signed, suitable for this Mac. Distribution to other Macs would require Developer ID signing and notarization.

## Verification

```sh
swift test
```

For shortcut checks that also run with command-line tools alone (without XCTest), use `bash scripts/verify-shortcut.sh`. These check saved preferences, failed replacements, cancellation, and real macOS hotkey registration and release using temporary uncommon key combinations.

For snapshot preference checks without XCTest, use `bash scripts/verify-snapshot-preferences.sh`. These use an isolated temporary registry and check compatibility, persistence, reconnects, UUID isolation, capture blocking, re-enabling, saved snapshot retention, internal volumes, and simulation isolation without accessing real drives.

Tests cover eject eligibility and UUID revalidation, busy-disk refusal, simulated ejection and capture guards, internal standby rejection, system volume filtering, mount-state parsing, APFS capacity, UUID persistence, registry compatibility, folder listing and symlink boundaries, explorer navigation/search, pins, and snapshot capture. Offline tests generate a photo, capture its thumbnail, remove the source fixture, and verify the saved catalog and thumbnail still work. Cancellation and failed refreshes preserve the previous catalog. Actual mount/unmount/eject integration requires an external test volume; do not use active work drives for testing.
