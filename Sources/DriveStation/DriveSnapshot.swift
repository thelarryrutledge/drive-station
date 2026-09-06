import Foundation
import AppKit
import QuickLookThumbnailing
import ImageIO
import UniformTypeIdentifiers

struct SnapshotSummary: Codable, Equatable {
    let generation: UUID
    let volumeID: String
    let volumeName: String
    let capturedAt: Date
    var itemCount: Int
    var thumbnailCount: Int
    var skippedCount: Int
    var partial: Bool
    var thumbnailLimitReached: Bool
    var scope: String
}

struct SnapshotEntry: Codable {
    let path: String
    let directory: Bool
    let package: Bool
    let symbolicLink: Bool
    let size: Int64?
    let modified: Date?
    var thumbnail: String?
    var parent: String { (path as NSString).deletingLastPathComponent }
    func fileEntry(root: URL, cache: URL) -> FileEntry {
        FileEntry(url: root.appendingPathComponent(path), name: (path as NSString).lastPathComponent,
                  directory: directory, package: package, symbolicLink: symbolicLink, size: size, modified: modified,
                  cachedThumbnail: thumbnail.map { cache.appendingPathComponent($0) }, savedPath: path)
    }
}

struct DriveSnapshot: Codable {
    var summary: SnapshotSummary
    var entries: [SnapshotEntry]
}

struct SnapshotViewData {
    let document: DriveSnapshot
    let cache: URL
    let children: [String: [SnapshotEntry]]
    init(document: DriveSnapshot, cache: URL) {
        self.document = document; self.cache = cache
        children = Dictionary(grouping: document.entries, by: \.parent)
    }
    func list(_ url: URL, root: URL) -> [FileEntry] {
        let base = root.standardizedFileURL.path, path = url.standardizedFileURL.path
        let relative = path == base ? "" : String(path.dropFirst(base.count + 1))
        return (children[relative] ?? []).map { $0.fileEntry(root: root, cache: cache) }
    }
}

enum SnapshotStorage {
    static var root: URL {
        // Allows UI verification against an isolated generated catalog.
        if let path = ProcessInfo.processInfo.environment["DRIVE_STATION_SNAPSHOT_CACHE"], path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DriveStation/Snapshots", isDirectory: true)
    }
    static func catalog(at root: URL = root) throws -> [String: SnapshotSummary] {
        let url = root.appendingPathComponent("catalog.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONDecoder().decode([String: SnapshotSummary].self, from: Data(contentsOf: url))
    }
    static func folder(_ summary: SnapshotSummary, at root: URL = root) -> URL {
        root.appendingPathComponent(summary.generation.uuidString, isDirectory: true)
    }
    static func load(_ summary: SnapshotSummary, at root: URL = root) throws -> SnapshotViewData {
        let cache = folder(summary, at: root)
        let document = try JSONDecoder().decode(DriveSnapshot.self, from: Data(contentsOf: cache.appendingPathComponent("snapshot.json")))
        guard document.summary.volumeID == summary.volumeID, document.summary.generation == summary.generation else {
            throw StationError(message: "The saved snapshot doesn't match this volume.")
        }
        guard document.entries.allSatisfy({ entry in
            !entry.path.hasPrefix("/") && !entry.path.split(separator: "/").contains("..") &&
            (entry.thumbnail == nil || (entry.thumbnail == (entry.thumbnail! as NSString).lastPathComponent && !entry.thumbnail!.hasPrefix(".")))
        }) else { throw StationError(message: "The saved snapshot contains an invalid cache path.") }
        return SnapshotViewData(document: document, cache: cache)
    }
    // The catalog is the commit point: an interrupted capture never replaces a good snapshot.
    static func commit(_ snapshot: DriveSnapshot, at root: URL = root) throws -> [String: SnapshotSummary] {
        var saved = try catalog(at: root)
        let previous = saved[snapshot.summary.volumeID]
        let cache = folder(snapshot.summary, at: root)
        try JSONEncoder().encode(snapshot).write(to: cache.appendingPathComponent("snapshot.json"), options: .atomic)
        saved[snapshot.summary.volumeID] = snapshot.summary
        try JSONEncoder().encode(saved).write(to: root.appendingPathComponent("catalog.json"), options: .atomic)
        // Keep the immediately previous capture as a recovery copy. Older generations are
        // removed only for this volume, from our UUID-named cache directories.
        if let directories = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for directory in directories where UUID(uuidString: directory.lastPathComponent) != nil && directory.lastPathComponent != snapshot.summary.generation.uuidString && directory.lastPathComponent != previous?.generation.uuidString {
                guard let data = try? Data(contentsOf: directory.appendingPathComponent("snapshot.json")),
                      let old = try? JSONDecoder().decode(DriveSnapshot.self, from: data),
                      old.summary.volumeID == snapshot.summary.volumeID else { continue }
                try? FileManager.default.removeItem(at: directory)
            }
        }
        return saved
    }
}

private final class ThumbnailResult: @unchecked Sendable {
    let lock = NSLock()
    private var bytes: Data?
    func set(_ data: Data?) { lock.lock(); bytes = data; lock.unlock() }
    func get() -> Data? { lock.lock(); defer { lock.unlock() }; return bytes }
}

final class CaptureCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

enum SnapshotCapture {
    static let supported = Set(["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp", "pdf", "mov", "mp4", "m4v"])
    static func thumbnail(_ url: URL, cancellation: CaptureCancellation?) -> Data? {
        guard cancellation?.isCancelled != true else { return nil }
        // Downsample photos directly rather than decoding a full-resolution image.
        if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 256, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
            let data = NSMutableData()
            if let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
                if CGImageDestinationFinalize(destination), cancellation?.isCancelled != true { return data as Data }
            }
        }
        guard cancellation?.isCancelled != true else { return nil }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 256, height: 192), scale: 1, representationTypes: .thumbnail)
        let completed = DispatchSemaphore(value: 0)
        let result = ThumbnailResult()
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            defer { completed.signal() }
            guard let image = representation?.cgImage else { return }
            let bytes = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
            if CGImageDestinationFinalize(destination) { result.set(bytes as Data) }
        }
        let deadline = DispatchTime.now() + 3
        while completed.wait(timeout: .now() + .milliseconds(100)) == .timedOut {
            if cancellation?.isCancelled == true || DispatchTime.now() >= deadline {
                QLThumbnailGenerator.shared.cancel(request)
                return nil
            }
        }
        guard cancellation?.isCancelled != true else { return nil }
        return result.get()
    }
    static func capture(drive: Drive, source: URL, storage: URL = SnapshotStorage.root,
                        maxItems: Int = 100_000, maxThumbnails: Int = 300,
                        cancellation: CaptureCancellation? = nil,
                        progress: @escaping @Sendable (String) -> Void) throws -> DriveSnapshot {
        func checkCancellation() throws {
            if Task.isCancelled || cancellation?.isCancelled == true { throw CancellationError() }
        }
        try checkCancellation()
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let manager = FileManager.default
        // A direct read makes a missing or denied root an error, not an empty snapshot.
        _ = try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var summary = SnapshotSummary(generation: UUID(), volumeID: drive.id, volumeName: drive.name, capturedAt: Date(), itemCount: 0, thumbnailCount: 0, skippedCount: 0, partial: false, thumbnailLimitReached: false, scope: drive.internalVolume ? "Home folder" : "Volume root")
        let cache = SnapshotStorage.folder(summary, at: storage)
        try manager.createDirectory(at: cache, withIntermediateDirectories: true)
        var succeeded = false
        defer { if !succeeded { try? manager.removeItem(at: cache) } }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .isUbiquitousItemKey, .volumeIdentifierKey]
        let sourceVolume = try source.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        let deadline = Date().addingTimeInterval(120)
        var unreadable = 0
        var entries: [SnapshotEntry] = []
        let base = source.standardizedFileURL.path
        var folders = [source], cursor = 0
        captureLoop: while cursor < folders.count {
            let directory = folders[cursor]; cursor += 1
            try checkCancellation()
            let children: [URL]
            do { children = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) }
            catch { unreadable += 1; continue }
            for url in children {
                try checkCancellation()
                if entries.count >= maxItems || Date() >= deadline { summary.partial = true; break captureLoop }
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { unreadable += 1; continue }
                // Explicit traversal never follows symlinks, other mounted volumes, packages or cloud items.
                if let volume = values.volumeIdentifier as? NSObject, let sourceVolume, volume != sourceVolume { unreadable += 1; continue }
                let relative = String(url.standardizedFileURL.path.dropFirst(base == "/" ? 1 : base.count + 1))
                let link = values.isSymbolicLink == true || values.isUbiquitousItem == true
                entries.append(SnapshotEntry(path: relative, directory: values.isDirectory == true, package: values.isPackage == true, symbolicLink: link, size: values.fileSize.map(Int64.init), modified: values.contentModificationDate))
                if values.isDirectory == true && values.isPackage != true && !link { folders.append(url) }
                if entries.count % 200 == 0 { progress("Indexing \(drive.name) · \(entries.count.formatted()) items") }
            }
        }
        summary.itemCount = entries.count; summary.skippedCount = unreadable
        summary.partial = summary.partial || unreadable > 0
        let thumbnailDeadline = Date().addingTimeInterval(90)
        var attempted = 0
        for index in entries.indices {
            try checkCancellation()
            let entry = entries[index]
            guard !entry.directory, !entry.symbolicLink, supported.contains((entry.path as NSString).pathExtension.lowercased()) else { continue }
            guard attempted < maxThumbnails && Date() < thumbnailDeadline else { summary.thumbnailLimitReached = true; break }
            attempted += 1
            progress("Saving thumbnails · \(attempted) / \(maxThumbnails) · \(drive.name)")
            let image = autoreleasepool { thumbnail(source.appendingPathComponent(entry.path), cancellation: cancellation) }
            try checkCancellation()
            if let image {
                let filename = "\(index).jpg"
                try image.write(to: cache.appendingPathComponent(filename), options: .atomic)
                entries[index].thumbnail = filename; summary.thumbnailCount += 1
            }
        }
        try checkCancellation()
        progress("Saving snapshot · \(drive.name)")
        succeeded = true
        return DriveSnapshot(summary: summary, entries: entries)
    }
}
