import Foundation

public enum ItemKind: String, Codable, CaseIterable, Sendable {
    case button
    case smallSpace
    case largeSpace
    case flexibleSpace
    /// Live battery percentage and charging state. Runs its action (if any) when tapped.
    case battery
    /// Shows whether the system microphone is muted; tapping toggles it by default.
    case microphone
    /// Current time and/or date. Runs its action (if any) when tapped.
    case clock
    /// Slider for the output volume of the default sound device.
    case volume
    /// Slider for the built-in display's brightness.
    case brightness
}

public struct ButtonIcon: Codable, Hashable, Sendable {
    public enum Source: String, Codable, CaseIterable, Sendable {
        case none
        /// SF Symbol name.
        case symbol
        /// Icon of the app with the given bundle identifier.
        case appIcon
        /// Image file on disk (PNG/PDF/…).
        case imageFile
    }

    public var source: Source
    public var value: String

    public init(source: Source, value: String = "") {
        self.source = source
        self.value = value
    }

    public static let none = ButtonIcon(source: .none)
    public static func symbol(_ name: String) -> ButtonIcon { .init(source: .symbol, value: name) }
    public static func app(_ bundleID: String) -> ButtonIcon { .init(source: .appIcon, value: bundleID) }
}

public enum ButtonColor: String, Codable, CaseIterable, Sendable {
    case standard, gray, red, orange, yellow, green, teal, blue, indigo, purple, pink
}

/// One element of a Touch Bar layout: a button or a spacer.
public struct TouchBarItemConfig: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ItemKind
    public var title: String
    public var showsTitle: Bool
    public var icon: ButtonIcon
    public var color: ButtonColor
    public var action: ActionConfig
    /// Optional global hotkey that triggers the same action as tapping the button.
    public var hotKey: KeyCombo?
    /// Application the button belongs to: used as the default target of keyboard
    /// shortcuts and as an icon source.
    public var associatedBundleIdentifier: String?
    /// Clock widget only.
    public var clockFormat: ClockFormat?
    /// Clock widget with `clockFormat == .custom`.
    public var clockCustom: ClockCustomFormat?
    /// Clock widget: text size in points; nil uses the standard Touch Bar font.
    public var textSize: Double?
    /// Icon size in points; nil uses the default from Settings.
    public var iconSize: Double?
    /// Width in points: nil uses the default from Settings, `ButtonWidth.fitContent` (0)
    /// sizes the button to its content. For sliders it is the width of the track.
    public var width: Double?

    public init(
        id: UUID = UUID(),
        kind: ItemKind = .button,
        title: String = "",
        showsTitle: Bool = true,
        icon: ButtonIcon = .none,
        color: ButtonColor = .standard,
        action: ActionConfig = .none,
        hotKey: KeyCombo? = nil,
        associatedBundleIdentifier: String? = nil,
        clockFormat: ClockFormat? = nil,
        clockCustom: ClockCustomFormat? = nil,
        textSize: Double? = nil,
        iconSize: Double? = nil,
        width: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.showsTitle = showsTitle
        self.icon = icon
        self.color = color
        self.action = action
        self.hotKey = hotKey
        self.associatedBundleIdentifier = associatedBundleIdentifier
        self.clockFormat = clockFormat
        self.clockCustom = clockCustom
        self.textSize = textSize
        self.iconSize = iconSize
        self.width = width
    }

    public static func button(
        _ title: String,
        symbol: String? = nil,
        color: ButtonColor = .standard,
        action: ActionConfig,
        app: String? = nil,
        showsTitle: Bool = true
    ) -> TouchBarItemConfig {
        TouchBarItemConfig(
            title: title,
            showsTitle: showsTitle,
            icon: symbol.map(ButtonIcon.symbol) ?? .none,
            color: color,
            action: action,
            associatedBundleIdentifier: app
        )
    }

    /// Battery widget; tapping opens Battery settings by default.
    public static func battery() -> TouchBarItemConfig {
        TouchBarItemConfig(kind: .battery, title: L("Battery"), action: .openURL(batterySettingsURL))
    }

    /// Microphone widget; tapping toggles system-wide mute by default.
    public static func microphone() -> TouchBarItemConfig {
        TouchBarItemConfig(kind: .microphone, title: L("Microphone"), action: .microphone(.toggle))
    }

    /// Clock widget; tapping opens Calendar by default.
    public static func clock(_ format: ClockFormat = .time) -> TouchBarItemConfig {
        TouchBarItemConfig(kind: .clock, title: L("Clock"), action: .openApp("com.apple.iCal"), clockFormat: format)
    }

    /// Volume slider for the default output device.
    public static func volume() -> TouchBarItemConfig {
        TouchBarItemConfig(kind: .volume, title: L("Volume"))
    }

    /// Brightness slider for the built-in display.
    public static func brightness() -> TouchBarItemConfig {
        TouchBarItemConfig(kind: .brightness, title: L("Brightness"))
    }

    public static let batterySettingsURL = "x-apple.systempreferences:com.apple.Battery-Settings.extension"

    /// Items that are tapped like buttons (have an action, title, color).
    public var isTappable: Bool { kind == .button || kind == .battery || kind == .microphone || kind == .clock }

    /// What a clock widget shows at `date`.
    public func clockText(at date: Date, language: AppLanguage = L10n.language, base: Locale = .autoupdatingCurrent,
                          timeZone: TimeZone = .autoupdatingCurrent) -> String {
        (clockFormat ?? .time).string(from: date, custom: clockCustom, language: language, base: base, timeZone: timeZone)
    }

    /// Icon size in points, using `defaultSize` (from Settings) unless the item has its own.
    public func resolvedIconSize(default defaultSize: Double) -> Double {
        IconSize.clamp(iconSize ?? defaultSize)
    }

    /// Clock text size in points, or nil for the standard font.
    public var resolvedTextSize: Double? {
        textSize.map(TextSize.clamp)
    }

    /// Fixed width in points, or nil when the item fits its content. `defaultWidth` is the
    /// Settings value (nil: fit content); it applies to buttons and widgets, not to spaces
    /// or sliders.
    public func resolvedWidth(default defaultWidth: Double?) -> Double? {
        switch kind {
        case .smallSpace, .largeSpace, .flexibleSpace:
            return nil
        case .volume, .brightness:
            guard let width, width != ButtonWidth.fitContent else { return nil }
            return ButtonWidth.clampSlider(width)
        case .button, .battery, .microphone, .clock:
            let value = width ?? defaultWidth
            guard let value, value != ButtonWidth.fitContent else { return nil }
            return ButtonWidth.clamp(value)
        }
    }

    /// System sliders: dragged, not tapped, and without an action.
    public var isSlider: Bool { kind == .volume || kind == .brightness }

    public static func space(_ kind: ItemKind) -> TouchBarItemConfig {
        TouchBarItemConfig(kind: kind)
    }

    /// Copy with a fresh identity (duplicate / import).
    public func withNewID() -> TouchBarItemConfig {
        var copy = self
        copy.id = UUID()
        return copy
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, showsTitle, icon, color, action, hotKey, associatedBundleIdentifier, clockFormat, clockCustom, textSize, iconSize, width
    }

    // Lenient decoding: missing optional fields fall back to defaults so older or
    // hand-written files still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(ItemKind.self, forKey: .kind) ?? .button
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        showsTitle = try c.decodeIfPresent(Bool.self, forKey: .showsTitle) ?? true
        icon = try c.decodeIfPresent(ButtonIcon.self, forKey: .icon) ?? .none
        color = try c.decodeIfPresent(ButtonColor.self, forKey: .color) ?? .standard
        action = try c.decodeIfPresent(ActionConfig.self, forKey: .action) ?? .none
        hotKey = try c.decodeIfPresent(KeyCombo.self, forKey: .hotKey)
        associatedBundleIdentifier = try c.decodeIfPresent(String.self, forKey: .associatedBundleIdentifier)
        clockFormat = try c.decodeIfPresent(ClockFormat.self, forKey: .clockFormat)
        clockCustom = try c.decodeIfPresent(ClockCustomFormat.self, forKey: .clockCustom)
        textSize = try c.decodeIfPresent(Double.self, forKey: .textSize)
        iconSize = try c.decodeIfPresent(Double.self, forKey: .iconSize)
        width = try c.decodeIfPresent(Double.self, forKey: .width)
    }
}

/// A named layout, optionally associated with one or more applications.
public struct Profile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Bundle identifiers of apps that activate this profile automatically.
    public var bundleIdentifiers: [String]
    public var items: [TouchBarItemConfig]

    public init(id: UUID = UUID(), name: String, bundleIdentifiers: [String] = [], items: [TouchBarItemConfig] = []) {
        self.id = id
        self.name = name
        self.bundleIdentifiers = bundleIdentifiers
        self.items = items
    }

    enum CodingKeys: String, CodingKey { case id, name, bundleIdentifiers, items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        bundleIdentifiers = try c.decodeIfPresent([String].self, forKey: .bundleIdentifiers) ?? []
        items = try c.decodeIfPresent([TouchBarItemConfig].self, forKey: .items) ?? []
    }
}

/// Limits for icon sizes on the Touch Bar (it is 30 pt tall).
public enum IconSize {
    public static let standard: Double = 16
    /// Above 22 pt tall symbols (e.g. the microphone) are clipped by the 30 pt bar.
    public static let range: ClosedRange<Double> = 10...22

    public static func clamp(_ size: Double) -> Double { min(range.upperBound, max(range.lowerBound, size)) }
}

/// Limits for the clock widget's text size (the Touch Bar is 30 pt tall).
public enum TextSize {
    /// Roughly the system font of Touch Bar buttons; the starting value of the slider.
    public static let standard: Double = 15
    public static let range: ClosedRange<Double> = 10...24

    public static func clamp(_ size: Double) -> Double { min(range.upperBound, max(range.lowerBound, size)) }
}

/// Limits for fixed button widths. The Touch Bar is 30 pt tall, so only the width can change.
public enum ButtonWidth {
    /// Stored as an item's `width` to fit the content even when Settings set a fixed width.
    public static let fitContent: Double = 0
    public static let range: ClosedRange<Double> = 30...300
    public static let sliderRange: ClosedRange<Double> = 60...400
    /// Starting value when a fixed width is first turned on.
    public static let standard: Double = 72

    public static func clamp(_ width: Double) -> Double { min(range.upperBound, max(range.lowerBound, width)) }
    public static func clampSlider(_ width: Double) -> Double { min(sliderRange.upperBound, max(sliderRange.lowerBound, width)) }
}
