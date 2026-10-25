import Foundation

public enum ItemKind: String, Codable, CaseIterable, Sendable {
    case button
    case smallSpace
    case largeSpace
    case flexibleSpace
    /// Live battery percentage and charging state. Runs its action (if any) when tapped.
    case battery
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

    public init(
        id: UUID = UUID(),
        kind: ItemKind = .button,
        title: String = "",
        showsTitle: Bool = true,
        icon: ButtonIcon = .none,
        color: ButtonColor = .standard,
        action: ActionConfig = .none,
        hotKey: KeyCombo? = nil,
        associatedBundleIdentifier: String? = nil
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

    public static let batterySettingsURL = "x-apple.systempreferences:com.apple.Battery-Settings.extension"

    /// Items that are tapped like buttons (have an action, title, color).
    public var isTappable: Bool { kind == .button || kind == .battery }

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
        case id, kind, title, showsTitle, icon, color, action, hotKey, associatedBundleIdentifier
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
