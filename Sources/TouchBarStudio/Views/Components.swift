import AppKit
import SwiftUI
import TouchBarStudioCore
import UniformTypeIdentifiers

/// Rounded panel used throughout the app.
struct Card<Content: View>: View {
    var title: String?
    var symbol: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label(title, systemImage: symbol ?? "circle").font(.headline)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
    }
}

struct StatusBadge: View {
    enum Style { case ok, warning, error, info }
    var text: String
    var style: Style

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var icon: String {
        switch style {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }

    private var color: Color {
        switch style {
        case .ok: .green
        case .warning: .orange
        case .error: .red
        case .info: .blue
        }
    }
}

/// Image for an app bundle ID, or a generic placeholder.
struct AppIconView: View {
    var bundleIdentifier: String?
    var size: CGFloat = 18

    var body: some View {
        if let id = bundleIdentifier, let image = IconProvider.appIcon(bundleIdentifier: id, size: size) {
            Image(nsImage: image).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed").frame(width: size, height: size).foregroundStyle(.secondary)
        }
    }
}

/// Lets the user pick an app: running apps, or any .app via an open panel.
struct AppPickerButton: View {
    var title: String
    var onPick: (String) -> Void

    var body: some View {
        Menu(title) {
            Section(L("Running Apps")) {
                ForEach(ApplicationProfileManager.runningApps(), id: \.bundleIdentifier) { app in
                    Button(app.name) { onPick(app.bundleIdentifier) }
                }
            }
            Divider()
            Button(L("Choose Application…")) {
                if let id = Self.chooseApplication() { onPick(id) }
            }
        }
        .fixedSize()
    }

    @MainActor
    static func chooseApplication() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L("Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}

/// Text field for a bundle identifier with app name/icon feedback and a picker.
struct BundleIdentifierField: View {
    var label: String
    @Binding var bundleIdentifier: String
    var allowsEmpty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                AppIconView(bundleIdentifier: bundleIdentifier.isEmpty ? nil : bundleIdentifier)
                TextField(label, text: $bundleIdentifier, prompt: Text(allowsEmpty ? L("None") : "com.example.App"))
                    .textFieldStyle(.roundedBorder)
                AppPickerButton(title: L("Pick")) { bundleIdentifier = $0 }
                if allowsEmpty && !bundleIdentifier.isEmpty {
                    Button { bundleIdentifier = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).help(L("Clear"))
                }
            }
            if !bundleIdentifier.isEmpty {
                if let name = IconProvider.appName(bundleIdentifier: bundleIdentifier) {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(L("Not installed on this Mac")).font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}

/// Records a key combination by capturing the next key press while focused.
struct KeyRecorder: View {
    @Binding var combo: KeyCombo?
    var requireModifier = false
    @ViewState private var recording = false
    @ViewState private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? L("Press keys…") : (combo?.displayString ?? L("Record Shortcut")))
                    .frame(minWidth: 110)
                    .monospaced(combo != nil && !recording)
            }
            .buttonStyle(.bordered)
            .tint(recording ? .accentColor : nil)
            .help(L("Click, then press the key combination. Esc cancels."))
            if combo != nil {
                Button { combo = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).help(L("Clear shortcut"))
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 0x35 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                stop()
                return nil
            }
            var mods: KeyCombo.Modifiers = []
            let flags = event.modifierFlags
            if flags.contains(.command) { mods.insert(.command) }
            if flags.contains(.option) { mods.insert(.option) }
            if flags.contains(.control) { mods.insert(.control) }
            if flags.contains(.shift) { mods.insert(.shift) }
            let candidate = KeyCombo(keyCode: event.keyCode, modifiers: mods)
            if candidate.isValid && (!requireModifier || !mods.isEmpty) {
                combo = candidate
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// SF Symbol name field with live preview and a palette of common symbols.
struct SymbolField: View {
    @Binding var name: String
    @ViewState private var showPalette = false

    static let common = [
        "star", "heart", "bolt", "terminal", "hammer", "play.fill", "stop.fill", "playpause.fill",
        "backward.fill", "forward.fill", "speaker.wave.2.fill", "speaker.slash.fill", "globe", "safari",
        "folder", "doc", "doc.text", "note.text", "calendar", "envelope", "message", "phone",
        "camera", "photo", "paintbrush", "paintpalette", "eyedropper", "scissors", "pencil", "trash",
        "magnifyingglass", "gearshape", "lock.fill", "moon.fill", "sun.max", "house", "arrow.clockwise",
        "chevron.backward", "chevron.forward", "plus", "minus", "checkmark", "xmark", "command",
        "keyboard", "clipboard", "link", "cloud", "music.note", "mic", "video", "tv", "gamecontroller",
        "cart", "creditcard", "chart.bar", "list.bullet", "checklist", "curlybraces", "ladybug",
    ]

    var body: some View {
        HStack {
            Image(systemName: IconProvider.isValidSymbol(name) ? name : "questionmark.square.dashed")
                .frame(width: 22)
                .foregroundStyle(IconProvider.isValidSymbol(name) ? .primary : Color.orange)
            TextField(L("SF Symbol name"), text: $name).textFieldStyle(.roundedBorder)
            Button(L("Browse")) { showPalette.toggle() }
                .popover(isPresented: $showPalette) {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34)), count: 8), spacing: 6) {
                            ForEach(Self.common, id: \.self) { symbol in
                                Button { name = symbol; showPalette = false } label: {
                                    Image(systemName: symbol).frame(width: 28, height: 28)
                                }
                                .buttonStyle(.borderless)
                                .help(symbol)
                            }
                        }
                        .padding(10)
                    }
                    .frame(width: 320, height: 260)
                }
        }
        if !name.isEmpty && !IconProvider.isValidSymbol(name) {
            Text(L("“%@” is not an SF Symbol on this Mac.", name)).font(.caption).foregroundStyle(.orange)
        }
    }
}

extension ButtonColor {
    var swiftUIColor: Color {
        nsColor.map(Color.init(nsColor:)) ?? Color(white: 0.27)
    }

    var title: String {
        switch self {
        case .standard: L("Default")
        case .gray: L("Gray")
        case .red: L("Red")
        case .orange: L("Orange")
        case .yellow: L("Yellow")
        case .green: L("Green")
        case .teal: L("Teal")
        case .blue: L("Blue")
        case .indigo: L("Indigo")
        case .purple: L("Purple")
        case .pink: L("Pink")
        }
    }
}

struct ColorSwatchPicker: View {
    @Binding var color: ButtonColor

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ButtonColor.allCases, id: \.self) { c in
                Button { color = c } label: {
                    Circle().fill(c.swiftUIColor)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.primary, lineWidth: color == c ? 2 : 0))
                        .padding(1)
                }
                .buttonStyle(.plain)
                .help(c.title)
                .accessibilityLabel(c.title)
                .accessibilityAddTraits(color == c ? .isSelected : [])
            }
        }
    }
}

/// Icon size in points, with a reset to the standard size.
struct IconSizeSlider: View {
    @Binding var size: Double
    var label = L("Icon size")

    var body: some View {
        LabeledContent(label) {
            HStack {
                Slider(value: $size, in: IconSize.range, step: 1) {
                    EmptyView()
                } minimumValueLabel: {
                    Image(systemName: "star.fill").font(.system(size: 9))
                } maximumValueLabel: {
                    Image(systemName: "star.fill").font(.system(size: 16))
                }
                .frame(minWidth: 140)
                Text(L("%d pt", Int(size))).monospacedDigit().frame(width: 44, alignment: .trailing)
                Button(L("Reset")) { size = IconSize.standard }
                    .disabled(size == IconSize.standard)
            }
        }
    }
}

/// Width in points for buttons or sliders.
struct WidthSlider: View {
    @Binding var width: Double
    var range: ClosedRange<Double> = ButtonWidth.range
    var label = L("Width")

    var body: some View {
        LabeledContent(label) {
            HStack {
                Slider(value: $width, in: range, step: 2) {
                    EmptyView()
                } minimumValueLabel: {
                    Image(systemName: "rectangle.compress.vertical").rotationEffect(.degrees(90))
                } maximumValueLabel: {
                    Image(systemName: "rectangle.expand.vertical").rotationEffect(.degrees(90))
                }
                .frame(minWidth: 140)
                Text(L("%d pt", Int(width))).monospacedDigit().frame(width: 52, alignment: .trailing)
            }
        }
    }
}
