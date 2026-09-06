import SwiftUI

private let cyan = StationTheme.accent
private let muted = StationTheme.muted
private let amber = StationTheme.amber
private let panel = StationTheme.panel
private let edge = StationTheme.edge

private extension DriveState {
    var color: Color { self == .online ? cyan : self == .standby ? amber : muted }
    var symbol: String { self == .online ? "bolt.fill" : self == .standby ? "moon.zzz.fill" : "link.badge.plus" }
}

private struct Micro: View {
    var text: String
    var color: Color = muted
    var body: some View { Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(color) }
}

private struct DeckButton: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 15).padding(.vertical, 11)
            .foregroundStyle(prominent ? StationTheme.onAccent : cyan)
            .background(prominent ? cyan.opacity(configuration.isPressed ? 0.65 : 1) : cyan.opacity(configuration.isPressed ? 0.15 : 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(cyan.opacity(prominent ? 0 : 0.25)))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(22).background(panel).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(edge)) }
}

struct CommandDeck: View {
    @ObservedObject var station: Station
    @State private var page = "Command deck"
    @State private var filter = "All volumes"
    @State private var search = ""
    @AppStorage("stationAppearance") private var appearance = "dark"
    @AppStorage("automaticSnapshots") private var automaticSnapshots = true
    @AppStorage("launchInMenuBar") private var launchInMenuBar = false
    @AppStorage("orbitDoubleClickAction") private var orbitDoubleClickAction = "explore"
    @State private var snapshotSearch = ""
    var filtered: [Drive] {
        station.drives.filter { (filter == "All volumes" || $0.state.rawValue == filter.lowercased()) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if station.simulation { simulationBanner }
                        if let progress = station.snapshotProgress {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text(progress).font(.system(size: 12, design: .monospaced))
                                Spacer()
                                Button("Cancel capture") { station.cancelSnapshot() }
                            }.padding(14).background(cyan.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        if page == "Activity log" { activity }
                        else if page == "Snapshot library" { snapshotLibrary }
                        else if page == "Station settings" { settings }
                        else {
                            title
                            if page == "Command deck" {
                                statistics
                                HStack(alignment: .top, spacing: 18) {
                                    topology.frame(maxWidth: .infinity)
                                    inspector.frame(width: 278)
                                }
                            }
                            fleet
                        }
                    }.padding(28)
                }
                footer
            }
        }
        .background(StationTheme.background)
        .foregroundStyle(StationTheme.text)
        .frame(minWidth: 1100, minHeight: 740)
        .sheet(item: $station.explorerRequest) { request in FileExplorer(request: request) }
        .alert("Operation needs attention", isPresented: Binding(get: { station.error != nil }, set: { if !$0 { station.error = nil } })) {
            Button("OK") { station.error = nil }
        } message: { Text(station.error ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "hexagon.fill").font(.system(size: 31)).foregroundStyle(cyan)
                    .overlay(Image(systemName: "externaldrive.fill").font(.system(size: 15)).foregroundStyle(panel))
                VStack(alignment: .leading, spacing: 3) {
                    Text("DRIVE").tracking(4).font(.system(size: 16, weight: .heavy))
                    Text("STATION").tracking(4).font(.system(size: 10, weight: .medium)).foregroundStyle(cyan)
                }
            }.padding(.top, 49).padding(.bottom, 47)
            Micro(text: "NAVIGATION").padding(.bottom, 18)
            ForEach([("Command deck", "square.grid.2x2"), ("Drive registry", "externaldrive"), ("Snapshot library", "photo.stack"), ("Activity log", "waveform.path.ecg"), ("Station settings", "slider.horizontal.3")], id: \.0) { item in
                Button { page = item.0 } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.1).frame(width: 17)
                        Text(item.0).font(.system(size: 12, weight: .medium))
                        Spacer()
                        if page == item.0 { Rectangle().fill(cyan).frame(width: 3, height: 15) }
                    }.foregroundStyle(page == item.0 ? cyan : muted).padding(.vertical, 14).padding(.horizontal, 12)
                        .background(page == item.0 ? cyan.opacity(0.075) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).padding(.horizontal, -12).padding(.bottom, 5)
            }
            Spacer(minLength: 40)
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: "moon.stars").font(.system(size: 23)).foregroundStyle(cyan)
                Text("Quiet by design.").font(.system(size: 14, weight: .semibold))
                Text("Your drives. On your terms.\nNo recurring scans.").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(5)
                Rectangle().fill(edge).frame(height: 1)
                HStack { Circle().fill(cyan).frame(width: 5, height: 5); Micro(text: "LOCAL CONTROL", color: cyan) }
            }.padding(16).background(cyan.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(edge))
            Micro(text: "DS / MACOS     V.03").padding(.top, 24).padding(.bottom, 23)
        }.padding(.horizontal, 26).frame(width: 220).background(StationTheme.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(edge).frame(width: 1) }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Micro(text: "MISSION CONTROL")
            Text("/").foregroundStyle(muted.opacity(0.4))
            Micro(text: page.uppercased(), color: StationTheme.text.opacity(0.8))
            Spacer()
            Button { NSApp.keyWindow?.close() } label: {
                Label("Hide to Menu Bar", systemImage: "menubar.rectangle")
            }.buttonStyle(.plain).help("Close the command deck; Drive Station stays available from the menu bar")
            AppearanceButton().padding(.trailing, 12)
            Circle().fill(station.simulation ? amber : cyan).frame(width: 5, height: 5)
            Micro(text: station.simulation ? "SIMULATION" : "LOCAL SYSTEM", color: station.simulation ? amber : cyan)
            Text(Date(), style: .date).font(.system(size: 10, design: .monospaced)).foregroundStyle(muted).padding(.leading, 17)
        }.padding(.horizontal, 29).padding(.top, 20).padding(.bottom, 20).overlay(alignment: .bottom) { Rectangle().fill(edge).frame(height: 1) }
    }
    private var title: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Micro(text: page == "Command deck" ? "STORAGE OPERATIONS / 01" : "PERSISTENT MEMORY / 02", color: cyan)
                Text(page == "Command deck" ? "Your storage. In orbit." : "Every drive, remembered.").font(.system(size: 30, weight: .semibold)).tracking(-0.8)
                Text("Keep the essentials online. Let everything else rest.").font(.system(size: 12)).foregroundStyle(muted)
            }
            Spacer()
            Button { Task { await station.refresh() } } label: {
                Label(station.busy ? "WORKING…" : "SCAN DRIVES", systemImage: "arrow.triangle.2.circlepath")
            }.buttonStyle(DeckButton(prominent: true)).disabled(station.busy).keyboardShortcut("r")
        }
    }
    private var simulationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
            Text("SIMULATION").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
            Text("Sample drives. Controls are simulated; your disks are unaffected.").font(.system(size: 11))
            Spacer()
            Button("Exit simulation") { station.setSimulation(false) }.buttonStyle(.plain).underline().disabled(station.busy)
        }.foregroundStyle(amber).padding(12).background(amber.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
    private var statistics: some View {
        HStack(spacing: 14) {
            stat("REGISTERED", value: String(format: "%02d", station.drives.count), suffix: "volumes", symbol: "square.stack.3d.up", color: StationTheme.text)
            stat("ONLINE", value: String(format: "%02d", station.drives.filter { $0.state == .online }.count), suffix: "ready to access", symbol: "bolt", color: cyan)
            stat("STANDBY", value: String(format: "%02d", station.drives.filter { $0.state == .standby }.count), suffix: "safely unmounted", symbol: "moon.zzz", color: amber)
            stat("OFFLINE", value: String(format: "%02d", station.drives.filter { $0.state == .offline }.count), suffix: "remembered", symbol: "link", color: muted)
        }
    }
    private func stat(_ label: String, value: String, suffix: String, symbol: String, color: Color) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Micro(text: label); Spacer(); Image(systemName: symbol).foregroundStyle(color).font(.system(size: 14)) }
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(value).font(.system(size: 29, weight: .light, design: .monospaced)).foregroundStyle(color)
                    Text(suffix).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var topology: some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                HStack { Micro(text: "ORBITAL MAP", color: StationTheme.text.opacity(0.8)); Spacer(); Micro(text: "CONNECTED STORAGE") }
                OrbitMap(
                    drives: station.drives,
                    selectedID: station.selected?.id,
                    select: { station.selectedID = $0 },
                    activate: { drive in
                        Task {
                            if orbitDoubleClickAction == "finder" { await station.act(drive, open: true) }
                            else { await station.explore(drive) }
                        }
                    },
                    explore: { drive in Task { await station.explore(drive) } },
                    finder: { drive in Task { await station.act(drive, open: true) } }
                )
                    .frame(height: 287)
                HStack(spacing: 18) {
                    ForEach([DriveState.online, .standby, .offline], id: \.self) { state in
                        HStack(spacing: 5) { Circle().fill(state.color).frame(width: 4, height: 4); Micro(text: state.rawValue.uppercased()) }
                    }
                    Spacer()
                    Micro(text: "SELECT A NODE", color: cyan)
                }
            }
        }
    }
    private var inspector: some View {
        Panel {
            VStack(alignment: .leading, spacing: 15) {
                HStack { Micro(text: "VOLUME TELEMETRY"); Spacer(); Image(systemName: "scope").foregroundStyle(cyan) }
                if let drive = station.selected {
                    HStack(spacing: 13) {
                        CapacityRing(drive: drive).frame(width: 66, height: 66)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(drive.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                            Micro(text: drive.state.rawValue.uppercased(), color: drive.state.color)
                        }
                    }.padding(.vertical, 2)
                    Rectangle().fill(edge).frame(height: 1)
                    detail("Capacity", Drive.bytes(drive.capacity))
                    detail("Available*", drive.free.map(Drive.bytes) ?? "Unknown")
                    detail("Interface", drive.connection)
                    detail("Filesystem", drive.format)
                    Text("*Last scanned. APFS space is shared within its container.").font(.system(size: 9)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button { Task { await station.explore(drive) } } label: {
                            Label(drive.state == .standby ? "WAKE & EXPLORE" : "EXPLORE", systemImage: "folder").frame(maxWidth: .infinity)
                        }.buttonStyle(DeckButton(prominent: true))
                        volumeOptions(drive)
                    }.disabled(drive.state == .offline || station.busy)
                } else {
                    Image(systemName: "externaldrive.badge.plus").font(.system(size: 45, weight: .ultraLight)).foregroundStyle(cyan).padding(.top, 27)
                    Text("Awaiting first contact.").font(.system(size: 18, weight: .medium))
                    Text("Connect an external drive and scan to bring it into your station.").font(.system(size: 12)).foregroundStyle(muted).lineSpacing(4)
                    Button("EXPLORE SIMULATION") { station.setSimulation(true) }.buttonStyle(DeckButton()).disabled(station.busy)
                    Spacer()
                }
            }.frame(height: 317, alignment: .top)
        }
    }
    private func detail(_ key: String, _ value: String) -> some View {
        HStack { Text(key).foregroundStyle(muted); Spacer(); Text(value) }.font(.system(size: 11, design: .monospaced))
    }
    private var fleet: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("Drive fleet").font(.system(size: 18, weight: .semibold))
                Micro(text: "\(station.drives.count) VOLUMES").padding(.leading, 5)
                Spacer()
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(muted); TextField("Find a drive", text: $search).textFieldStyle(.plain) }
                    .font(.system(size: 11)).padding(9).frame(width: 150).background(panel).clipShape(RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(edge))
                Picker("Filter volumes", selection: $filter) { ForEach(["All volumes", "Online", "Standby", "Offline"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 120)
            }
            if filtered.isEmpty {
                Panel {
                    HStack(spacing: 20) {
                        Image(systemName: "externaldrive.connected.to.line.below").font(.system(size: 30, weight: .light)).foregroundStyle(cyan)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(station.drives.isEmpty ? "Your next drive belongs here." : "No matching volumes.").font(.system(size: 15, weight: .medium))
                            Text(station.drives.isEmpty ? "Connect a drive and select Scan Drives. The station will remember it, even after you disconnect." : "Try a different filter or search.").font(.system(size: 12)).foregroundStyle(muted)
                        }
                        Spacer()
                    }.padding(.vertical, 15)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 18)], spacing: 18) {
                    ForEach(filtered) { drive in driveCard(drive) }
                }
            }
        }
    }
    private func driveCard(_ drive: Drive) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: drive.internalVolume ? "internaldrive.fill" : "externaldrive.fill").font(.system(size: 24)).foregroundStyle(drive.state.color)
                    Spacer()
                    Image(systemName: drive.state.symbol).font(.system(size: 9)).foregroundStyle(drive.state.color)
                    Micro(text: drive.state.rawValue.uppercased(), color: drive.state.color)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(drive.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Micro(text: "\(drive.connection.uppercased()) / \(drive.format)")
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(StationTheme.track)
                            Capsule().fill(drive.state.color.opacity(0.7)).frame(width: max(0, geo.size.width * drive.usedFraction))
                        }
                    }.frame(height: 3)
                    HStack { Text(drive.free.map { "\(Drive.bytes(max(0, drive.capacity - $0))) used" } ?? "Usage unknown"); Spacer(); Text(Drive.bytes(drive.capacity)) }.font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                }
                HStack {
                    if drive.state == .offline {
                        Text("Reconnect to access").font(.system(size: 11)).foregroundStyle(muted)
                        Spacer()
                        Button { station.forget(drive) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).help("Forget this disconnected volume; files are not deleted").disabled(station.busy)
                    } else {
                        Button { Task { await station.explore(drive) } } label: { Label(drive.state == .standby ? "WAKE & EXPLORE" : "EXPLORE", systemImage: "folder") }.buttonStyle(DeckButton())
                        Spacer(minLength: 3)
                        volumeOptions(drive)
                        if drive.canStandby {
                            Button { Task { await station.act(drive, open: false) } } label: { Image(systemName: "moon.zzz").foregroundStyle(amber).padding(10) }.buttonStyle(.plain).help("Standby: safely unmount this volume").disabled(station.isSnapshotting(drive))
                        }
                    }
                }.frame(height: 34).disabled(station.busy)
                if !station.simulation, let summary = station.snapshots[drive.id] {
                    Button { Task { await station.browseSnapshot(drive) } } label: {
                        HStack {
                            Image(systemName: "photo.stack")
                            Text("BROWSE SNAPSHOT")
                            Spacer()
                            Text(summary.capturedAt, style: .date).foregroundStyle(muted)
                        }.font(.system(size: 10, design: .monospaced))
                    }.buttonStyle(.plain).foregroundStyle(cyan).disabled(station.busy)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 276)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { station.selectedID = drive.id }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(station.selected?.id == drive.id ? cyan.opacity(0.65) : .clear, lineWidth: 1.5))
    }
    private func volumeOptions(_ drive: Drive) -> some View {
        Menu {
            Button("Explore in Drive Station") { Task { await station.explore(drive) } }.disabled(drive.state == .offline)
            Button("Open in Finder") { Task { await station.act(drive, open: true) } }.disabled(drive.state == .offline)
            if !station.simulation {
                Divider()
                if station.snapshots[drive.id] != nil {
                    Button("Browse Saved Snapshot") { Task { await station.browseSnapshot(drive) } }
                }
                Button(drive.internalVolume ? "Capture Home Folder Snapshot" : station.snapshots[drive.id] == nil ? "Capture Snapshot" : "Refresh Snapshot") {
                    Task { await station.captureSnapshot(drive) }
                }.disabled(drive.state == .offline || station.snapshotProgress != nil)
            }
            if drive.canStandby {
                Divider()
                Button("Standby volume") { Task { await station.act(drive, open: false) } }.disabled(station.isSnapshotting(drive))
            }
        } label: { Image(systemName: "ellipsis.circle").foregroundStyle(cyan) }
            .menuStyle(.borderlessButton).fixedSize().help("Volume options").disabled(station.busy)
    }
    private var snapshotLibrary: some View {
        VStack(alignment: .leading, spacing: 22) {
            Micro(text: "OFFLINE MEMORY / SNAPSHOTS", color: cyan)
            Text("See what's on board.").font(.system(size: 30, weight: .semibold))
            Text("Browse saved folders and thumbnails without reconnecting a drive.").foregroundStyle(muted)
            TextField("Find a saved drive", text: $snapshotSearch).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
            if station.simulation {
                Text("Snapshots use real volumes. Exit simulation to capture or browse your saved drives.").foregroundStyle(amber)
            } else if station.snapshots.isEmpty {
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "photo.stack").font(.system(size: 36, weight: .light)).foregroundStyle(cyan)
                        Text("A memory for every drive.").font(.headline)
                        Text("The first snapshot is captured when a new external volume is discovered online. You can also choose Capture Snapshot in a volume's options menu. Internal storage uses an explicit Home Folder capture.").foregroundStyle(muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                let summaries = station.snapshots.values.filter { snapshotSearch.isEmpty || $0.volumeName.localizedCaseInsensitiveContains(snapshotSearch) }.sorted { $0.capturedAt > $1.capturedAt }
                if summaries.isEmpty { Text("No saved drives match your search.").foregroundStyle(muted) }
                ForEach(summaries, id: \.volumeID) { summary in
                    let drive = station.registry.first { $0.id == summary.volumeID } ?? Drive(id: summary.volumeID, name: summary.volumeName, device: "", format: "", connection: "", capacity: 0, state: .offline, lastSeen: summary.capturedAt)
                    Panel {
                        HStack(spacing: 20) {
                            Image(systemName: "photo.stack").font(.system(size: 34, weight: .light)).foregroundStyle(cyan)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(summary.volumeName).font(.system(size: 19, weight: .semibold))
                                Text("\(summary.scope) · \(summary.itemCount.formatted()) items · \(summary.thumbnailCount) thumbnails").font(.system(size: 12)).foregroundStyle(muted)
                                Text("Captured \(summary.capturedAt.formatted())\(summary.partial ? " · PARTIAL CATALOG" : "")").font(.system(size: 10, design: .monospaced)).foregroundStyle(summary.partial ? amber : muted)
                            }
                            Spacer()
                            Button("BROWSE SNAPSHOT") { Task { await station.browseSnapshot(drive) } }.buttonStyle(DeckButton(prominent: true)).disabled(station.busy)
                        }
                    }
                }
            }
        }
    }
    private var activity: some View {
        VStack(alignment: .leading, spacing: 22) {
            Micro(text: "SESSION EVENTS / 03", color: cyan)
            Text("The station log.").font(.system(size: 30, weight: .semibold))
            Text("Scans and commands from this session. Nothing runs on a schedule.").foregroundStyle(muted)
            Panel {
                VStack(alignment: .leading, spacing: 0) {
                    if station.events.isEmpty { Text("No events yet.").foregroundStyle(muted) }
                    ForEach(station.events) { event in
                        HStack(alignment: .top, spacing: 20) {
                            Text(event.date, style: .time).foregroundStyle(muted).frame(width: 85, alignment: .leading)
                            Image(systemName: event.failure ? "exclamationmark.triangle" : "smallcircle.filled.circle").foregroundStyle(event.failure ? amber : cyan)
                            Text(event.text).textSelection(.enabled)
                            Spacer()
                        }.font(.system(size: 12, design: .monospaced)).padding(.vertical, 15)
                        Rectangle().fill(edge).frame(height: 1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 22) {
            Micro(text: "STATION CONFIGURATION / 04", color: cyan)
            Text("Built to stay quiet.").font(.system(size: 30, weight: .semibold))
            Panel {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Appearance", selection: $appearance) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                    }.pickerStyle(.segmented).frame(maxWidth: 320)
                    Text("Choose your command deck colors. Appearance is saved and also applies to the volume explorer.").foregroundStyle(muted)
                    Divider()
                    Toggle("Capture first snapshot of new external drives", isOn: $automaticSnapshots).toggleStyle(.switch).tint(cyan).disabled(station.busy)
                    Text("A snapshot saves filenames, folders and media thumbnails on this Mac. It runs once for a mounted external volume without a snapshot; later updates are manual. Cancel from the capture banner at any time. Internal storage is opt-in and captures your Home folder.").foregroundStyle(muted)
                    Text("Coverage: visible files only; no package contents, symlink traversal, other mounted volumes, or cloud-only downloads. Each capture indexes up to 100,000 items / 2 minutes and attempts up to 300 media thumbnails / 90 seconds. Partial coverage is labeled. This is a catalog, not a backup.").foregroundStyle(muted)
                    Divider()
                    Toggle("Launch into the menu bar", isOn: $launchInMenuBar).toggleStyle(.switch).tint(cyan)
                    Text("When enabled, Drive Station starts without opening the command deck. Select its menu-bar drive icon to open it.").foregroundStyle(muted)
                    Toggle("Start Drive Station at login", isOn: Binding(get: { LoginItemService.enabled }, set: { enabled in
                        do {
                            try LoginItemService.setEnabled(enabled)
                            if enabled { launchInMenuBar = true }
                        } catch {
                            station.error = "Could not change the login-item setting: \(error.localizedDescription)"
                        }
                    })).toggleStyle(.switch).tint(cyan)
                    Text("macOS may ask you to approve this in System Settings. Login launches use the menu-bar mode.").foregroundStyle(muted)
                    Divider()
                    Picker("Orbital-map double-click", selection: $orbitDoubleClickAction) {
                        Text("Explore in Drive Station").tag("explore")
                        Text("Open in Finder").tag("finder")
                    }.pickerStyle(.segmented).frame(maxWidth: 420)
                    Text("Right-click any orbital-map drive for Explore and Open in Finder. Double-click uses the selected action.").foregroundStyle(muted)
                    Divider()
                    Toggle("Simulation mode", isOn: Binding(get: { station.simulation }, set: { station.setSimulation($0) })).toggleStyle(.switch).tint(cyan).disabled(station.busy)
                    Text("Explore a sample fleet and try the controls. Simulation never operates on your real drives.").foregroundStyle(muted)
                    Divider()
                    Text("How standby works").font(.headline)
                    Text("Standby asks macOS to safely unmount one external volume. Wake & Explore mounts it again and opens the built-in explorer. The volume options menu also offers Open in Finder. Internal storage can be explored but always stays online. If an app is using a volume, macOS can refuse to unmount it; close its files and try again.")
                    Text("Standby is not a hardware sleep command. Other volumes on the same disk may remain active. Reconnecting or rebooting may cause macOS to mount volumes again.")
                    Divider()
                    Text("On-demand discovery").font(.headline)
                    Text("The station scans at launch, when you press ⌘R or Scan Drives, after a drive operation, and when leaving simulation. The explorer reads only the folder you open or refresh. Search filters that folder; it does not crawl the drive. Use Scan Drives after connecting or disconnecting a disk.")
                    Divider()
                    Text("Local memory").font(.headline)
                    Text("Names, volume IDs, capacity, and last-seen details stay on this Mac in Application Support/DriveStation/registry.json. Disconnected volumes remain in your registry. Use their minus button to forget them.")
                    Text("Drive Station does not change Spotlight, macOS power settings, or automatic mounting rules. The effect on performance depends on your drives and the apps using them.").foregroundStyle(muted)
                }.font(.system(size: 13)).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: station.busy ? "hourglass" : "checkmark.shield").foregroundStyle(cyan)
            Micro(text: station.busy ? "COMMAND IN PROGRESS" : "ON-DEMAND SCANNING", color: cyan)
            Spacer()
            Micro(text: station.simulation ? "SAMPLE TELEMETRY" : station.lastScan.map { "LAST SCAN  " + $0.formatted(date: .omitted, time: .shortened) } ?? "AWAITING SCAN")
            Text("│").foregroundStyle(edge)
            Micro(text: "⌘ R  RESCAN")
        }.padding(.horizontal, 28).padding(.vertical, 13).background(panel).overlay(alignment: .top) { Rectangle().fill(edge).frame(height: 1) }
    }
}

private struct CapacityRing: View {
    var drive: Drive
    var body: some View {
        ZStack {
            Circle().stroke(drive.state.color.opacity(0.1), lineWidth: 4)
            Circle().trim(from: 0, to: drive.usedFraction).stroke(drive.state.color, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(drive.free == nil ? "—" : "\(Int(drive.usedFraction * 100))%").font(.system(size: 16, weight: .medium, design: .monospaced))
                Text("USED").font(.system(size: 7, design: .monospaced)).foregroundStyle(muted)
            }
        }
    }
}

private struct OrbitMap: View {
    var drives: [Drive]
    var selectedID: String?
    var select: (String) -> Void
    var activate: (Drive) -> Void
    var explore: (Drive) -> Void
    var finder: (Drive) -> Void
    private func point(_ index: Int, count: Int, size: CGSize) -> CGPoint {
        let angle = Double(index) / Double(max(count, 1)) * .pi * 2 - .pi / 4
        return CGPoint(x: size.width / 2 + cos(angle) * size.width * 0.33, y: size.height / 2 + sin(angle) * size.height * 0.32)
    }
    var body: some View {
        GeometryReader { geo in
            let shown = Array(drives.prefix(8))
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                Canvas { context, size in
                    for x in stride(from: 0.0, to: size.width, by: 20) {
                        for y in stride(from: 8.0, to: size.height, by: 20) {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(cyan.opacity(0.12)))
                        }
                    }
                    for radius in [57.0, 84, 117] {
                        let ellipse = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                        context.stroke(Path(ellipseIn: ellipse), with: .color(cyan.opacity(radius == 84 ? 0.16 : 0.07)), style: StrokeStyle(lineWidth: 1, dash: radius == 117 ? [2, 6] : []))
                    }
                    for (i, drive) in shown.enumerated() {
                        let end = point(i, count: shown.count, size: size)
                        var line = Path(); line.move(to: center); line.addLine(to: end)
                        context.stroke(line, with: .color(drive.state.color.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: drive.state == .online ? [] : [3, 5]))
                    }
                    var cross = Path()
                    cross.move(to: CGPoint(x: center.x, y: 0)); cross.addLine(to: CGPoint(x: center.x, y: size.height))
                    cross.move(to: CGPoint(x: 0, y: center.y)); cross.addLine(to: CGPoint(x: size.width, y: center.y))
                    context.stroke(cross, with: .color(cyan.opacity(0.045)))
                }
                Circle().fill(cyan.opacity(0.04)).frame(width: 110, height: 110).blur(radius: 12).position(center)
                VStack(spacing: 7) {
                    ZStack {
                        Hexagon().fill(StationTheme.core)
                        Hexagon().stroke(cyan.opacity(0.75), lineWidth: 1)
                        Image(systemName: "desktopcomputer").font(.system(size: 25, weight: .light)).foregroundStyle(cyan)
                    }.frame(width: 72, height: 77).shadow(color: cyan.opacity(0.15), radius: 15)
                    Micro(text: "THIS MAC", color: cyan)
                }.position(x: center.x, y: center.y + 8)
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, drive in
                    Button { select(drive.id) } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(panel)
                                RoundedRectangle(cornerRadius: 10).stroke(drive.state.color.opacity(drive.id == selectedID ? 1 : 0.3), lineWidth: 1)
                                Image(systemName: "externaldrive.fill").font(.system(size: 22)).foregroundStyle(drive.state.color)
                                Circle().fill(drive.state.color).frame(width: 5, height: 5).offset(x: 20, y: -19)
                            }.frame(width: 59, height: 51).shadow(color: drive.state.color.opacity(drive.id == selectedID ? 0.2 : 0), radius: 12)
                            Text(drive.name.components(separatedBy: " • ").first ?? drive.name).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1).lineLimit(1).frame(width: 120)
                            Text(drive.state.rawValue.uppercased()).font(.system(size: 7, design: .monospaced)).tracking(1).foregroundStyle(drive.state.color)
                        }
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { activate(drive) })
                    .contextMenu {
                        Button("Explore in Drive Station") { explore(drive) }.disabled(drive.state == .offline)
                        Button("Open in Finder") { finder(drive) }.disabled(drive.state == .offline)
                    }
                    .position(point(i, count: shown.count, size: geo.size))
                    .accessibilityLabel("Select \(drive.name), \(drive.state.rawValue)")
                }
                if drives.isEmpty {
                    Micro(text: "NO EXTERNAL VOLUMES DETECTED").position(x: center.x, y: geo.size.height - 12)
                } else if drives.count > 8 {
                    Micro(text: "+\(drives.count - 8) MORE IN FLEET").position(x: center.x, y: geo.size.height - 8)
                }
                Micro(text: "DS—01").position(x: 28, y: 20)
                Micro(text: "HOST").position(x: geo.size.width - 22, y: 20)
            }
        }
    }
}

private struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            for i in 0..<6 {
                let angle = Double(i) * .pi / 3 - .pi / 2
                let point = CGPoint(x: rect.midX + cos(angle) * rect.width / 2, y: rect.midY + sin(angle) * rect.height / 2)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }
}
