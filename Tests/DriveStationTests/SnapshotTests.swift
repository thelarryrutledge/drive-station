import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import DriveStation

final class SnapshotTests: XCTestCase {
    private func fixture() throws -> (URL, URL, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = folder.appendingPathComponent("Source")
        let storage = folder.appendingPathComponent("Cache")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Photos"), withIntermediateDirectories: true)
        try Data("Field notes".utf8).write(to: source.appendingPathComponent("Notes.txt"))
        try Data().write(to: source.appendingPathComponent(".hidden"))
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("Outside"), withDestinationURL: folder)
        let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        context.setFillColor(CGColor(red: 1, green: 0.7, blue: 0.2, alpha: 1))
        context.fillEllipse(in: CGRect(x: 220, y: 140, width: 200, height: 200))
        let imageURL = source.appendingPathComponent("Photos/Test landscape.png")
        let destination = CGImageDestinationCreateWithURL(imageURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return (folder, source, storage)
    }

    @MainActor func testOfflineSnapshotSurvivesSourceRemovalWithThumbnail() async throws {
        let (folder, source, storage) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let drive = Drive.demo[0]
        let capture = try await Task.detached { try SnapshotCapture.capture(drive: drive, source: source, storage: storage, progress: { _ in }) }.value
        XCTAssertEqual(capture.summary.thumbnailCount, 1, "Entries: \(capture.entries.map(\.path))")
        XCTAssertFalse(capture.summary.partial)
        XCTAssertFalse(capture.entries.contains { $0.path == ".hidden" })
        XCTAssertFalse(capture.entries.contains { $0.path.hasPrefix("Outside/") })
        let saved = try SnapshotStorage.commit(capture, at: storage)
        // Remove only this test's source fixture, then load everything from the cache.
        try FileManager.default.removeItem(at: source)
        let data = try SnapshotStorage.load(XCTUnwrap(saved[drive.id]), at: storage)
        let virtualRoot = URL(fileURLWithPath: "/Snapshot/Test", isDirectory: true)
        let model = ExplorerModel(ExplorerRequest(drive: drive, root: virtualRoot, simulation: false, snapshot: data))
        await model.load()
        XCTAssertTrue(model.visible.contains { $0.name == "Photos" })
        model.navigate(virtualRoot.appendingPathComponent("Photos"))
        await model.load()
        let image = try XCTUnwrap(model.visible.first)
        let thumbnail = try XCTUnwrap(image.cachedThumbnail)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnail.path))
        let decoded = try XCTUnwrap(CGImageSourceCreateWithURL(thumbnail as CFURL, nil))
        XCTAssertLessThanOrEqual(CGImageSourceCreateImageAtIndex(decoded, 0, nil)!.width, 256)
        model.open(image)
        XCTAssertTrue(model.notice?.contains("Reconnect") == true)
        model.finder()
        XCTAssertTrue(model.notice?.contains("offline snapshot") == true)
        model.navigate(virtualRoot)
        await model.load()
        model.search = "landscape"
        XCTAssertEqual(model.visible.map(\.name), ["Test landscape.png"])
        if let export = ProcessInfo.processInfo.environment["SNAPSHOT_FIXTURE_EXPORT"] {
            let exportURL = URL(fileURLWithPath: export, isDirectory: true)
            try FileManager.default.createDirectory(at: exportURL, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: data.cache, to: SnapshotStorage.folder(capture.summary, at: exportURL))
            _ = try SnapshotStorage.commit(capture, at: exportURL)
        }
    }

    @MainActor func testPartialLimitsAndCancelledRefreshPreserveSavedCapture() async throws {
        let (folder, source, storage) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let drive = Drive.demo[0]
        let partial = try await Task.detached { try SnapshotCapture.capture(drive: drive, source: source, storage: storage, maxItems: 1, maxThumbnails: 0, progress: { _ in }) }.value
        XCTAssertTrue(partial.summary.partial)
        XCTAssertEqual(partial.entries.count, 1)
        let saved = try SnapshotStorage.commit(partial, at: storage)
        let cancellation = CaptureCancellation()
        let task = Task.detached { try SnapshotCapture.capture(drive: drive, source: source, storage: storage, cancellation: cancellation, progress: { _ in }) }
        cancellation.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        XCTAssertEqual(try SnapshotStorage.catalog(at: storage), saved)
        XCTAssertThrowsError(try SnapshotCapture.capture(drive: drive, source: source.appendingPathComponent("Missing"), storage: storage, progress: { _ in }))
        XCTAssertEqual(try SnapshotStorage.catalog(at: storage), saved)
    }
}
