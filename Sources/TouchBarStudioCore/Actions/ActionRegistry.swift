import Foundation

/// What a given action kind needs from the system before it can run.
public enum ActionRequirement: String, Hashable, Sendable {
    /// Posting synthetic keyboard/media events (Privacy & Security › Accessibility).
    case accessibility
    /// Sending Apple Events to other apps (macOS asks per target app).
    case automation
    /// Shell commands must be enabled in Settings and each command approved.
    case shellEnabled
    /// The script text must be approved by the user before first run.
    case scriptApproval
}

public struct ActionDescriptor: Identifiable, Hashable, Sendable {
    public var kind: ActionKind
    public var title: String
    public var summary: String
    public var symbol: String
    public var requirements: [ActionRequirement]
    public var id: ActionKind { kind }
}

/// Catalog of every supported action type. UI lists come from here, and the executor
/// has a handler for each entry (enforced by `ActionExecutor.supportedKinds` tests).
public enum ActionRegistry {
    /// Computed so titles follow the current interface language.
    public static var descriptors: [ActionDescriptor] { [
        .init(kind: .openApplication, title: L("Open Application"),
              summary: L("Launch or bring an installed app to the front."), symbol: "app.badge", requirements: []),
        .init(kind: .openURL, title: L("Open URL"),
              summary: L("Open a web address or app URL scheme in its default handler."), symbol: "link", requirements: []),
        .init(kind: .openFile, title: L("Open File or Folder"),
              summary: L("Open a document with its default app, or a folder in Finder."), symbol: "folder", requirements: []),
        .init(kind: .keyboardShortcut, title: L("Keyboard Shortcut"),
              summary: L("Send a key combination, optionally to a specific app (activated first)."),
              symbol: "command", requirements: [.accessibility]),
        .init(kind: .copyText, title: L("Copy Text"),
              summary: L("Put predefined text on the clipboard."), symbol: "doc.on.clipboard", requirements: []),
        .init(kind: .appleScript, title: L("AppleScript"),
              summary: L("Run an AppleScript you wrote. macOS asks once per app it controls."),
              symbol: "applescript", requirements: [.automation, .scriptApproval]),
        .init(kind: .shellCommand, title: L("Shell Command"),
              summary: L("Run a command with /bin/zsh. Disabled by default; each command needs approval."),
              symbol: "terminal", requirements: [.shellEnabled, .scriptApproval]),
        .init(kind: .appCommand, title: L("App Command"),
              summary: L("Built-in commands for Finder, Safari, Terminal, Xcode, Music and the system."),
              symbol: "square.grid.3x3", requirements: []),
        .init(kind: .mediaKey, title: L("Media Key"),
              summary: L("Play/pause, track skipping and volume, like the hardware keys."),
              symbol: "playpause", requirements: [.accessibility]),
        .init(kind: .microphone, title: L("Microphone"),
              summary: L("Mute or unmute the microphone for all apps (the default input device)."),
              symbol: "mic.slash", requirements: []),
        .init(kind: .sequence, title: L("Sequence"),
              summary: L("Run several actions in order; stops at the first failure."),
              symbol: "list.number", requirements: []),
    ] }

    public static func descriptor(for kind: ActionKind) -> ActionDescriptor? {
        descriptors.first { $0.kind == kind }
    }

    /// A reasonable starting configuration when the user picks a kind in the editor.
    public static func template(for kind: ActionKind) -> ActionConfig {
        switch kind {
        case .none: .none
        case .openApplication: .openApp("com.apple.calculator")
        case .openURL: .openURL("https://www.apple.com")
        case .openFile: .openFile("~/Downloads")
        case .keyboardShortcut: .shortcut(KeyCombo("Space", .command))
        case .copyText: .copy(L("Hello"))
        case .appleScript: .appleScript("display notification \"Hello\" with title \"TouchBar Studio\"")
        case .shellCommand: .shell("say hello")
        case .appCommand: .command("finder.newWindow")
        case .mediaKey: .media(.playPause)
        case .sequence: .sequence([.openApp("com.apple.finder")])
        case .microphone: .microphone(.toggle)
        }
    }
}
