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

    /// Computed so titles follow the current interface language.
    public static var standard: AppCommandCatalog {
        func key(_ id: String, _ title: String, _ app: String, _ bundle: String?, _ symbol: String, _ combo: KeyCombo) -> AppCommand {
            AppCommand(id: id, title: title, appName: app, bundleIdentifier: bundle, symbol: symbol,
                       action: .shortcut(combo, in: bundle))
        }
        let finder = "com.apple.finder", safari = "com.apple.Safari", terminal = "com.apple.Terminal", xcode = "com.apple.dt.Xcode"
        return AppCommandCatalog(commands: [
            key("finder.newWindow", L("New Window"), "Finder", finder, "macwindow.badge.plus", KeyCombo("N", .command)),
            key("finder.goHome", L("Go to Home"), "Finder", finder, "house", KeyCombo("H", [.command, .shift])),
            key("finder.goDownloads", L("Go to Downloads"), "Finder", finder, "arrow.down.circle", KeyCombo("L", [.command, .option])),
            key("finder.toggleHidden", L("Show/Hide Hidden Files"), "Finder", finder, "eye", KeyCombo(".", [.command, .shift])),
            key("finder.getInfo", L("Get Info"), "Finder", finder, "info.circle", KeyCombo("I", .command)),

            key("safari.newTab", L("New Tab"), "Safari", safari, "plus.square.on.square", KeyCombo("T", .command)),
            key("safari.reopenTab", L("Reopen Closed Tab"), "Safari", safari, "arrow.uturn.backward", KeyCombo("T", [.command, .shift])),
            key("safari.reload", L("Reload Page"), "Safari", safari, "arrow.clockwise", KeyCombo("R", .command)),
            key("safari.back", L("Back"), "Safari", safari, "chevron.backward", KeyCombo("[", .command)),
            key("safari.forward", L("Forward"), "Safari", safari, "chevron.forward", KeyCombo("]", .command)),
            key("safari.readerMode", L("Reader Mode"), "Safari", safari, "doc.plaintext", KeyCombo("R", [.command, .shift])),

            key("terminal.newWindow", L("New Window"), "Terminal", terminal, "terminal", KeyCombo("N", .command)),
            key("terminal.newTab", L("New Tab"), "Terminal", terminal, "plus.rectangle", KeyCombo("T", .command)),
            key("terminal.clear", L("Clear Scrollback"), "Terminal", terminal, "clear", KeyCombo("K", .command)),

            key("xcode.build", L("Build"), "Xcode", xcode, "hammer", KeyCombo("B", .command)),
            key("xcode.run", L("Run"), "Xcode", xcode, "play.fill", KeyCombo("R", .command)),
            key("xcode.stop", L("Stop"), "Xcode", xcode, "stop.fill", KeyCombo(".", .command)),
            key("xcode.test", L("Test"), "Xcode", xcode, "checkmark.diamond", KeyCombo("U", .command)),
            key("xcode.cleanBuild", L("Clean Build Folder"), "Xcode", xcode, "trash", KeyCombo("K", [.command, .shift])),

            AppCommand(id: "music.playPause", title: L("Play / Pause"), appName: "Music", bundleIdentifier: "com.apple.Music",
                       symbol: "playpause.fill", action: .appleScript("tell application \"Music\" to playpause")),
            AppCommand(id: "music.nextTrack", title: L("Next Track"), appName: "Music", bundleIdentifier: "com.apple.Music",
                       symbol: "forward.fill", action: .appleScript("tell application \"Music\" to next track")),

            key("system.lockScreen", L("Lock Screen"), L("System"), nil, "lock.fill", KeyCombo("Q", [.command, .control])),
            key("system.screenshotArea", L("Screenshot Area"), L("System"), nil, "camera.viewfinder", KeyCombo("4", [.command, .shift])),
            key("system.spotlight", L("Spotlight"), L("System"), nil, "magnifyingglass", KeyCombo("Space", .command)),
            AppCommand(id: "system.screenshotToolbar", title: L("Screenshot Toolbar"), appName: L("System"), bundleIdentifier: nil,
                       symbol: "camera.on.rectangle", action: .openApp("com.apple.screenshot.launcher")),
            AppCommand(id: "system.missionControl", title: L("Mission Control"), appName: L("System"), bundleIdentifier: nil,
                       symbol: "rectangle.3.group", action: .openApp("com.apple.exposelauncher")),
            AppCommand(id: "system.emptyTrash", title: L("Empty Trash"), appName: L("System"), bundleIdentifier: finder,
                       symbol: "trash", action: .appleScript("tell application \"Finder\" to empty trash")),
        ])
    }
}
