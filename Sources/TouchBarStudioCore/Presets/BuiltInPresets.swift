import Foundation

/// Presets shipped with the app. Every action uses a real handler; apps that are not
/// installed on a given Mac are reported by preflight, not faked.
public enum BuiltInPresets {
    public static var all: [Preset] { [developer, browser, writer, productivity, creative, finder] }

    // Stable IDs so the UI can tell built-ins apart from user presets.
    private static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }

    public static let developer = Preset(
        id: id(1), name: "Developer", summary: "Terminal, Xcode build/run/stop, VS Code and GitHub.",
        symbol: "chevron.left.forwardslash.chevron.right",
        items: [
            .button("Terminal", symbol: "terminal", action: .openApp("com.apple.Terminal"), showsTitle: false),
            .button("VS Code", symbol: "curlybraces", color: .blue, action: .openApp("com.microsoft.VSCode"), showsTitle: false),
            .space(.smallSpace),
            .button("Build", symbol: "hammer", action: .command("xcode.build")),
            .button("Run", symbol: "play.fill", color: .green, action: .command("xcode.run"), showsTitle: false),
            .button("Stop", symbol: "stop.fill", color: .red, action: .command("xcode.stop"), showsTitle: false),
            .space(.smallSpace),
            .button("GitHub", symbol: "globe", action: .openURL("https://github.com"), showsTitle: false),
            .button("Activity Monitor", symbol: "gauge.with.dots.needle.33percent", action: .openApp("com.apple.ActivityMonitor"), showsTitle: false),
        ],
        suggestedBundleIdentifiers: ["com.apple.dt.Xcode"]
    )

    public static let browser = Preset(
        id: id(2), name: "Browser", summary: "Navigation, tabs, reload and reader mode for Safari.",
        symbol: "safari",
        items: [
            .button("Back", symbol: "chevron.backward", action: .command("safari.back"), showsTitle: false),
            .button("Forward", symbol: "chevron.forward", action: .command("safari.forward"), showsTitle: false),
            .button("Reload", symbol: "arrow.clockwise", action: .command("safari.reload"), showsTitle: false),
            .space(.smallSpace),
            .button("New Tab", symbol: "plus.square.on.square", action: .command("safari.newTab")),
            .button("Reopen", symbol: "arrow.uturn.backward", action: .command("safari.reopenTab")),
            .button("Reader", symbol: "doc.plaintext", action: .command("safari.readerMode")),
        ],
        suggestedBundleIdentifiers: ["com.apple.Safari"]
    )

    public static let writer = Preset(
        id: id(3), name: "Writer", summary: "TextEdit, Notes, Dictionary, formatting and an em dash.",
        symbol: "pencil.and.outline",
        items: [
            .button("TextEdit", symbol: "doc.text", action: .openApp("com.apple.TextEdit"), showsTitle: false),
            .button("Notes", symbol: "note.text", color: .yellow, action: .openApp("com.apple.Notes"), showsTitle: false),
            .button("Dictionary", symbol: "character.book.closed", action: .openApp("com.apple.Dictionary"), showsTitle: false),
            .space(.smallSpace),
            .button("Bold", symbol: "bold", action: .shortcut(KeyCombo("B", .command)), showsTitle: false),
            .button("Italic", symbol: "italic", action: .shortcut(KeyCombo("I", .command)), showsTitle: false),
            .button("Underline", symbol: "underline", action: .shortcut(KeyCombo("U", .command)), showsTitle: false),
            .space(.smallSpace),
            .button("—", action: .copy("—")),
        ],
        suggestedBundleIdentifiers: ["com.apple.TextEdit"]
    )

    public static let productivity = Preset(
        id: id(4), name: "Productivity", summary: "Calendar, Mail, Reminders, Notes, screenshots and lock screen.",
        symbol: "checklist",
        items: [
            .button("Calendar", symbol: "calendar", action: .openApp("com.apple.iCal"), showsTitle: false),
            .button("Mail", symbol: "envelope", action: .openApp("com.apple.mail"), showsTitle: false),
            .button("Reminders", symbol: "checklist", action: .openApp("com.apple.reminders"), showsTitle: false),
            .button("Notes", symbol: "note.text", color: .yellow, action: .openApp("com.apple.Notes")),
            .space(.smallSpace),
            .button("Calculator", symbol: "plus.forwardslash.minus", color: .orange, action: .openApp("com.apple.calculator"), showsTitle: false),
            .button("Screenshot", symbol: "camera.on.rectangle", action: .command("system.screenshotToolbar"), showsTitle: false),
            .button("Lock Screen", symbol: "lock.fill", action: .command("system.lockScreen"), showsTitle: false),
        ]
    )

    public static let creative = Preset(
        id: id(5), name: "Creative Work", summary: "Photos, Preview, Color Meter, screenshots and music controls.",
        symbol: "paintpalette",
        items: [
            .button("Photos", symbol: "photo.on.rectangle", action: .openApp("com.apple.Photos"), showsTitle: false),
            .button("Preview", symbol: "eye", action: .openApp("com.apple.Preview")),
            .button("Color Meter", symbol: "eyedropper", color: .purple, action: .openApp("com.apple.DigitalColorMeter"), showsTitle: false),
            .button("Screenshot Area", symbol: "camera.viewfinder", action: .command("system.screenshotArea"), showsTitle: false),
            .space(.smallSpace),
            .button("Previous", symbol: "backward.fill", action: .media(.previous), showsTitle: false),
            .button("Play/Pause", symbol: "playpause.fill", color: .pink, action: .media(.playPause), showsTitle: false),
            .button("Next", symbol: "forward.fill", action: .media(.next), showsTitle: false),
        ]
    )

    public static let finder = Preset(
        id: id(6), name: "Finder", summary: "New window, Home, Downloads, hidden files and Get Info.",
        symbol: "folder",
        items: [
            .button("New", symbol: "macwindow.badge.plus", action: .command("finder.newWindow")),
            .button("Home", symbol: "house", action: .command("finder.goHome")),
            .button("Downloads", symbol: "arrow.down.circle", action: .openFile("~/Downloads")),
            .button("Hidden", symbol: "eye", action: .command("finder.toggleHidden")),
            .button("Info", symbol: "info.circle", action: .command("finder.getInfo")),
        ],
        suggestedBundleIdentifiers: ["com.apple.finder"]
    )
}
