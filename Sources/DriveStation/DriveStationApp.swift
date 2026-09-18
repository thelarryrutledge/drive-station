import SwiftUI
import AppKit
import ServiceManagement

final class StationAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard UserDefaults.standard.bool(forKey: "launchInMenuBar") else { return }
        // Let SwiftUI create its initial window, then leave the app available
        // from the menu bar without showing the command deck.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.windows.filter { $0.title == "Drive Station" }.forEach { $0.close() }
        }
    }
}

enum LoginItemService {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }
    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}

@main struct DriveStationApp: App {
    @NSApplicationDelegateAdaptor(StationAppDelegate.self) private var appDelegate
    @StateObject private var station = Station()
    @StateObject private var shortcut = GlobalShortcut()
    @AppStorage("stationAppearance") private var appearance = "dark"
    var body: some Scene {
        Window("Drive Station", id: "station") {
            CommandDeck(station: station, shortcut: shortcut)
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
            MenuControls(station: station, shortcut: shortcut)
                .preferredColorScheme(appearance == "light" ? .light : .dark)
        }
        .menuBarExtraStyle(.window)
    }
}
