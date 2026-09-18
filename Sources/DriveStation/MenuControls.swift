import SwiftUI
import AppKit

struct MenuControls: View {
    @ObservedObject var station: Station
    @ObservedObject var shortcut: GlobalShortcut
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filteredDrives: [Drive] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return station.drives.filter {
            query.isEmpty || "\($0.name) \($0.connection) \($0.state.rawValue)".localizedStandardContains(query)
        }
    }
    private var connectedCount: Int { station.drives.filter { $0.state != .offline }.count }

    var body: some View {
        VStack(spacing: 18) {
            header
            searchField
            overview
            VStack(spacing: 10) {
                HStack {
                    Text(search.isEmpty ? "Your drives" : "Search results")
                        .foregroundStyle(StationTheme.muted)
                    Spacer()
                    Text("\(filteredDrives.count)")
                        .monospacedDigit().foregroundStyle(StationTheme.muted)
                }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 4)
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if filteredDrives.isEmpty { emptyState }
                        ForEach(filteredDrives) { drive in driveCard(drive) }
                    }
                }
                .frame(height: filteredDrives.isEmpty ? 105 : min(CGFloat(filteredDrives.count) * 156 - 10, 300))
            }
            if let progress = station.snapshotProgress {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.system(size: 11)).lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Cancel") { station.cancelSnapshot() }
                        .buttonStyle(.plain).foregroundStyle(StationTheme.accent)
                }
                .padding(12).background(StationTheme.panel, in: RoundedRectangle(cornerRadius: 14))
            }
            if let error = station.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(StationTheme.amber)
                    Text(error).font(.system(size: 11)).lineLimit(3).help(error)
                    Spacer(minLength: 0)
                    Button { station.error = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss error")
                }.padding(12).background(StationTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            footer
        }
        .padding(18)
        .frame(width: 400)
        .background(StationTheme.background)
        .foregroundStyle(StationTheme.text)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { showCommandDeck() } label: {
                HStack(spacing: 9) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .foregroundStyle(StationTheme.accent)
                    Text("Open command deck").fontWeight(.semibold)
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(StationTheme.muted)
                }.padding(.horizontal, 15).padding(.vertical, 12)
            }
            .buttonStyle(MenuPillStyle())
            .help(shortcut.registered ? "Open command deck · \(shortcut.shortcut.display)" : "Open command deck")
            Spacer(minLength: 0)
            AppearanceButton()
                .frame(width: 38, height: 38)
                .background(StationTheme.panel, in: Circle())
                .overlay(Circle().stroke(StationTheme.edge))
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(StationTheme.muted)
            TextField("Search drives", text: $search)
                .textFieldStyle(.plain).accessibilityLabel("Search drives")
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(StationTheme.muted)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
        .background(StationTheme.panel, in: Capsule())
        .overlay(Capsule().stroke(StationTheme.edge))
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 13) {
                Image(systemName: connectedCount > 0 ? "externaldrive.fill.badge.checkmark" : "externaldrive.badge.plus")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(StationTheme.accent)
                    .frame(width: 54, height: 54)
                    .background(StationTheme.accent.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(station.simulation ? "Simulation fleet" : connectedCount == 0 ? "Ready for your drives" : "\(connectedCount) drive\(connectedCount == 1 ? "" : "s") connected")
                        .font(.system(size: 21, weight: .semibold))
                    Text(station.simulation ? "Sample drives · no disk operations" : "\(station.drives.filter { $0.state == .online }.count) online · \(station.drives.filter { $0.state == .standby }.count) on standby")
                        .font(.system(size: 12)).foregroundStyle(StationTheme.muted)
                }
            }
            Button { Task { await station.refresh() } } label: {
                HStack(spacing: 8) {
                    if station.busy { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "arrow.clockwise") }
                    Text(station.busy ? "Working…" : "Scan drives").fontWeight(.semibold)
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(MenuPillStyle(prominent: true))
            .disabled(station.busy)
            .keyboardShortcut("r")
        }.padding(16).background(StationTheme.panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private func driveCard(_ drive: Drive) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: drive.internalVolume ? "internaldrive.fill" : "externaldrive.fill")
                    .font(.system(size: 20)).foregroundStyle(stateColor(drive))
                    .frame(width: 38, height: 38)
                    .background(stateColor(drive).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(drive.name).font(.system(size: 14, weight: .semibold)).lineLimit(1).help(drive.name)
                    Text("\(drive.connection) · \(drive.format)")
                        .font(.system(size: 10)).foregroundStyle(StationTheme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(drive.state.rawValue.capitalized)
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(stateColor(drive))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(stateColor(drive).opacity(0.1), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { geometry in
                    Capsule().fill(StationTheme.track)
                        .overlay(alignment: .leading) {
                            Capsule().fill(stateColor(drive))
                                .frame(width: geometry.size.width * drive.usedFraction)
                        }
                }.frame(height: 4)
                    .accessibilityLabel("Used space on \(drive.name)")
                    .accessibilityValue(drive.free == nil ? "Unknown" : "\(Int(drive.usedFraction * 100)) percent")
                Text(capacityLabel(drive))
                    .font(.system(size: 10)).foregroundStyle(StationTheme.muted).lineLimit(1)
            }
            HStack(spacing: 10) {
                if drive.state == .offline {
                    Button { browseSnapshot(drive) } label: { Label("Saved snapshot", systemImage: "photo.stack") }
                        .disabled(station.simulation || station.snapshots[drive.id] == nil || station.busy)
                } else {
                    Button { explore(drive) } label: {
                        Label(drive.state == .standby ? "Wake & explore" : "Explore", systemImage: "folder")
                    }.disabled(station.busy)
                }
                Spacer(minLength: 0)
                if station.isSnapshotExcluded(drive) {
                    Image(systemName: "camera.slash").foregroundStyle(StationTheme.muted)
                        .help("Snapshots are off for this drive").accessibilityLabel("Snapshots off")
                }
                if !drive.internalVolume {
                    Button { Task { await station.eject(drive) } } label: { Image(systemName: "eject") }
                        .disabled(!station.canEject(drive)).help("Eject \(drive.name)")
                        .accessibilityLabel("Eject \(drive.name)")
                }
                Menu { driveActions(drive) } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Options for \(drive.name)").accessibilityLabel("Options for \(drive.name)")
            }
            .font(.system(size: 11, weight: .medium)).buttonStyle(.plain).foregroundStyle(StationTheme.accent)
        }
        .padding(14)
        .background(StationTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(StationTheme.edge.opacity(0.7)))
    }

    @ViewBuilder private func driveActions(_ drive: Drive) -> some View {
        Button("Explore in Drive Station") { explore(drive) }.disabled(drive.state == .offline || station.busy)
        Button("Open in Finder") { Task { await station.act(drive, open: true) } }.disabled(drive.state == .offline || station.busy)
        if !station.simulation, station.snapshots[drive.id] != nil {
            Button("Browse Saved Snapshot") { browseSnapshot(drive) }.disabled(station.busy)
        }
        Divider()
        Toggle("Do not snapshot", isOn: Binding(
            get: { station.isSnapshotExcluded(drive) },
            set: { station.setSnapshotExcluded($0, for: drive) }
        )).disabled(station.busy)
        if !drive.internalVolume {
            Button("Standby") { Task { await station.act(drive, open: false) } }
                .disabled(!drive.canStandby || station.busy || station.isSnapshotting(drive))
            Button("Eject", systemImage: "eject") { Task { await station.eject(drive) } }
                .disabled(!station.canEject(drive))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: search.isEmpty ? "externaldrive.badge.plus" : "magnifyingglass")
                .font(.system(size: 25)).foregroundStyle(StationTheme.accent)
            Text(search.isEmpty ? "Connect a drive to get started" : "No matching drives")
                .font(.system(size: 13, weight: .medium))
            Text(search.isEmpty ? "Scan to discover connected volumes." : "Try a drive name, connection, or status.")
                .font(.system(size: 11)).foregroundStyle(StationTheme.muted)
        }.frame(maxWidth: .infinity).padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            if station.simulation { Text("Simulation mode") }
            else if let date = station.lastScan {
                Text("Scanned \(date.formatted(date: .omitted, time: .shortened))")
            } else { Text("Scan to update drive status") }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).keyboardShortcut("q").help("Quit Drive Station")
        }.font(.system(size: 10)).foregroundStyle(StationTheme.muted).padding(.horizontal, 4)
    }

    private func stateColor(_ drive: Drive) -> Color {
        drive.state == .online ? StationTheme.accent : drive.state == .standby ? StationTheme.amber : StationTheme.muted
    }

    private func capacityLabel(_ drive: Drive) -> String {
        let prefix = drive.state == .offline ? "Last known · " : ""
        guard let free = drive.free else { return "\(prefix)\(Drive.bytes(drive.capacity)) capacity · free space unknown" }
        return "\(prefix)\(Drive.bytes(free)) free of \(Drive.bytes(drive.capacity))"
    }

    private func showCommandDeck() {
        dismiss()
        openWindow(id: "station")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.title == "Drive Station" }?.deminiaturize(nil)
    }

    private func explore(_ drive: Drive) {
        showCommandDeck()
        Task { await station.explore(drive) }
    }

    private func browseSnapshot(_ drive: Drive) {
        showCommandDeck()
        Task { await station.browseSnapshot(drive) }
    }
}

private struct MenuPillStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? StationTheme.onAccent : StationTheme.text)
            .background(prominent ? StationTheme.accent : StationTheme.panel, in: Capsule())
            .overlay(Capsule().stroke(prominent ? .clear : StationTheme.edge))
            .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
