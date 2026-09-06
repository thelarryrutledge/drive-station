import SwiftUI
import AppKit

struct ExplorerRequest: Identifiable {
    let id = UUID()
    let drive: Drive
    let root: URL
    let simulation: Bool
    var snapshot: SnapshotViewData? = nil
}

struct FileEntry: Identifiable {
    let url: URL
    let name: String
    let directory: Bool
    let package: Bool
    let symbolicLink: Bool
    let size: Int64?
    let modified: Date?
    var cachedThumbnail: URL? = nil
    var savedPath: String? = nil
    var id: URL { url }
    var browsable: Bool { directory && !package && !symbolicLink }
    var kind: String { symbolicLink ? "Link" : package ? "Package" : directory ? "Folder" : url.pathExtension.isEmpty ? "File" : url.pathExtension.uppercased() + " file" }
    var symbol: String { symbolicLink ? "link" : browsable ? "folder.fill" : package ? "shippingbox" : ["jpg", "png", "heic", "gif"].contains(url.pathExtension.lowercased()) ? "photo" : ["mov", "mp4", "mkv"].contains(url.pathExtension.lowercased()) ? "film" : "doc" }
}

enum DirectoryService {
    static func contains(_ url: URL, root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        return base == "/" || path == base || path.hasPrefix(base + "/")
    }
    static func list(_ url: URL, root: URL, hidden: Bool) throws -> [FileEntry] {
        guard contains(url.resolvingSymlinksInPath(), root: root.resolvingSymlinksInPath()) else {
            throw StationError(message: "This folder points outside the selected volume. Open it in Finder instead.")
        }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: hidden ? [] : [.skipsHiddenFiles])
        return urls.map { child in
            let values = try? child.resourceValues(forKeys: keys)
            return FileEntry(url: child, name: child.lastPathComponent, directory: values?.isDirectory == true, package: values?.isPackage == true, symbolicLink: values?.isSymbolicLink == true, size: values?.fileSize.map(Int64.init), modified: values?.contentModificationDate)
        }
    }
    static func samples(_ url: URL, root: URL) -> [FileEntry] {
        let atRoot = url.standardizedFileURL.path == root.standardizedFileURL.path
        let names = atRoot ? ["Projects", "Footage", "Exports", "Station notes.txt"] : ["Session 01.mov", "Reference.png", "Project notes.txt"]
        return names.enumerated().map { i, name in
            let folder = atRoot && i < 3
            return FileEntry(url: url.appendingPathComponent(name), name: name, directory: folder, package: false, symbolicLink: false, size: folder ? nil : Int64((i + 1) * 480_000), modified: Date(timeIntervalSince1970: 1_780_000_000))
        }
    }
}

@MainActor final class ExplorerModel: ObservableObject {
    let request: ExplorerRequest
    @Published var current: URL
    @Published var entries: [FileEntry] = []
    @Published var selection: URL?
    @Published var search = ""
    @Published var showHidden = false
    @Published var sort = "Name"
    @Published var loading = false
    @Published var error: String?
    @Published var notice: String?
    @Published var back: [URL] = []
    @Published var forward: [URL] = []
    private var generation = UUID()
    init(_ request: ExplorerRequest) { self.request = request; current = request.root }
    var selected: FileEntry? { visible.first { $0.id == selection } }
    var visible: [FileEntry] {
        let candidates: [FileEntry]
        if let snapshot = request.snapshot, !search.isEmpty {
            candidates = snapshot.document.entries.lazy.filter { $0.path.localizedCaseInsensitiveContains(self.search) }.prefix(500).map { $0.fileEntry(root: self.request.root, cache: snapshot.cache) }
        } else { candidates = entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
        return candidates.sorted {
            if $0.browsable != $1.browsable { return $0.browsable }
            if sort == "Size", $0.size != $1.size { return ($0.size ?? -1) > ($1.size ?? -1) }
            if sort == "Modified", $0.modified != $1.modified { return ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    var crumbs: [URL] {
        var result = [current]
        var url = current
        while url.standardizedFileURL.path != request.root.standardizedFileURL.path && url.path != "/" {
            url = url.deletingLastPathComponent()
            if url.standardizedFileURL.path == request.root.standardizedFileURL.path { url = request.root }
            result.insert(url, at: 0)
        }
        return result
    }
    func load() async {
        let token = UUID(); generation = token
        let target = current, root = request.root, hidden = showHidden
        loading = true; error = nil; notice = nil; selection = nil; entries = []
        do {
            let found: [FileEntry]
            if let snapshot = request.snapshot { found = snapshot.list(target, root: root) }
            else if request.simulation { found = DirectoryService.samples(target, root: root) }
            else { found = try await Task.detached(priority: .userInitiated) { try DirectoryService.list(target, root: root, hidden: hidden) }.value }
            guard generation == token else { return }
            entries = found; loading = false
        } catch {
            guard generation == token else { return }
            self.error = "Couldn't read this folder. \(error.localizedDescription)"; loading = false
        }
    }
    func navigate(_ url: URL, record: Bool = true) {
        guard DirectoryService.contains(url, root: request.root) else { return }
        let url = url.standardizedFileURL.path == request.root.standardizedFileURL.path ? request.root : url
        if record && url != current { back.append(current); forward = [] }
        current = url; search = ""
        Task { await load() }
    }
    func goBack() { guard let url = back.popLast() else { return }; forward.append(current); navigate(url, record: false) }
    func goForward() { guard let url = forward.popLast() else { return }; back.append(current); navigate(url, record: false) }
    func open(_ entry: FileEntry) {
        if entry.browsable { navigate(entry.url) }
        else if request.snapshot != nil { notice = "Saved metadata and thumbnail only. Reconnect the drive and use Explore to open the original." }
        else if request.simulation { notice = "Sample file · opening is simulated." }
        else if entry.symbolicLink { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        else if !NSWorkspace.shared.open(entry.url) { error = "No application could open this file. Try Reveal in Finder." }
    }
    func finder(reveal: Bool = false) {
        guard request.snapshot == nil else { notice = "This is an offline snapshot. Open the connected volume to access originals."; return }
        guard !request.simulation else { notice = "Finder access is simulated for sample volumes."; return }
        if reveal, let selected { NSWorkspace.shared.activateFileViewerSelecting([selected.url]) }
        else if !NSWorkspace.shared.open(current) { error = "Finder couldn't open this folder. The volume may have disconnected." }
    }
}

struct FileExplorer: View {
    @StateObject private var model: ExplorerModel
    @ObservedObject private var pins: PinnedLocations
    @Environment(\.dismiss) private var dismiss
    private let accent = StationTheme.accent
    private let dim = StationTheme.muted
    @AppStorage("stationAppearance") private var appearance = "dark"
    @State private var grid = true
    init(request: ExplorerRequest) {
        _model = StateObject(wrappedValue: ExplorerModel(request))
        pins = request.simulation ? .simulation : .shared
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                Image(systemName: "folder.badge.gearshape").font(.system(size: 26)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.request.snapshot == nil ? "VOLUME EXPLORER" : "SNAPSHOT EXPLORER").font(.system(size: 10, design: .monospaced)).tracking(3).foregroundStyle(accent)
                    Text(model.request.drive.name).font(.system(size: 22, weight: .semibold))
                }
                Spacer()
                AppearanceButton()
                Text(model.request.simulation ? "SIMULATION" : model.request.drive.internalVolume ? "INTERNAL STORAGE" : "EXTERNAL STORAGE").font(.system(size: 10, design: .monospaced)).foregroundStyle(dim)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            if let summary = model.request.snapshot?.document.summary {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("SAVED \(summary.capturedAt.formatted(date: .abbreviated, time: .shortened)) · \(summary.scope)")
                    Spacer()
                    Text("\(summary.itemCount.formatted()) items · \(summary.thumbnailCount) thumbnails")
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(accent).padding(.horizontal, 24).padding(.vertical, 10).background(accent.opacity(0.06))
                if summary.partial || summary.thumbnailLimitReached || summary.skippedCount > 0 {
                    Text("\(summary.partial ? "Partial catalog · " : "")\(summary.skippedCount) unreadable/cross-volume locations skipped\(summary.thumbnailLimitReached ? " · Thumbnail budget reached" : ""). Hidden files, package contents and cloud-only items are excluded.")
                        .font(.system(size: 10)).foregroundStyle(StationTheme.amber).padding(.horizontal, 24).padding(.bottom, 8)
                }
            }
            Divider()
            HStack(spacing: 0) {
                locations
                VStack(spacing: 0) {
                    toolbar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(model.crumbs, id: \.self) { url in
                                Button(url == model.request.root ? model.request.drive.name : url.lastPathComponent) { model.navigate(url) }.buttonStyle(.plain).foregroundStyle(url == model.current ? accent : dim)
                                    .contextMenu { pinAction(url) }
                                if url != model.current { Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(dim) }
                            }
                        }.font(.system(size: 11, design: .monospaced)).padding(.horizontal, 18).padding(.vertical, 12)
                    }
                    Divider()
                    content
                    Divider()
                    HStack {
                        Text(model.loading ? "Reading folder…" : "\(model.visible.count) items\(model.search.isEmpty ? "" : " matching search")")
                        Spacer()
                        Text(model.notice ?? (model.request.snapshot == nil ? "On-demand access · no background indexing" : "Cached on this Mac · source drive is not accessed"))
                    }.font(.system(size: 10, design: .monospaced)).foregroundStyle(dim).padding(14)
                }
            }
        }.frame(width: 1020, height: 660).background(StationTheme.background).foregroundStyle(StationTheme.text)
            .preferredColorScheme(appearance == "light" ? .light : .dark)
            .task { await model.load() }
            .onChange(of: model.showHidden) { _, _ in Task { await model.load() } }
            .alert("Pinned locations", isPresented: Binding(get: { pins.error != nil }, set: { if !$0 { pins.error = nil } })) {
                Button("OK") { pins.error = nil }
            } message: { Text(pins.error ?? "") }
    }
    private var locations: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LOCATIONS").font(.system(size: 10, design: .monospaced)).tracking(2).foregroundStyle(dim)
            if model.request.snapshot == nil {
              VStack(alignment: .leading, spacing: 10) {
                Label("PINNED", systemImage: "pin.fill").font(.system(size: 9, design: .monospaced)).tracking(1.5).foregroundStyle(dim)
                if pins.locations(for: model.request.drive.id).isEmpty {
                    Text("Right-click a folder\nto pin it here.").font(.system(size: 11)).foregroundStyle(dim).lineSpacing(3)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(pins.locations(for: model.request.drive.id)) { pin in
                                PinnedLocationRow(pin: pin, pins: pins, model: model, accent: accent)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: min(170, CGFloat(pins.locations(for: model.request.drive.id).count * 36 - 4)))
                }
            }
            Divider().overlay(StationTheme.edge)
            }
            Button { model.navigate(model.request.root) } label: { Label(model.request.snapshot == nil ? "Volume root" : "Snapshot root", systemImage: model.request.drive.internalVolume ? "internaldrive" : "externaldrive") }
                .contextMenu { pinAction(model.request.root) }
            if model.request.drive.internalVolume && !model.request.simulation && model.request.snapshot == nil {
                Button { model.navigate(FileManager.default.homeDirectoryForCurrentUser) } label: { Label("Home folder", systemImage: "house") }
                    .contextMenu { pinAction(FileManager.default.homeDirectoryForCurrentUser) }
                Button { model.navigate(URL(fileURLWithPath: "/Applications")) } label: { Label("Applications", systemImage: "square.grid.2x2") }
                    .contextMenu { pinAction(URL(fileURLWithPath: "/Applications")) }
            }
            Spacer()
            Image(systemName: "scope").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(accent)
            Text("Explore your orbit.").font(.system(size: 14, weight: .medium))
            Text(model.request.snapshot == nil ? "Double-click a folder to explore. Double-click a file to open its default app." : "Browse saved folders and thumbnails, even with the drive disconnected. Originals stay on the drive.").font(.system(size: 11)).foregroundStyle(dim).lineSpacing(4)
            if model.request.simulation { Text("All files here are samples.").font(.system(size: 11)).foregroundStyle(.orange) }
        }.buttonStyle(.plain).foregroundStyle(accent).padding(22).frame(width: 190).frame(maxHeight: .infinity).background(StationTheme.sidebar)
    }
    private func pinAction(_ url: URL) -> some View {
        Button(pins.contains(url, request: model.request) ? "Location Already Pinned" : "Pin Location") {
            pins.pin(url, request: model.request)
        }.disabled(model.request.snapshot != nil || pins.contains(url, request: model.request))
    }
    private var toolbar: some View {
        HStack(spacing: 11) {
            Button { model.goBack() } label: { Image(systemName: "chevron.left") }.disabled(model.back.isEmpty).help("Back")
            Button { model.goForward() } label: { Image(systemName: "chevron.right") }.disabled(model.forward.isEmpty).help("Forward")
            Button { model.navigate(model.current.deletingLastPathComponent()) } label: { Image(systemName: "arrow.up") }.disabled(model.current == model.request.root).help("Enclosing folder")
            Button { Task { await model.load() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh this folder").disabled(model.loading)
            TextField(model.request.snapshot == nil ? "Search this folder" : "Search entire snapshot (up to 500 results)", text: $model.search).textFieldStyle(.roundedBorder).frame(minWidth: 100)
            Menu {
                Picker("Sort", selection: $model.sort) { ForEach(["Name", "Size", "Modified"], id: \.self) { Text($0) } }
                Toggle("Show hidden files", isOn: $model.showHidden).disabled(model.request.snapshot != nil)
            } label: { Image(systemName: "slider.horizontal.3") }.help("Sort and visibility")
            if model.request.snapshot != nil {
                Button { grid.toggle() } label: { Image(systemName: grid ? "list.bullet" : "square.grid.2x2") }.help("Switch thumbnail/list view")
            } else { Button("Open in Finder") { model.finder() } }
        }.controlSize(.small).padding(14)
    }
    @ViewBuilder private var content: some View {
        if model.loading { Spacer(); ProgressView("Reading folder"); Spacer() }
        else if let error = model.error {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.folder").font(.system(size: 35)).foregroundStyle(.orange)
                Text(error).multilineTextAlignment(.center).foregroundStyle(dim)
                HStack { Button("Try again") { Task { await model.load() } }; Button("Open in Finder") { model.finder() } }
            }.padding(30)
            Spacer()
        } else if model.visible.isEmpty {
            Spacer(); Image(systemName: "folder").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(accent)
            Text(model.search.isEmpty ? "This folder is empty." : "No matching items in this folder.").foregroundStyle(dim).padding(); Spacer()
        } else if model.request.snapshot != nil && grid {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(model.visible) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            SnapshotThumbnail(entry: entry).frame(height: 94).frame(maxWidth: .infinity)
                                .background(accent.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(entry.name).font(.system(size: 11, weight: .medium)).lineLimit(2).frame(height: 30, alignment: .topLeading)
                            if !model.search.isEmpty { Text(entry.savedPath ?? "").font(.system(size: 9)).foregroundStyle(dim).lineLimit(2) }
                            Text(entry.browsable ? "Folder" : entry.size.map(Drive.bytes) ?? entry.kind).font(.system(size: 10, design: .monospaced)).foregroundStyle(dim)
                        }.padding(10).background(model.selection == entry.id ? accent.opacity(0.12) : StationTheme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
                            .onTapGesture(count: 2) { model.open(entry) }.onTapGesture { model.selection = entry.id }
                            .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton).accessibilityAction { model.open(entry) }
                            .contextMenu { Button(entry.browsable ? "Explore saved folder" : "View saved details") { model.open(entry) } }
                    }
                }.padding(16)
            }
        } else {
            VStack(spacing: 0) {
                HStack { Text("NAME"); Spacer(); Text("KIND").frame(width: 92, alignment: .leading); Text("SIZE").frame(width: 80, alignment: .trailing); Text("MODIFIED").frame(width: 100, alignment: .trailing) }
                    .font(.system(size: 9, design: .monospaced)).tracking(1).foregroundStyle(dim).padding(.horizontal, 18).padding(.vertical, 12)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.visible) { entry in
                            HStack(spacing: 12) {
                                SnapshotThumbnail(entry: entry).frame(width: 24, height: 24)
                                Text(entry.name).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 5)
                                Text(entry.kind).foregroundStyle(dim).frame(width: 92, alignment: .leading)
                                Text(entry.directory ? "—" : entry.size.map(Drive.bytes) ?? "—").foregroundStyle(dim).frame(width: 80, alignment: .trailing)
                                Text(entry.modified?.formatted(date: .abbreviated, time: .omitted) ?? "—").foregroundStyle(dim).frame(width: 100, alignment: .trailing)
                            }.font(.system(size: 11)).padding(.horizontal, 14).padding(.vertical, 11)
                                .background(model.selection == entry.id ? accent.opacity(0.12) : StationTheme.panel)
                                .clipShape(RoundedRectangle(cornerRadius: 4)).contentShape(Rectangle())
                                .onTapGesture(count: 2) { model.open(entry) }
                                .onTapGesture { model.selection = entry.id }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { model.open(entry) }
                                .contextMenu {
                                    Button(entry.browsable ? "Explore folder" : "Open") { model.open(entry) }
                                    if entry.browsable { pinAction(entry.url) }
                                    if model.request.snapshot == nil { Button("Reveal in Finder") { model.selection = entry.id; model.finder(reveal: true) } }
                                }
                        }
                    }.padding(.horizontal, 8)
                }
                if let selected = model.selected {
                    HStack {
                        Text(selected.name).lineLimit(1).truncationMode(.middle).foregroundStyle(accent)
                        Spacer()
                        Button(selected.browsable ? "Explore folder" : "Open file") { model.open(selected) }
                        if model.request.snapshot == nil { Button("Reveal in Finder") { model.finder(reveal: true) } }
                    }.font(.system(size: 11)).padding(12).background(accent.opacity(0.035))
                }
            }
        }
    }
}

private struct SnapshotThumbnail: View {
    let entry: FileEntry
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: entry.symbol).resizable().scaledToFit().padding(5).foregroundStyle(StationTheme.accent).frame(maxWidth: 46, maxHeight: 46) }
        }.task(id: entry.cachedThumbnail) {
            image = nil
            guard let url = entry.cachedThumbnail else { return }
            let bytes = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            if !Task.isCancelled, let bytes { image = NSImage(data: bytes) }
        }
    }
}

private struct PinnedLocationRow: View {
    let pin: PinnedLocation
    @ObservedObject var pins: PinnedLocations
    @ObservedObject var model: ExplorerModel
    let accent: Color
    @State private var targeted = false
    var body: some View {
        Button { model.navigate(pin.url(relativeTo: model.request.root)) } label: {
            HStack(spacing: 7) {
                Image(systemName: "folder").font(.system(size: 11))
                Text(pin.name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "line.3.horizontal").font(.system(size: 8)).opacity(0.45)
            }.font(.system(size: 11)).frame(height: 32).padding(.horizontal, 5)
                .background(accent.opacity(targeted ? 0.18 : model.current.standardizedFileURL.path == pin.url(relativeTo: model.request.root).standardizedFileURL.path ? 0.08 : 0))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(accent.opacity(targeted ? 0.6 : 0)))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .help("\(pin.name) · Drag to reorder. Right-click to remove.")
            .draggable("drive-station-pin:\(pin.id.uuidString)")
            .dropDestination(for: String.self) { values, _ in
                guard values.count == 1, let value = values.first, value.hasPrefix("drive-station-pin:"), let id = UUID(uuidString: String(value.dropFirst("drive-station-pin:".count))) else { return false }
                return pins.move(id, to: pin.id, volumeID: model.request.drive.id)
            } isTargeted: { targeted = $0 }
            .contextMenu {
                Button("Open Pinned Location") { model.navigate(pin.url(relativeTo: model.request.root)) }
                Divider()
                Button("Remove Pin") { pins.remove(pin.id) }
            }
    }
}
