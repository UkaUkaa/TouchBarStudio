import Foundation

/// A keyboard shortcut expressed as a macOS virtual key code plus modifiers.
public struct KeyCombo: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
        public static let function = Modifiers(rawValue: 1 << 4)

        public static let all: Modifiers = [.command, .option, .control, .shift, .function]
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Human-readable form, e.g. "⇧⌘K".
    public var displayString: String {
        var s = ""
        if modifiers.contains(.function) { s += "fn " }
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + KeyCodes.name(for: keyCode)
    }

    public var isValid: Bool {
        KeyCodes.isKnown(keyCode) && Modifiers.all.isSuperset(of: modifiers)
    }
}

/// ANSI virtual key codes (Carbon `kVK_*`) with display names.
public enum KeyCodes {
    public static let table: [UInt16: String] = [
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F", 0x05: "G", 0x04: "H",
        0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P",
        0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
        0x10: "Y", 0x06: "Z",
        0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7",
        0x1C: "8", 0x19: "9",
        0x18: "=", 0x1B: "-", 0x1E: "]", 0x21: "[", 0x27: "'", 0x29: ";", 0x2A: "\\", 0x2B: ",",
        0x2C: "/", 0x2F: ".", 0x32: "`",
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x73: "Home", 0x77: "End", 0x74: "PgUp", 0x79: "PgDn",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15",
        0x6A: "F16", 0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
    ]

    public static func isKnown(_ code: UInt16) -> Bool { table[code] != nil }
    public static func name(for code: UInt16) -> String { table[code] ?? "Key \(code)" }

    /// Looks up a key code by its display name ("K", "F5", "Space", …).
    public static func code(named name: String) -> UInt16? {
        table.first { $0.value.caseInsensitiveCompare(name) == .orderedSame }?.key
    }
}

extension KeyCombo {
    /// Convenience for presets: `KeyCombo("K", [.command, .shift])`.
    public init(_ keyName: String, _ modifiers: Modifiers = []) {
        self.init(keyCode: KeyCodes.code(named: keyName) ?? 0, modifiers: modifiers)
    }
}
