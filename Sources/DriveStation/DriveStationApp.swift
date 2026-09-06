import SwiftUI
import AppKit

@main struct DriveStationApp: App {
    @StateObject private var station = Station()
    @AppStorage("stationAppearance") private var appearance = "dark"
    var body: some Scene {
        Window("Drive Station", id: "station") {
            CommandDeck(station: station)
                .preferredColorScheme(appearance == "light" ? .light : .dark)
                .task { await station.refresh() }
        }
        .defaultSize(width: 1380, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan drives") { Task { await station.refresh() } }.keyboardShortcut("r").disabled(station.busy)
            }
        }
        MenuBarExtra("Drive Station", systemImage: "externaldrive.connected.to.line.below") {
            MenuControls(station: station)
        }
    }
}

struct MenuControls: View {
    @ObservedObject var station: Station
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Button("Open command deck") { openWindow(id: "station"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        if station.simulation { Text("Simulation mode") }
        ForEach(station.drives) { drive in
            Menu("\(drive.name) · \(drive.state.rawValue)") {
                Button("Explore in Drive Station") {
                    openWindow(id: "station"); NSApp.activate(ignoringOtherApps: true)
                    Task { await station.explore(drive) }
                }.disabled(drive.state == .offline || station.busy)
                Button("Open in Finder") { Task { await station.act(drive, open: true) } }.disabled(drive.state == .offline || station.busy)
                if !station.simulation, station.snapshots[drive.id] != nil {
                    Button("Browse Saved Snapshot") {
                        openWindow(id: "station"); NSApp.activate(ignoringOtherApps: true)
                        Task { await station.browseSnapshot(drive) }
                    }.disabled(station.busy)
                }
                if !drive.internalVolume {
                    Button("Standby") { Task { await station.act(drive, open: false) } }.disabled(!drive.canStandby || station.busy)
                }
            }
        }
        Button("Scan drives") { Task { await station.refresh() } }.disabled(station.busy)
        Divider()
        Button("Quit Drive Station") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}
