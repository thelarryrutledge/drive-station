// Standalone checks for Macs with command-line tools but no XCTest framework.
// Run with: bash scripts/verify-snapshot-preferences.sh
import Foundation

@main private enum SnapshotPreferenceChecks {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("registry.json")
        let station = Station(registryURL: file)
        precondition(station.error == nil)
        var card = Drive.demo[0]
        card.name = "EOS_DIGITAL"
        station.registry = [card]
        precondition(station.canCaptureSnapshot(card))
        precondition(station.shouldAutomaticallySnapshot(card))

        // Old registry files default to allowing snapshots.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as! [String: Any]
        legacy.removeValue(forKey: "doNotSnapshot")
        let decoded = try JSONDecoder().decode(Drive.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(decoded.doNotSnapshot == nil)

        station.setSnapshotExcluded(true, for: card)
        // Deliberately pass a stale value, as a queued capture or menu can do.
        precondition(station.isSnapshotExcluded(card))
        precondition(!station.canCaptureSnapshot(card))
        precondition(!station.shouldAutomaticallySnapshot(card))
        let events = station.events.count
        await station.captureSnapshot(card)
        precondition(station.error == nil && station.snapshotProgress == nil)
        precondition(station.events.count == events, "An excluded capture must return before querying a disk")

        let restored = Station(registryURL: file)
        precondition(restored.registry.count == 1 && restored.registry[0].state == .offline)
        precondition(restored.isSnapshotExcluded(card), "Exclusions must survive relaunch")
        var renamed = card
        renamed.name = "Next shoot"
        renamed.device = "disk99s9"
        renamed.mountPoint = "/Volumes/Next shoot"
        restored.registry = Station.merge(restored.registry, [renamed])
        precondition(restored.registry[0].name == renamed.name)
        precondition(restored.isSnapshotExcluded(renamed), "A fresh scan must preserve the preference")
        restored.registry = Station.merge(restored.registry, [])
        precondition(restored.isSnapshotExcluded(renamed), "Disconnection must preserve the preference")
        restored.registry = Station.merge(restored.registry, [renamed])
        precondition(!restored.shouldAutomaticallySnapshot(renamed))

        // Names do not confer exclusions on unrelated volumes.
        var other = renamed
        other.id = "different-volume"
        restored.registry = Station.merge(restored.registry, [renamed, other])
        precondition(!restored.isSnapshotExcluded(other))
        precondition(restored.shouldAutomaticallySnapshot(other))

        restored.setSnapshotExcluded(false, for: renamed)
        precondition(restored.canCaptureSnapshot(renamed))
        precondition(restored.shouldAutomaticallySnapshot(renamed))
        precondition(!Station(registryURL: file).isSnapshotExcluded(renamed), "Re-enabling must persist too")
        let summary = SnapshotSummary(generation: UUID(), volumeID: card.id, volumeName: card.name,
            capturedAt: Date(), itemCount: 0, thumbnailCount: 0, skippedCount: 0,
            partial: false, thumbnailLimitReached: false, scope: "Volume root")
        restored.snapshots[card.id] = summary
        restored.setSnapshotExcluded(true, for: renamed)
        precondition(restored.snapshots[card.id] == summary, "Excluding must keep existing snapshots")
        restored.setSnapshotExcluded(false, for: renamed)
        precondition(!restored.shouldAutomaticallySnapshot(renamed), "Existing captures remain manual to refresh")
        precondition(restored.canCaptureSnapshot(renamed))

        // Internal roots are rebuilt during merge, but still retain their preference.
        var internalDrive = card
        internalDrive.isInternal = true
        var excludedInternal = internalDrive
        excludedInternal.doNotSnapshot = true
        let mergedInternal = Station.merge([excludedInternal], [internalDrive])
        precondition(mergedInternal.count == 1 && mergedInternal[0].doNotSnapshot == true)

        // Simulation preferences are held separately and never written to the registry.
        let saved = try Data(contentsOf: file)
        restored.setSimulation(true)
        restored.setSnapshotExcluded(true, for: restored.samples[0])
        precondition(restored.isSnapshotExcluded(restored.samples[0]))
        precondition(!restored.canCaptureSnapshot(restored.samples[0]))
        let afterSimulation = try Data(contentsOf: file)
        precondition(saved == afterSimulation)
        print("Snapshot preference checks passed: compatibility, persistence, reconnects, UUID isolation, queued/manual blocking, re-enabling, saved snapshots, internal volumes, and simulation.")
    }
}
