// Standalone checks for Macs with command-line tools but no XCTest framework.
// Run with: bash scripts/verify-shortcut.sh
import AppKit
import Carbon

private final class FakeRegistrar: ShortcutRegistering {
    var onPress: (() -> Void)?
    var current: StationShortcut?
    var reject = false
    var registrations = 0
    func register(_ shortcut: StationShortcut) throws {
        registrations += 1
        if reject { throw NSError(domain: "ShortcutChecks", code: 1) }
        current = shortcut
    }
    func unregister() { current = nil }
}

@main private enum ShortcutChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let suite = "DriveStation.ShortcutChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = FakeRegistrar()
        let shortcut = GlobalShortcut(defaults: defaults, registrar: backend)
        var activations = 0
        shortcut.start { activations += 1 }
        precondition(shortcut.registered && backend.current == .defaultShortcut)
        precondition(shortcut.shortcut.display == "⌃⌥D")
        shortcut.start { activations += 1 }
        precondition(backend.registrations == 1, "Reopening the window must not register twice")
        backend.onPress?()
        precondition(activations == 1)

        let replacement = StationShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | shiftKey), keyLabel: "S")
        precondition(shortcut.apply(replacement))
        let saved = defaults.data(forKey: GlobalShortcut.preferenceKey)
        precondition(backend.current == replacement)
        backend.reject = true
        precondition(!shortcut.apply(.defaultShortcut))
        precondition(shortcut.registered && shortcut.shortcut == replacement && backend.current == replacement)
        precondition(defaults.data(forKey: GlobalShortcut.preferenceKey) == saved)
        precondition(shortcut.error?.contains("previous shortcut is still active") == true)
        backend.reject = false

        let restoredBackend = FakeRegistrar()
        let restored = GlobalShortcut(defaults: defaults, registrar: restoredBackend)
        restored.start {}
        precondition(restoredBackend.current == replacement, "Relaunch should register the saved combination")
        shortcut.setEnabled(false)
        precondition(!shortcut.enabled && !shortcut.registered && backend.current == nil)
        let disabledBackend = FakeRegistrar()
        let disabled = GlobalShortcut(defaults: defaults, registrar: disabledBackend)
        disabled.start {}
        precondition(!disabled.enabled && disabledBackend.current == nil, "Disabled state should survive relaunch")
        shortcut.setEnabled(true)
        precondition(shortcut.registered && backend.current == replacement)
        precondition(shortcut.apply(.defaultShortcut))

        let invalid = StationShortcut(keyCode: 2, modifiers: UInt32(shiftKey), keyLabel: "D")
        precondition(!shortcut.apply(invalid))
        precondition(shortcut.shortcut == .defaultShortcut)
        shortcut.startRecording()
        backend.onPress?()
        precondition(!shortcut.recording && activations == 1, "Recording the current shortcut must not open the deck")
        shortcut.startRecording()
        shortcut.stopRecording()
        precondition(shortcut.registered && backend.current == .defaultShortcut)

        func event(_ flags: NSEvent.ModifierFlags, code: UInt16 = 2, characters: String = "d") -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        }
        precondition(StationShortcut(event: event([.control, .option])) == .defaultShortcut)
        precondition(StationShortcut(event: event([.shift])) == nil)
        precondition(StationShortcut(event: event([.option])) == nil)
        precondition(StationShortcut(event: event([.command], code: 49, characters: " "))?.display == "⌘Space")
        defaults.set(Data("invalid".utf8), forKey: GlobalShortcut.preferenceKey)
        precondition(GlobalShortcut(defaults: defaults, registrar: FakeRegistrar()).shortcut == .defaultShortcut)
        defaults.set(try JSONEncoder().encode(invalid), forKey: GlobalShortcut.preferenceKey)
        precondition(GlobalShortcut(defaults: defaults, registrar: FakeRegistrar()).shortcut == .defaultShortcut)
        let failingBackend = FakeRegistrar()
        failingBackend.reject = true
        let failing = GlobalShortcut(defaults: defaults, registrar: failingBackend)
        failing.start {}
        precondition(failing.enabled && !failing.registered && failing.error != nil)
        failingBackend.reject = false
        precondition(failing.apply(failing.shortcut) && failing.registered, "Startup conflicts should be retryable")

        // Exercise the real macOS registration API using uncommon combinations.
        let first = CarbonShortcutRegistrar()
        let second = CarbonShortcutRegistrar()
        let probe = CarbonShortcutRegistrar()
        defer { first.unregister(); second.unregister(); probe.unregister() }
        let modifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        let a = StationShortcut(keyCode: UInt32(kVK_F18), modifiers: modifiers, keyLabel: "F18")
        let b = StationShortcut(keyCode: UInt32(kVK_F19), modifiers: modifiers, keyLabel: "F19")
        let c = StationShortcut(keyCode: UInt32(kVK_F17), modifiers: modifiers, keyLabel: "F17")
        func expectConflict(_ registrar: CarbonShortcutRegistrar, _ key: StationShortcut) {
            do { try registrar.register(key); preconditionFailure("Expected an exclusive registration conflict") }
            catch { precondition(error.localizedDescription.contains("already in use")) }
        }
        try first.register(a)
        try second.register(b)
        expectConflict(second, a)
        expectConflict(probe, b) // Failed replacement preserved second's old registration.
        try first.register(c)
        try probe.register(a) // Successful replacement released first's old registration.
        first.unregister()
        try second.register(c)

        var pressed = 0
        second.onPress = { pressed += 1 }
        var hotKeyEvent: EventRef?
        precondition(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &hotKeyEvent) == noErr)
        defer { ReleaseEvent(hotKeyEvent) }
        var id = EventHotKeyID(signature: 0x4453544E, id: 2)
        precondition(SetEventParameter(hotKeyEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id) == noErr)
        precondition(SendEventToEventTarget(hotKeyEvent, GetApplicationEventTarget()) == noErr)
        precondition(pressed == 1, "Registered Carbon events should invoke the activation callback")
        id.id = 1
        precondition(SetEventParameter(hotKeyEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id) == noErr)
        _ = SendEventToEventTarget(hotKeyEvent, GetApplicationEventTarget())
        precondition(pressed == 1, "Events queued for a replaced binding must be ignored")
        second.unregister()
        id.id = 2
        precondition(SetEventParameter(hotKeyEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id) == noErr)
        _ = SendEventToEventTarget(hotKeyEvent, GetApplicationEventTarget())
        precondition(pressed == 1, "Events queued before disabling must be ignored")
        var temporary: CarbonShortcutRegistrar? = CarbonShortcutRegistrar()
        try temporary?.register(c)
        temporary = nil
        try first.register(c) // Destroying a registrar must release its binding.

        var symbolicKeys: Unmanaged<CFArray>?
        precondition(CopySymbolicHotKeys(&symbolicKeys) == noErr)
        let reserved = symbolicKeys!.takeRetainedValue() as! [[String: Any]]
        if let systemKey = reserved.first(where: { ($0[kHISymbolicHotKeyEnabled as String] as? Bool) == true }),
           let code = systemKey[kHISymbolicHotKeyCode as String] as? NSNumber,
           let flags = systemKey[kHISymbolicHotKeyModifiers as String] as? NSNumber {
            expectConflict(second, StationShortcut(keyCode: code.uint32Value, modifiers: flags.uint32Value & StationShortcut.allowedModifiers, keyLabel: "System key"))
        }
        print("Shortcut checks passed: persistence, validation, recording cancellation, retry, Carbon activation, exclusive conflicts, replacement, and release.")
    }
}
