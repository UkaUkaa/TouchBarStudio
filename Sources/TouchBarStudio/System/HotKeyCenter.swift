import Carbon
import Foundation
import TouchBarStudioCore

/// Global hotkeys via Carbon `RegisterEventHotKey`, the documented API for system-wide
/// shortcuts. It needs no Accessibility permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var registered: [UInt32: (ref: EventHotKeyRef, itemID: UUID)] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false
    var onHotKey: ((UUID) -> Void)?

    /// Replaces all registrations. Returns failures keyed by item ID (e.g. combo already taken).
    func register(_ entries: [(itemID: UUID, combo: KeyCombo)]) -> [UUID: String] {
        unregisterAll()
        installHandlerIfNeeded()
        var failures: [UUID: String] = [:]
        for entry in entries {
            guard entry.combo.isValid, !entry.combo.modifiers.isEmpty else {
                failures[entry.itemID] = "A hotkey needs at least one modifier key."
                continue
            }
            let hotKeyID = EventHotKeyID(signature: OSType(0x5442_5374), id: nextID) // 'TBSt'
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(entry.combo.keyCode), Self.carbonModifiers(entry.combo.modifiers),
                                             hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[nextID] = (ref, entry.itemID)
                nextID += 1
            } else {
                failures[entry.itemID] = "\(entry.combo.displayString) is already used by another app or the system."
            }
        }
        return failures
    }

    func unregisterAll() {
        for (_, entry) in registered { UnregisterEventHotKey(entry.ref) }
        registered.removeAll()
    }

    fileprivate func fire(id: UInt32) {
        if let entry = registered[id] { onHotKey?(entry.itemID) }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated { HotKeyCenter.shared.fire(id: id) }
            return noErr
        }, 1, &eventType, nil, nil)
        handlerInstalled = true
    }

    private static func carbonModifiers(_ m: KeyCombo.Modifiers) -> UInt32 {
        var result = 0
        if m.contains(.command) { result |= cmdKey }
        if m.contains(.option) { result |= optionKey }
        if m.contains(.control) { result |= controlKey }
        if m.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }
}
