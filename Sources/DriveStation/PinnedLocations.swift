import Foundation

struct PinnedLocation: Identifiable, Codable, Equatable {
    let id: UUID
    let volumeID: String
    let relativePath: String
    let name: String

    func url(relativeTo root: URL) -> URL {
        relativePath.isEmpty ? root : root.appendingPathComponent(relativePath, isDirectory: true)
    }
}

@MainActor final class PinnedLocations: ObservableObject {
    static let shared = PinnedLocations(file: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DriveStation/pins.json"))
    static let simulation = PinnedLocations(file: nil)
    @Published private(set) var items: [PinnedLocation] = []
    @Published var error: String?
    private let file: URL?

    init(file: URL?) {
        self.file = file
        guard let file, FileManager.default.fileExists(atPath: file.path) else { return }
        do { items = try JSONDecoder().decode([PinnedLocation].self, from: Data(contentsOf: file)) }
        catch { self.error = "Couldn't load pinned locations: \(error.localizedDescription)" }
    }

    func locations(for volumeID: String) -> [PinnedLocation] { items.filter { $0.volumeID == volumeID } }

    private func relativePath(_ url: URL, root: URL) -> String? {
        guard DirectoryService.contains(url, root: root) else { return nil }
        let path = url.standardizedFileURL.path, base = root.standardizedFileURL.path
        if path == base { return "" }
        return String(path.dropFirst(base == "/" ? 1 : base.count + 1))
    }

    func contains(_ url: URL, request: ExplorerRequest) -> Bool {
        guard let path = relativePath(url, root: request.root) else { return false }
        return items.contains { $0.volumeID == request.drive.id && $0.relativePath == path }
    }

    func pin(_ url: URL, request: ExplorerRequest) {
        guard let path = relativePath(url, root: request.root), !contains(url, request: request) else { return }
        commit(items + [PinnedLocation(id: UUID(), volumeID: request.drive.id, relativePath: path, name: path.isEmpty ? request.drive.name : url.lastPathComponent)])
    }

    func remove(_ id: UUID) { commit(items.filter { $0.id != id }) }

    @discardableResult func move(_ source: UUID, to target: UUID, volumeID: String) -> Bool {
        var ordered = locations(for: volumeID)
        guard let from = ordered.firstIndex(where: { $0.id == source }), let to = ordered.firstIndex(where: { $0.id == target }), from != to else { return false }
        ordered.insert(ordered.remove(at: from), at: to)
        var iterator = ordered.makeIterator()
        return commit(items.map { $0.volumeID == volumeID ? iterator.next()! : $0 })
    }

    @discardableResult private func commit(_ updated: [PinnedLocation]) -> Bool {
        do {
            if let file {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(updated).write(to: file, options: .atomic)
            }
            items = updated
            return true
        } catch { self.error = "Couldn't save pinned locations: \(error.localizedDescription)"; return false }
    }
}
