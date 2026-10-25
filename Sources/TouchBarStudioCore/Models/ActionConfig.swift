import Foundation

public enum ActionKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case none
    case openApplication
    case openURL
    case openFile
    case keyboardShortcut
    case copyText
    case appleScript
    case shellCommand
    case appCommand
    case mediaKey
    case sequence

    public var id: String { rawValue }
}

public enum MediaKey: String, Codable, CaseIterable, Sendable, Identifiable {
    case playPause, next, previous, volumeUp, volumeDown, mute

    public var id: String { rawValue }

    /// `NX_KEYTYPE_*` value from IOKit's ev_keymap.h.
    public var systemKeyType: Int32 {
        switch self {
        case .volumeUp: 0
        case .volumeDown: 1
        case .mute: 7
        case .playPause: 16
        case .next: 17
        case .previous: 18
        }
    }

    public var title: String {
        switch self {
        case .playPause: L("Play / Pause")
        case .next: L("Next Track")
        case .previous: L("Previous Track")
        case .volumeUp: L("Volume Up")
        case .volumeDown: L("Volume Down")
        case .mute: L("Mute")
        }
    }

    public var symbolName: String {
        switch self {
        case .playPause: "playpause.fill"
        case .next: "forward.fill"
        case .previous: "backward.fill"
        case .volumeUp: "speaker.wave.3.fill"
        case .volumeDown: "speaker.wave.1.fill"
        case .mute: "speaker.slash.fill"
        }
    }
}

/// A configured action. Stored flat (kind + optional payload fields) so the JSON
/// stays readable and switching kinds in the editor does not lose unrelated input.
public struct ActionConfig: Codable, Hashable, Sendable {
    public var kind: ActionKind
    /// openApplication: target bundle identifier.
    public var bundleIdentifier: String?
    /// openURL.
    public var url: String?
    /// openFile: absolute path (`~` is expanded).
    public var path: String?
    /// keyboardShortcut.
    public var keyCombo: KeyCombo?
    /// keyboardShortcut: app to activate before sending the keys (falls back to the button's app).
    public var targetBundleIdentifier: String?
    /// copyText.
    public var text: String?
    /// appleScript source or shell command line.
    public var script: String?
    /// appCommand: identifier in `AppCommandCatalog`.
    public var appCommandID: String?
    /// mediaKey.
    public var mediaKey: MediaKey?
    /// sequence.
    public var steps: [ActionConfig]?
    /// sequence: pause between steps.
    public var delayMilliseconds: Int?

    public init(
        kind: ActionKind,
        bundleIdentifier: String? = nil,
        url: String? = nil,
        path: String? = nil,
        keyCombo: KeyCombo? = nil,
        targetBundleIdentifier: String? = nil,
        text: String? = nil,
        script: String? = nil,
        appCommandID: String? = nil,
        mediaKey: MediaKey? = nil,
        steps: [ActionConfig]? = nil,
        delayMilliseconds: Int? = nil
    ) {
        self.kind = kind
        self.bundleIdentifier = bundleIdentifier
        self.url = url
        self.path = path
        self.keyCombo = keyCombo
        self.targetBundleIdentifier = targetBundleIdentifier
        self.text = text
        self.script = script
        self.appCommandID = appCommandID
        self.mediaKey = mediaKey
        self.steps = steps
        self.delayMilliseconds = delayMilliseconds
    }

    public static let none = ActionConfig(kind: .none)

    public static func openApp(_ bundleID: String) -> ActionConfig { .init(kind: .openApplication, bundleIdentifier: bundleID) }
    public static func openURL(_ url: String) -> ActionConfig { .init(kind: .openURL, url: url) }
    public static func openFile(_ path: String) -> ActionConfig { .init(kind: .openFile, path: path) }
    public static func shortcut(_ combo: KeyCombo, in bundleID: String? = nil) -> ActionConfig {
        .init(kind: .keyboardShortcut, keyCombo: combo, targetBundleIdentifier: bundleID)
    }
    public static func copy(_ text: String) -> ActionConfig { .init(kind: .copyText, text: text) }
    public static func appleScript(_ source: String) -> ActionConfig { .init(kind: .appleScript, script: source) }
    public static func shell(_ command: String) -> ActionConfig { .init(kind: .shellCommand, script: command) }
    public static func command(_ id: String) -> ActionConfig { .init(kind: .appCommand, appCommandID: id) }
    public static func media(_ key: MediaKey) -> ActionConfig { .init(kind: .mediaKey, mediaKey: key) }
    public static func sequence(_ steps: [ActionConfig], delayMilliseconds: Int = 150) -> ActionConfig {
        .init(kind: .sequence, steps: steps, delayMilliseconds: delayMilliseconds)
    }

    /// True if this action (or any nested step) runs user-provided code.
    public var containsScript: Bool {
        switch kind {
        case .appleScript, .shellCommand: true
        case .sequence: (steps ?? []).contains { $0.containsScript }
        default: false
        }
    }

    /// All script-bearing actions, flattened out of sequences.
    public var scriptActions: [ActionConfig] {
        switch kind {
        case .appleScript, .shellCommand: [self]
        case .sequence: (steps ?? []).flatMap(\.scriptActions)
        default: []
        }
    }

    /// Whether running this action needs permission to post synthetic input events.
    public func requiresAccessibility(catalog: AppCommandCatalog = .standard) -> Bool {
        switch kind {
        case .keyboardShortcut, .mediaKey: true
        case .appCommand: catalog.command(id: appCommandID ?? "")?.action.requiresAccessibility(catalog: catalog) ?? false
        case .sequence: (steps ?? []).contains { $0.requiresAccessibility(catalog: catalog) }
        default: false
        }
    }

    /// One-line summary for lists.
    public var summary: String {
        switch kind {
        case .none: return L("No action")
        case .openApplication: return L("Open %@", bundleIdentifier ?? "?")
        case .openURL: return L("Open %@", url ?? "?")
        case .openFile: return L("Open %@", path ?? "?")
        case .keyboardShortcut:
            let keys = keyCombo?.displayString ?? "?"
            if let t = targetBundleIdentifier, !t.isEmpty { return L("Press %@ in %@", keys, t) }
            return L("Press %@", keys)
        case .copyText: return L("Copy “%@”", String((text ?? "").prefix(30)))
        case .appleScript: return L("AppleScript (%d chars)", (script ?? "").count)
        case .shellCommand: return L("Shell: %@", String((script ?? "").prefix(40)))
        case .appCommand: return AppCommandCatalog.standard.command(id: appCommandID ?? "")?.title ?? L("Unknown command")
        case .mediaKey: return mediaKey?.title ?? L("Media key")
        case .sequence: return L("Sequence: %@", Lp("%d actions", steps?.count ?? 0))
        }
    }
}
