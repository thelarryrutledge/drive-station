import Foundation
import AppKit

enum DriveState: String, Codable { case online, standby, offline }

struct Drive: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var device: String
    var format: String
    var connection: String
    var capacity: Int64
    var free: Int64?
    var mountPoint: String?
    var state: DriveState
    var lastSeen: Date
    // Optional for compatibility with registries written by version 1.0.
    var isInternal: Bool? = nil
    var internalVolume: Bool { isInternal == true }
    var canStandby: Bool { !internalVolume && state == .online }
    var usedFraction: Double { guard capacity > 0, let free else { return 0 }; return min(1, max(0, Double(capacity - free) / Double(capacity))) }
    static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal) }
    static func parse(_ info: [String: Any], now: Date = Date(), allowInternalRoot: Bool = false) -> Drive? {
        let root = allowInternalRoot && info["Internal"] as? Bool == true && info["MountPoint"] as? String == "/"
        guard (info["Internal"] as? Bool == false || root),
              info["WholeDisk"] as? Bool == false,
              let uuid = info["VolumeUUID"] as? String, !uuid.isEmpty,
              let name = info["VolumeName"] as? String, !name.isEmpty,
              let device = info["DeviceIdentifier"] as? String,
              let format = info["FilesystemType"] as? String else { return nil }
        let roles = info["APFSVolumeRole"] as? [String] ?? []
        guard root || roles.isEmpty || roles.allSatisfy({ !["System", "Preboot", "Recovery", "VM", "Update"].contains($0) }) else { return nil }
        let mount = info["MountPoint"] as? String
        guard mount != "/" || root else { return nil }
        func number(_ key: String) -> Int64? { (info[key] as? NSNumber)?.int64Value }
        let capacity = number("APFSContainerSize") ?? number("TotalSize") ?? number("VolumeSize") ?? 0
        let free = number("APFSContainerFree") ?? number("VolumeFreeSpace") ?? number("FreeSpace")
        let identity = root ? (info["APFSVolumeGroupID"] as? String ?? uuid) : uuid
        return Drive(id: identity, name: name, device: device, format: format.uppercased(), connection: root ? "Internal SSD" : info["BusProtocol"] as? String ?? "External", capacity: capacity, free: free, mountPoint: mount, state: (mount?.isEmpty == false) ? .online : .standby, lastSeen: now, isInternal: root)
    }
    static let demo: [Drive] = [
        Drive(id: "demo-1", name: "ORION • Studio", device: "disk4s1", format: "APFS", connection: "Thunderbolt", capacity: 4_000_000_000_000, free: 1_320_000_000_000, mountPoint: "/Volumes/Orion", state: .online, lastSeen: Date()),
        Drive(id: "demo-2", name: "NOVA • Cinema", device: "disk5s1", format: "APFS", connection: "USB", capacity: 8_000_000_000_000, free: 2_880_000_000_000, state: .standby, lastSeen: Date()),
        Drive(id: "demo-3", name: "ATLAS • Archive", device: "disk6s1", format: "EXFAT", connection: "USB", capacity: 12_000_000_000_000, free: 3_240_000_000_000, state: .standby, lastSeen: Date()),
        Drive(id: "demo-4", name: "VOYAGER • Field", device: "disk7s1", format: "APFS", connection: "USB", capacity: 2_000_000_000_000, free: 1_120_000_000_000, state: .offline, lastSeen: Date().addingTimeInterval(-86400))
    ]
}

struct StationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum DiskService {
    // Argument arrays only: volume names are never interpolated into a shell.
    static func run(_ args: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = args
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw StationError(message: String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "macOS could not complete the drive operation.")
        }
        return data
    }
    static func plist(_ args: [String]) throws -> [String: Any] {
        guard let result = try PropertyListSerialization.propertyList(from: run(args), format: nil) as? [String: Any] else {
            throw StationError(message: "macOS returned an unreadable drive response.")
        }
        return result
    }
    static func scan() throws -> [Drive] {
        let list = try plist(["list", "-plist", "external"])
        let identifiers = list["AllDisks"] as? [String] ?? []
        var result: [Drive] = []
        if let root = Drive.parse(try plist(["info", "-plist", "/"]), allowInternalRoot: true) { result.append(root) }
        for id in identifiers {
            // A failed query must not silently turn a connected drive into an offline drive.
            let info = try plist(["info", "-plist", id])
            if let drive = Drive.parse(info), !result.contains(where: { $0.id == drive.id }) { result.append(drive) }
        }
        return result
    }
    static func validated(_ drive: Drive) throws -> Drive {
        let info = try plist(["info", "-plist", drive.internalVolume ? "/" : drive.id])
        guard let current = Drive.parse(info, allowInternalRoot: drive.internalVolume), current.id == drive.id else {
            throw StationError(message: "This volume is no longer available. Scan your drives and try again.")
        }
        return current
    }
    static func standby(_ drive: Drive) throws {
        guard !drive.internalVolume else { throw StationError(message: "Internal storage stays online. Standby is available only for external volumes.") }
        let current = try validated(drive)
        guard current.canStandby else { return }
        _ = try run(["unmount", current.id])
    }
    static func wake(_ drive: Drive) throws -> URL {
        var current = try validated(drive)
        if current.state != .online {
            _ = try run(["mount", current.id])
            current = try validated(drive)
        }
        guard let path = current.mountPoint, !path.isEmpty else { throw StationError(message: "The volume has no mount point. It may need to be unlocked in Disk Utility.") }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

struct StationEvent: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
    var failure = false
}

@MainActor final class Station: ObservableObject {
    @Published var registry: [Drive] = []
    @Published var simulation = false
    @Published var samples = Drive.demo
    @Published var busy = false
    @Published var events: [StationEvent] = []
    @Published var error: String?
    @Published var selectedID: String?
    @Published var lastScan: Date?
    @Published var explorerRequest: ExplorerRequest?
    @Published var snapshots: [String: SnapshotSummary] = [:]
    @Published var snapshotProgress: String?
    private var snapshotWorker: Task<DriveSnapshot, Error>?
    private var automaticAttempts: Set<String> = []
    private var snapshotCancellationRequested = false
    var drives: [Drive] { simulation ? samples : registry }
    var selected: Drive? { drives.first(where: { $0.id == selectedID }) ?? drives.first }
    private let registryURL: URL
    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DriveStation")
        registryURL = folder.appendingPathComponent("registry.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: registryURL.path) {
                registry = try JSONDecoder().decode([Drive].self, from: Data(contentsOf: registryURL)).map { var d = $0; d.state = .offline; d.mountPoint = nil; return d }
            }
        } catch { self.error = "Could not load the drive registry: \(error.localizedDescription)" }
        do { snapshots = try SnapshotStorage.catalog() }
        catch { self.error = "Could not load snapshot catalog: \(error.localizedDescription)" }
    }
    func log(_ message: String, failure: Bool = false) {
        events.insert(StationEvent(text: message, failure: failure), at: 0)
        events = Array(events.prefix(100))
    }
    func save() {
        do { try JSONEncoder().encode(registry).write(to: registryURL, options: .atomic) }
        catch { self.error = "Could not remember drives: \(error.localizedDescription)"; log(self.error!, failure: true) }
    }
    static func merge(_ old: [Drive], _ found: [Drive]) -> [Drive] {
        var result = old.filter { !$0.internalVolume }.map { var d = $0; d.state = .offline; d.mountPoint = nil; return d }
        for drive in found {
            if let i = result.firstIndex(where: { $0.id == drive.id }) {
                var updated = drive
                if updated.free == nil { updated.free = result[i].free }
                result[i] = updated
            } else { result.append(drive) }
        }
        return result.sorted { if $0.internalVolume != $1.internalVolume { return $0.internalVolume }; return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if simulation { log("SIMULATION / telemetry refreshed"); return }
        do {
            let found = try await Task.detached(priority: .userInitiated) { try DiskService.scan() }.value
            registry = Self.merge(registry, found)
            lastScan = Date()
            save()
            log("Scan complete · \(found.count) volume\(found.count == 1 ? "" : "s") connected")
            let automatic = found.filter { !$0.internalVolume && $0.state == .online && snapshots[$0.id] == nil && !automaticAttempts.contains($0.id) }
            if UserDefaults.standard.object(forKey: "automaticSnapshots") as? Bool ?? true {
                Task { @MainActor in
                    for drive in automatic {
                        guard !self.simulation, self.snapshotProgress == nil else { break }
                        self.automaticAttempts.insert(drive.id)
                        await self.captureSnapshot(drive)
                        if self.snapshotCancellationRequested { break }
                    }
                }
            }
        } catch { self.error = error.localizedDescription; log(error.localizedDescription, failure: true) }
    }
    func act(_ drive: Drive, open: Bool) async {
        guard !busy, drive.state != .offline else { return }
        guard open || drive.canStandby else { return }
        busy = true
        if simulation {
            if let i = samples.firstIndex(where: { $0.id == drive.id }) { samples[i].state = open ? .online : .standby }
            log("SIMULATION / \(drive.name) \(open ? "opened" : "on standby")")
            busy = false
            return
        }
        do {
            if open {
                let url = try await Task.detached(priority: .userInitiated) { try DiskService.wake(drive) }.value
                guard NSWorkspace.shared.open(url) else { throw StationError(message: "The volume mounted, but Finder could not open it.") }
            } else { try await Task.detached(priority: .userInitiated) { try DiskService.standby(drive) }.value }
            log("\(drive.name) · \(open ? "opened in Finder" : "safely unmounted")")
        } catch { self.error = error.localizedDescription; log(error.localizedDescription, failure: true) }
        busy = false
        await refresh()
    }
    func setSimulation(_ enabled: Bool) {
        guard !busy else { return }
        simulation = enabled
        explorerRequest = nil
        selectedID = nil
        log(enabled ? "Simulation enabled · sample volumes only" : "Live mode enabled")
        if !enabled { Task { await refresh() } }
    }
    func forget(_ drive: Drive) {
        guard drive.state == .offline, !drive.internalVolume, !busy else { return }
        if simulation { samples.removeAll { $0.id == drive.id } }
        else { registry.removeAll { $0.id == drive.id }; save() }
        log("Removed \(drive.name) from the registry")
    }
    func explore(_ drive: Drive) async {
        guard !busy, drive.state != .offline else { return }
        busy = true
        defer { busy = false }
        if simulation {
            if let i = samples.firstIndex(where: { $0.id == drive.id }) { samples[i].state = .online }
            explorerRequest = ExplorerRequest(drive: drive, root: URL(fileURLWithPath: "/Simulation/\(drive.id)"), simulation: true)
            log("SIMULATION / exploring \(drive.name)")
            return
        }
        do {
            let root = try await Task.detached(priority: .userInitiated) { try DiskService.wake(drive) }.value
            if let i = registry.firstIndex(where: { $0.id == drive.id }) { registry[i].state = .online; registry[i].mountPoint = root.path; save() }
            explorerRequest = ExplorerRequest(drive: drive, root: root, simulation: false)
            log("Exploring \(drive.name)")
        } catch { self.error = error.localizedDescription; log(error.localizedDescription, failure: true) }
    }
    func captureSnapshot(_ drive: Drive) async {
        guard !busy, !simulation, drive.state != .offline else { return }
        busy = true
        snapshotCancellationRequested = false
        snapshotProgress = "Preparing snapshot · \(drive.name)"
        defer { busy = false; snapshotProgress = nil; snapshotWorker = nil }
        var generated: DriveSnapshot?
        do {
            let station = self
            let worker = Task.detached(priority: .utility) {
                let mount = try DiskService.wake(drive)
                let source = drive.internalVolume ? FileManager.default.homeDirectoryForCurrentUser : mount
                let result = try SnapshotCapture.capture(drive: drive, source: source) { message in
                    Task { @MainActor in if station.snapshotWorker != nil { station.snapshotProgress = message } }
                }
                do {
                    try Task.checkCancellation()
                    _ = try DiskService.validated(drive)
                    return result
                } catch {
                    try? FileManager.default.removeItem(at: SnapshotStorage.folder(result.summary))
                    throw error
                }
            }
            snapshotWorker = worker
            let result = try await worker.value
            generated = result
            if worker.isCancelled { throw CancellationError() }
            snapshots = try await Task.detached(priority: .utility) { try SnapshotStorage.commit(result) }.value
            if let i = registry.firstIndex(where: { $0.id == drive.id }) { registry[i].state = .online; save() }
            log("Snapshot saved · \(drive.name) · \(result.summary.itemCount.formatted()) items · \(result.summary.thumbnailCount) thumbnails\(result.summary.partial ? " · partial coverage" : "")")
        } catch {
            if let generated { try? FileManager.default.removeItem(at: SnapshotStorage.folder(generated.summary)) }
            if error is CancellationError { log("Snapshot cancelled · previous capture kept") }
            else { self.error = "Snapshot failed: \(error.localizedDescription)"; log(self.error!, failure: true) }
        }
    }
    func cancelSnapshot() { snapshotCancellationRequested = true; snapshotWorker?.cancel() }
    func browseSnapshot(_ drive: Drive) async {
        guard !busy, let summary = snapshots[drive.id], !simulation else { return }
        busy = true
        defer { busy = false }
        do {
            let data = try await Task.detached(priority: .userInitiated) { try SnapshotStorage.load(summary) }.value
            explorerRequest = ExplorerRequest(drive: drive, root: URL(fileURLWithPath: "/Snapshot/\(summary.generation.uuidString)", isDirectory: true), simulation: false, snapshot: data)
            log("Browsing saved snapshot · \(drive.name)")
        } catch { self.error = "Couldn't open snapshot: \(error.localizedDescription)" }
    }
}
