import SwiftUI
import AppKit

enum StationTheme {
    private static func adaptive(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
    static let accent = adaptive(0x52F0E8, 0x00776F)
    static let muted = adaptive(0x7D96A3, 0x536A75)
    static let amber = adaptive(0xFAB85C, 0x925600)
    static let background = adaptive(0x060A0D, 0xEDF3F5)
    static let sidebar = adaptive(0x070C10, 0xE3ECEF)
    static let panel = adaptive(0x0A1216, 0xFFFFFF)
    static let text = adaptive(0xDEEBF0, 0x172F39)
    static let edge = adaptive(0x202A2F, 0xCCDADD)
    static let track = adaptive(0x172024, 0xE1EAED)
    static let core = adaptive(0x0A2126, 0xD0EAE7)
    static let onAccent = adaptive(0x000000, 0xFFFFFF)
}

struct AppearanceButton: View {
    @AppStorage("stationAppearance") private var appearance = "dark"
    var body: some View {
        Button { appearance = appearance == "dark" ? "light" : "dark" } label: {
            Image(systemName: appearance == "dark" ? "sun.max" : "moon")
                .foregroundStyle(StationTheme.accent)
        }.buttonStyle(.plain).help(appearance == "dark" ? "Switch to light mode" : "Switch to dark mode")
            .accessibilityLabel(appearance == "dark" ? "Switch to light mode" : "Switch to dark mode")
    }
}
