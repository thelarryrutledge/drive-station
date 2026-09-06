import XCTest
@testable import DriveStation

final class DriveStationTests: XCTestCase {
    private var external: [String: Any] {
        ["Internal": false, "WholeDisk": false, "VolumeUUID": "A1", "VolumeName": "Media $(test)", "DeviceIdentifier": "disk4s1", "FilesystemType": "apfs", "BusProtocol": "USB", "APFSContainerSize": NSNumber(value: 4_000_000_000_000 as Int64), "APFSContainerFree": NSNumber(value: 1_000_000_000_000 as Int64), "MountPoint": "/Volumes/Media"]
    }
    func testExternalVolumeAndSharedCapacity() throws {
        let drive = try XCTUnwrap(Drive.parse(external))
        XCTAssertEqual(drive.id, "A1")
        XCTAssertEqual(drive.state, .online)
        XCTAssertEqual(drive.usedFraction, 0.75)
        XCTAssertEqual(drive.name, "Media $(test)")
    }
    func testInternalAndUnidentifiedDisksCannotBeControlled() {
        var info = external
        info["Internal"] = true
        XCTAssertNil(Drive.parse(info))
        info.removeValue(forKey: "Internal")
        XCTAssertNil(Drive.parse(info))
        info = external; info["WholeDisk"] = true
        XCTAssertNil(Drive.parse(info))
        info = external; info.removeValue(forKey: "VolumeUUID")
        XCTAssertNil(Drive.parse(info))
        info = external; info["MountPoint"] = "/"
        XCTAssertNil(Drive.parse(info))
        info = external; info["APFSVolumeRole"] = ["Recovery"]
        XCTAssertNil(Drive.parse(info))
    }
    func testUnmountedVolumeIsStandbyAndUnknownFreeStaysUnknown() throws {
        var info = external
        info.removeValue(forKey: "MountPoint")
        info.removeValue(forKey: "APFSContainerFree")
        let drive = try XCTUnwrap(Drive.parse(info))
        XCTAssertEqual(drive.state, .standby)
        XCTAssertNil(drive.free)
    }
    @MainActor func testRegistryTracksUUIDAcrossReconnectAndKeepsOfflineDrives() {
        let original = Drive.demo
        var reconnected = original[0]
        reconnected.device = "disk12s2"
        reconnected.name = "Renamed drive"
        reconnected.free = nil
        let merged = Station.merge(original, [reconnected])
        XCTAssertEqual(merged.count, 4)
        let found = merged.first { $0.id == reconnected.id }!
        XCTAssertEqual(found.device, "disk12s2")
        XCTAssertEqual(found.name, "Renamed drive")
        XCTAssertEqual(found.free, original[0].free)
        XCTAssertEqual(merged.filter { $0.state == .offline }.count, 3)
        XCTAssertTrue(merged.filter { $0.state == .offline }.allSatisfy { $0.mountPoint == nil })
    }
    func testRegistryRoundTrip() throws {
        let data = try JSONEncoder().encode(Drive.demo)
        XCTAssertEqual(try JSONDecoder().decode([Drive].self, from: data), Drive.demo)
    }
    func testInternalRootIsBrowseOnlyWithStableGroupIdentity() throws {
        var info = external
        info["Internal"] = true
        info["MountPoint"] = "/"
        info["APFSVolumeGroupID"] = "stable-group"
        info["APFSVolumeRole"] = ["System"]
        let drive = try XCTUnwrap(Drive.parse(info, allowInternalRoot: true))
        XCTAssertEqual(drive.id, "stable-group")
        XCTAssertTrue(drive.internalVolume)
        XCTAssertFalse(drive.canStandby)
        XCTAssertThrowsError(try DiskService.standby(drive))
        info["MountPoint"] = "/System/Volumes/Preboot"
        XCTAssertNil(Drive.parse(info, allowInternalRoot: true))
    }
    func testOldRegistryWithoutInternalFlagStillDecodes() throws {
        let data = try JSONEncoder().encode(Drive.demo[0])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "isInternal")
        let drive = try JSONDecoder().decode(Drive.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(drive.internalVolume)
    }
    func testDirectoryListingHiddenFilesPackagesAndBoundary() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        try manager.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: false)
        try manager.createDirectory(at: root.appendingPathComponent("Example.app"), withIntermediateDirectories: false)
        try Data("sample".utf8).write(to: root.appendingPathComponent("note.txt"))
        try Data().write(to: root.appendingPathComponent(".hidden"))
        try manager.createSymbolicLink(at: root.appendingPathComponent("Outside"), withDestinationURL: root.deletingLastPathComponent())
        let items = try DirectoryService.list(root, root: root, hidden: false)
        XCTAssertFalse(items.contains { $0.name == ".hidden" })
        XCTAssertTrue(items.first { $0.name == "Folder" }!.browsable)
        XCTAssertFalse(items.first { $0.name == "Outside" }!.browsable)
        XCTAssertFalse(items.first { $0.name == "Example.app" }!.browsable)
        XCTAssertEqual(items.first { $0.name == "note.txt" }!.size, 6)
        XCTAssertTrue(try DirectoryService.list(root, root: root, hidden: true).contains { $0.name == ".hidden" })
        XCTAssertThrowsError(try DirectoryService.list(root.appendingPathComponent("Outside"), root: root, hidden: false))
        XCTAssertFalse(DirectoryService.contains(URL(fileURLWithPath: root.path + "-other"), root: root))
    }
    @MainActor func testExplorerSimulationNavigationAndSearch() async {
        let root = URL(fileURLWithPath: "/Simulation/demo")
        let model = ExplorerModel(ExplorerRequest(drive: Drive.demo[0], root: root, simulation: true))
        await model.load()
        XCTAssertEqual(model.visible.count, 4)
        model.search = "project"
        XCTAssertEqual(model.visible.map(\.name), ["Projects"])
        model.navigate(root.appendingPathComponent("Projects"))
        await model.load()
        XCTAssertEqual(model.visible.count, 3)
        XCTAssertEqual(model.crumbs, [root, root.appendingPathComponent("Projects")])
        model.goBack()
        XCTAssertEqual(model.current, root)
        model.goForward()
        XCTAssertEqual(model.current.lastPathComponent, "Projects")
    }
    @MainActor func testPinsPersistDeduplicateReorderAndRemove() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("pins.json")
        let pins = PinnedLocations(file: file)
        XCTAssertTrue(pins.items.isEmpty)
        let request = ExplorerRequest(drive: Drive.demo[0], root: URL(fileURLWithPath: "/Volumes/Orion"), simulation: false)
        for name in ["A", "B", "C", "A"] { pins.pin(request.root.appendingPathComponent(name), request: request) }
        XCTAssertEqual(pins.items.map(\.name), ["A", "B", "C"])
        let first = pins.items[0].id, last = pins.items[2].id
        XCTAssertTrue(pins.move(first, to: last, volumeID: request.drive.id))
        XCTAssertEqual(pins.items.map(\.name), ["B", "C", "A"])
        let restored = PinnedLocations(file: file)
        XCTAssertEqual(restored.items, pins.items)
        XCTAssertTrue(restored.move(first, to: restored.items[0].id, volumeID: request.drive.id))
        XCTAssertEqual(restored.items.map(\.name), ["A", "B", "C"])
        restored.remove(first)
        XCTAssertEqual(PinnedLocations(file: file).items.map(\.name), ["B", "C"])
    }
    @MainActor func testPinsAreVolumeRelativeAndIsolated() throws {
        let pins = PinnedLocations(file: nil)
        let request = ExplorerRequest(drive: Drive.demo[0], root: URL(fileURLWithPath: "/Volumes/Orion"), simulation: false)
        pins.pin(request.root.appendingPathComponent("Projects/Film"), request: request)
        pins.pin(URL(fileURLWithPath: "/Volumes/Other"), request: request)
        XCTAssertEqual(pins.items.count, 1)
        XCTAssertEqual(pins.items[0].url(relativeTo: URL(fileURLWithPath: "/Volumes/Orion 1")).path, "/Volumes/Orion 1/Projects/Film")
        XCTAssertTrue(pins.locations(for: Drive.demo[1].id).isEmpty)
        XCTAssertFalse(pins.move(pins.items[0].id, to: UUID(), volumeID: Drive.demo[1].id))
        XCTAssertTrue(PinnedLocations(file: nil).items.isEmpty)
    }
}
