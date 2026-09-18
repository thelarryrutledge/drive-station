import AppKit
import Carbon
import SwiftUI

struct StationShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyLabel: String

    static let defaultShortcut = StationShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey), keyLabel: "D")
    static let allowedModifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)
    var isValid: Bool {
        keyCode < 128 && !keyLabel.isEmpty && modifiers & ~Self.allowedModifiers == 0
            && modifiers & UInt32(controlKey | cmdKey) != 0
    }
    var display: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + keyLabel
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)] {
            if flags.contains(flag) { modifiers |= UInt32(carbon) }
        }
        let specialKeys: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        let label = specialKeys[event.keyCode] ?? event.characters(byApplyingModifiers: [])?.uppercased() ?? ""
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
        guard isValid, !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
    }
}

protocol ShortcutRegistering: AnyObject {
    var onPress: (() -> Void)? { get set }
    /// A failed replacement must leave the existing registration intact.
    func register(_ shortcut: StationShortcut) throws
    func unregister()
}

private struct ShortcutRegistrationError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        status == eventHotKeyExistsErr
            ? "That shortcut is already in use. Choose another combination."
            : "macOS could not register that shortcut (error \(status)). Choose another combination or try again."
    }
}

final class CarbonShortcutRegistrar: ShortcutRegistering {
    var onPress: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var activeID: UInt32 = 0
    private static let signature: OSType = 0x4453544E // DSTN

    func register(_ shortcut: StationShortcut) throws {
        var symbolicKeys: Unmanaged<CFArray>?
        let lookupStatus = CopySymbolicHotKeys(&symbolicKeys)
        let reserved = symbolicKeys?.takeRetainedValue() as? [[String: Any]] ?? []
        guard lookupStatus == noErr else { throw ShortcutRegistrationError(status: lookupStatus) }
        if reserved.contains(where: {
            ($0[kHISymbolicHotKeyEnabled as String] as? Bool) == true
                && ($0[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value == shortcut.keyCode
                && (($0[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value ?? 0) & StationShortcut.allowedModifiers == shortcut.modifiers
        }) { throw ShortcutRegistrationError(status: OSStatus(eventHotKeyExistsErr)) }
        if handler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                let registrar = Unmanaged<CarbonShortcutRegistrar>.fromOpaque(context).takeUnretainedValue()
                var id = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr, registrar.hotKey != nil, id.signature == CarbonShortcutRegistrar.signature, id.id == registrar.activeID else { return OSStatus(eventNotHandledErr) }
                registrar.onPress?()
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw ShortcutRegistrationError(status: status) }
        }
        var replacement: EventHotKeyRef?
        let nextID = activeID &+ 1
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: Self.signature, id: nextID), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &replacement)
        guard status == noErr else { throw ShortcutRegistrationError(status: status) }
        // Keep the old binding until macOS accepts the replacement.
        unregister()
        hotKey = replacement
        activeID = nextID
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }
}

@MainActor final class GlobalShortcut: ObservableObject {
    @Published private(set) var shortcut: StationShortcut
    @Published private(set) var enabled: Bool
    @Published private(set) var registered = false
    @Published private(set) var recording = false
    @Published private(set) var error: String?
    private let defaults: UserDefaults
    private let registrar: ShortcutRegistering
    private var activate: (() -> Void)?
    private var monitor: Any?
    static let preferenceKey = "commandDeckShortcut"
    static let enabledKey = "commandDeckShortcutEnabled"

    init(defaults: UserDefaults = .standard, registrar: ShortcutRegistering = CarbonShortcutRegistrar()) {
        self.defaults = defaults
        self.registrar = registrar
        let saved = defaults.data(forKey: Self.preferenceKey).flatMap { try? JSONDecoder().decode(StationShortcut.self, from: $0) }
        shortcut = saved.flatMap { $0.isValid ? $0 : nil } ?? .defaultShortcut
        enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        registrar.onPress = { [weak self] in
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.recording { self.stopRecording() }
                else { self.activate?() }
            }
        }
    }

    func start(activate: @escaping () -> Void) {
        self.activate = activate
        if enabled && !registered { _ = apply(shortcut) }
    }

    @discardableResult func apply(_ candidate: StationShortcut) -> Bool {
        guard candidate.isValid else {
            error = "Include Control or Command along with a key. Option and Shift are optional."
            return false
        }
        if !registered || candidate.keyCode != shortcut.keyCode || candidate.modifiers != shortcut.modifiers {
            do { try registrar.register(candidate) }
            catch {
                self.error = error.localizedDescription + (registered ? " Your previous shortcut is still active." : " The shortcut is currently unavailable.")
                return false
            }
        }
        shortcut = candidate
        enabled = true
        registered = true
        error = nil
        defaults.set(try? JSONEncoder().encode(candidate), forKey: Self.preferenceKey)
        defaults.set(true, forKey: Self.enabledKey)
        return true
    }

    func setEnabled(_ value: Bool) {
        stopRecording()
        if value { _ = apply(shortcut) }
        else {
            registrar.unregister()
            enabled = false
            registered = false
            error = nil
            defaults.set(false, forKey: Self.enabledKey)
        }
    }

    func startRecording() {
        stopRecording()
        error = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                if event.keyCode == UInt16(kVK_Escape) { self.stopRecording(); return true }
                guard !event.isARepeat else { return true }
                guard let candidate = StationShortcut(event: event) else {
                    self.error = "Include Control or Command along with a key. Option and Shift are optional."
                    return true
                }
                self.stopRecording()
                _ = self.apply(candidate)
                return true
            }
            return consumed ? nil : event
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

struct ShortcutSettings: View {
    @ObservedObject var shortcut: GlobalShortcut
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Global keyboard shortcut", isOn: Binding(get: { shortcut.enabled }, set: { shortcut.setEnabled($0) }))
                .toggleStyle(.switch).tint(StationTheme.accent)
            HStack(spacing: 12) {
                Text("Open command deck")
                Text(shortcut.shortcut.display).font(.system(.body, design: .monospaced)).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(StationTheme.accent.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 5))
                Button(shortcut.recording ? "Cancel" : "Change…") {
                    if shortcut.recording { shortcut.stopRecording() } else { shortcut.startRecording() }
                }
                Button("Reset to default") { shortcut.stopRecording(); shortcut.apply(.defaultShortcut) }.disabled(shortcut.recording)
                if shortcut.enabled && !shortcut.registered { Button("Retry") { shortcut.apply(shortcut.shortcut) } }
            }
            Text(shortcut.recording ? "Press your new shortcut. Include Control or Command; press Escape to cancel." : "Opens Drive Station from any app while it is running, including when its window is closed. Changes are saved automatically.")
                .foregroundStyle(StationTheme.muted)
            if let error = shortcut.error { Text(error).foregroundStyle(StationTheme.amber) }
        }
        .onDisappear { shortcut.stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in shortcut.stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in shortcut.stopRecording() }
    }
}
