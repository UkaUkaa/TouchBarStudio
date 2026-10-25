import Foundation

/// A named, app-specific command implemented in terms of a basic action.
public struct AppCommand: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var appName: String
    /// Bundle identifier of the app the command targets, or nil for system-wide commands.
    public var bundleIdentifier: String?
    public var symbol: String
    public var action: ActionConfig
}

/// Built-in application commands. Each expands to a real keyboard shortcut,
/// AppleScript, or app launch — nothing is simulated.
public struct AppCommandCatalog: Sendable {
    public let commands: [AppCommand]

    public func command(id: String) -> AppCommand? { commands.first { $0.id == id } }

    public var groupedByApp: [(app: String, commands: [AppCommand])] {
        var order: [String] = []
        var groups: [String: [AppCommand]] = [:]
        for c in commands {
            if groups[c.appName] == nil { order.append(c.appName) }
            groups[c.appName, default: []].append(c)
        }
        return order.map { ($0, groups[$0]!) }
    }

    public static let standard: AppCommandCatalog = {
        func key(_ id: String, _ title: String, _ app: String, _ bundle: String?, _ symbol: String, _ combo: KeyCombo) -> AppCommand {
            AppCommand(id: id, title: title, appName: app, bundleIdentifier: bundle, symbol: symbol,
                       action: .shortcut(combo, in: bundle))
        }
        let finder = "com.apple.finder", safari = "com.apple.Safari", terminal = "com.apple.Terminal", xcode = "com.apple.dt.Xcode"
        return AppCommandCatalog(commands: [
            key("finder.newWindow", "New Window", "Finder", finder, "macwindow.badge.plus", KeyCombo("N", .command)),
            key("finder.goHome", "Go to Home", "Finder", finder, "house", KeyCombo("H", [.command, .shift])),
            key("finder.goDownloads", "Go to Downloads", "Finder", finder, "arrow.down.circle", KeyCombo("L", [.command, .option])),
            key("finder.toggleHidden", "Show/Hide Hidden Files", "Finder", finder, "eye", KeyCombo(".", [.command, .shift])),
            key("finder.getInfo", "Get Info", "Finder", finder, "info.circle", KeyCombo("I", .command)),

            key("safari.newTab", "New Tab", "Safari", safari, "plus.square.on.square", KeyCombo("T", .command)),
            key("safari.reopenTab", "Reopen Closed Tab", "Safari", safari, "arrow.uturn.backward", KeyCombo("T", [.command, .shift])),
            key("safari.reload", "Reload Page", "Safari", safari, "arrow.clockwise", KeyCombo("R", .command)),
            key("safari.back", "Back", "Safari", safari, "chevron.backward", KeyCombo("[", .command)),
            key("safari.forward", "Forward", "Safari", safari, "chevron.forward", KeyCombo("]", .command)),
            key("safari.readerMode", "Reader Mode", "Safari", safari, "doc.plaintext", KeyCombo("R", [.command, .shift])),

            key("terminal.newWindow", "New Window", "Terminal", terminal, "terminal", KeyCombo("N", .command)),
            key("terminal.newTab", "New Tab", "Terminal", terminal, "plus.rectangle", KeyCombo("T", .command)),
            key("terminal.clear", "Clear Scrollback", "Terminal", terminal, "clear", KeyCombo("K", .command)),

            key("xcode.build", "Build", "Xcode", xcode, "hammer", KeyCombo("B", .command)),
            key("xcode.run", "Run", "Xcode", xcode, "play.fill", KeyCombo("R", .command)),
            key("xcode.stop", "Stop", "Xcode", xcode, "stop.fill", KeyCombo(".", .command)),
            key("xcode.test", "Test", "Xcode", xcode, "checkmark.diamond", KeyCombo("U", .command)),
            key("xcode.cleanBuild", "Clean Build Folder", "Xcode", xcode, "trash", KeyCombo("K", [.command, .shift])),

            AppCommand(id: "music.playPause", title: "Play / Pause", appName: "Music", bundleIdentifier: "com.apple.Music",
                       symbol: "playpause.fill", action: .appleScript("tell application \"Music\" to playpause")),
            AppCommand(id: "music.nextTrack", title: "Next Track", appName: "Music", bundleIdentifier: "com.apple.Music",
                       symbol: "forward.fill", action: .appleScript("tell application \"Music\" to next track")),

            key("system.lockScreen", "Lock Screen", "System", nil, "lock.fill", KeyCombo("Q", [.command, .control])),
            key("system.screenshotArea", "Screenshot Area", "System", nil, "camera.viewfinder", KeyCombo("4", [.command, .shift])),
            key("system.spotlight", "Spotlight", "System", nil, "magnifyingglass", KeyCombo("Space", .command)),
            AppCommand(id: "system.screenshotToolbar", title: "Screenshot Toolbar", appName: "System", bundleIdentifier: nil,
                       symbol: "camera.on.rectangle", action: .openApp("com.apple.screenshot.launcher")),
            AppCommand(id: "system.missionControl", title: "Mission Control", appName: "System", bundleIdentifier: nil,
                       symbol: "rectangle.3.group", action: .openApp("com.apple.exposelauncher")),
            AppCommand(id: "system.emptyTrash", title: "Empty Trash", appName: "System", bundleIdentifier: finder,
                       symbol: "trash", action: .appleScript("tell application \"Finder\" to empty trash")),
        ])
    }()
}
