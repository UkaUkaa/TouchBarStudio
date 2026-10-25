import Foundation

/// Presets shipped with the app. Every action uses a real handler; apps that are not
/// installed on a given Mac are reported by preflight, not faked. Computed so names and
/// button titles follow the interface language when a profile is created from them.
public enum BuiltInPresets {
    public static var all: [Preset] { [developer, browser, writer, productivity, creative, finder] }

    // Stable IDs so the UI can tell built-ins apart from user presets.
    private static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }

    public static var developer: Preset { Preset(
        id: id(1), name: L("Developer"), summary: L("Terminal, Xcode build/run/stop, VS Code and GitHub."),
        symbol: "chevron.left.forwardslash.chevron.right",
        items: [
            .button(L("Terminal"), symbol: "terminal", action: .openApp("com.apple.Terminal"), showsTitle: false),
            .button(L("VS Code"), symbol: "curlybraces", color: .blue, action: .openApp("com.microsoft.VSCode"), showsTitle: false),
            .space(.smallSpace),
            .button(L("Build"), symbol: "hammer", action: .command("xcode.build")),
            .button(L("Run"), symbol: "play.fill", color: .green, action: .command("xcode.run"), showsTitle: false),
            .button(L("Stop"), symbol: "stop.fill", color: .red, action: .command("xcode.stop"), showsTitle: false),
            .space(.smallSpace),
            .button(L("GitHub"), symbol: "globe", action: .openURL("https://github.com"), showsTitle: false),
            .button(L("Activity Monitor"), symbol: "gauge.with.dots.needle.33percent", action: .openApp("com.apple.ActivityMonitor"), showsTitle: false),
        ],
        suggestedBundleIdentifiers: ["com.apple.dt.Xcode"]
    ) }

    public static var browser: Preset { Preset(
        id: id(2), name: L("Browser"), summary: L("Navigation, tabs, reload and reader mode for Safari."),
        symbol: "safari",
        items: [
            .button(L("Back"), symbol: "chevron.backward", action: .command("safari.back"), showsTitle: false),
            .button(L("Forward"), symbol: "chevron.forward", action: .command("safari.forward"), showsTitle: false),
            .button(L("Reload"), symbol: "arrow.clockwise", action: .command("safari.reload"), showsTitle: false),
            .space(.smallSpace),
            .button(L("New Tab"), symbol: "plus.square.on.square", action: .command("safari.newTab"), showsTitle: false),
            .button(L("Reopen"), symbol: "arrow.uturn.backward", action: .command("safari.reopenTab")),
            .button(L("Reader"), symbol: "doc.plaintext", action: .command("safari.readerMode")),
        ],
        suggestedBundleIdentifiers: ["com.apple.Safari"]
    ) }

    public static var writer: Preset { Preset(
        id: id(3), name: L("Writer"), summary: L("TextEdit, Notes, Dictionary, formatting and an em dash."),
        symbol: "pencil.and.outline",
        items: [
            .button(L("TextEdit"), symbol: "doc.text", action: .openApp("com.apple.TextEdit"), showsTitle: false),
            .button(L("Notes"), symbol: "note.text", color: .yellow, action: .openApp("com.apple.Notes"), showsTitle: false),
            .button(L("Dictionary"), symbol: "character.book.closed", action: .openApp("com.apple.Dictionary"), showsTitle: false),
            .space(.smallSpace),
            .button(L("Bold"), symbol: "bold", action: .shortcut(KeyCombo("B", .command)), showsTitle: false),
            .button(L("Italic"), symbol: "italic", action: .shortcut(KeyCombo("I", .command)), showsTitle: false),
            .button(L("Underline"), symbol: "underline", action: .shortcut(KeyCombo("U", .command)), showsTitle: false),
            .space(.smallSpace),
            .button("—", action: .copy("—")),
        ],
        suggestedBundleIdentifiers: ["com.apple.TextEdit"]
    ) }

    public static var productivity: Preset { Preset(
        id: id(4), name: L("Productivity"), summary: L("Calendar, Mail, Reminders, Notes, screenshots and lock screen."),
        symbol: "checklist",
        items: [
            .button(L("Calendar"), symbol: "calendar", action: .openApp("com.apple.iCal"), showsTitle: false),
            .button(L("Mail"), symbol: "envelope", action: .openApp("com.apple.mail"), showsTitle: false),
            .button(L("Reminders"), symbol: "checklist", action: .openApp("com.apple.reminders"), showsTitle: false),
            .button(L("Notes"), symbol: "note.text", color: .yellow, action: .openApp("com.apple.Notes")),
            .space(.smallSpace),
            .button(L("Calculator"), symbol: "plus.forwardslash.minus", color: .orange, action: .openApp("com.apple.calculator"), showsTitle: false),
            .button(L("Screenshot"), symbol: "camera.on.rectangle", action: .command("system.screenshotToolbar"), showsTitle: false),
            .button(L("Lock Screen"), symbol: "lock.fill", action: .command("system.lockScreen"), showsTitle: false),
        ]
    ) }

    public static var creative: Preset { Preset(
        id: id(5), name: L("Creative Work"), summary: L("Photos, Preview, Color Meter, screenshots and music controls."),
        symbol: "paintpalette",
        items: [
            .button(L("Photos"), symbol: "photo.on.rectangle", action: .openApp("com.apple.Photos"), showsTitle: false),
            .button(L("Preview"), symbol: "eye", action: .openApp("com.apple.Preview")),
            .button(L("Color Meter"), symbol: "eyedropper", color: .purple, action: .openApp("com.apple.DigitalColorMeter"), showsTitle: false),
            .button(L("Screenshot Area"), symbol: "camera.viewfinder", action: .command("system.screenshotArea"), showsTitle: false),
            .space(.smallSpace),
            .button(L("Previous"), symbol: "backward.fill", action: .media(.previous), showsTitle: false),
            .button(L("Play/Pause"), symbol: "playpause.fill", color: .pink, action: .media(.playPause), showsTitle: false),
            .button(L("Next"), symbol: "forward.fill", action: .media(.next), showsTitle: false),
        ]
    ) }

    public static var finder: Preset { Preset(
        id: id(6), name: L("Finder"), summary: L("New window, Home, Downloads, hidden files and Get Info."),
        symbol: "folder",
        items: [
            .button(L("New"), symbol: "macwindow.badge.plus", action: .command("finder.newWindow")),
            .button(L("Home"), symbol: "house", action: .command("finder.goHome")),
            .button(L("Downloads"), symbol: "arrow.down.circle", action: .openFile("~/Downloads")),
            .button(L("Hidden"), symbol: "eye", action: .command("finder.toggleHidden")),
            .button(L("Info"), symbol: "info.circle", action: .command("finder.getInfo")),
        ],
        suggestedBundleIdentifiers: ["com.apple.finder"]
    ) }
}
