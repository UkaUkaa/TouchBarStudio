import Foundation

/// Which mechanism puts the layout on the physical Touch Bar.
public enum TouchBarProviderKind: String, Codable, CaseIterable, Sendable {
    /// Public AppKit API. Visible only while TouchBar Studio is the active app.
    case application
    /// Undocumented system-modal API. Visible over every app. Opt-in only.
    case systemModalExperimental
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var providerKind: TouchBarProviderKind
    /// Switch profiles when the frontmost app changes (only meaningful with a provider
    /// that stays visible over other apps).
    public var autoSwitchProfiles: Bool
    /// Profile shown when no app-specific profile applies or auto-switching is off.
    public var manualProfileID: UUID?
    /// Shell commands are disabled until the user turns this on.
    public var allowShellCommands: Bool
    public var allowAppleScript: Bool
    public var shellTimeoutSeconds: Int
    /// Experimental mode: keep the system Control Strip and a close button.
    public var keepControlStrip: Bool
    public var enableGlobalHotKeys: Bool
    public var language: AppLanguage
    /// Default icon size on the Touch Bar, in points; items can override it.
    public var iconSize: Double
    /// Fixed width of every button and widget in points; nil fits each to its content.
    /// Items can override it.
    public var buttonWidth: Double?
    /// Bundle identifiers of apps that always keep their own Touch Bar: the layout is not
    /// shown while one of them is in front (experimental mode only).
    public var ownTouchBarApps: [String]

    public init(
        providerKind: TouchBarProviderKind = .application,
        autoSwitchProfiles: Bool = true,
        manualProfileID: UUID? = nil,
        allowShellCommands: Bool = false,
        allowAppleScript: Bool = true,
        shellTimeoutSeconds: Int = 30,
        keepControlStrip: Bool = true,
        enableGlobalHotKeys: Bool = true,
        language: AppLanguage = .system,
        iconSize: Double = IconSize.standard,
        buttonWidth: Double? = nil,
        ownTouchBarApps: [String] = []
    ) {
        self.providerKind = providerKind
        self.autoSwitchProfiles = autoSwitchProfiles
        self.manualProfileID = manualProfileID
        self.allowShellCommands = allowShellCommands
        self.allowAppleScript = allowAppleScript
        self.shellTimeoutSeconds = shellTimeoutSeconds
        self.keepControlStrip = keepControlStrip
        self.enableGlobalHotKeys = enableGlobalHotKeys
        self.language = language
        self.iconSize = iconSize
        self.buttonWidth = buttonWidth
        self.ownTouchBarApps = ownTouchBarApps
    }

    enum CodingKeys: String, CodingKey {
        case providerKind, autoSwitchProfiles, manualProfileID, allowShellCommands, allowAppleScript
        case shellTimeoutSeconds, keepControlStrip, enableGlobalHotKeys, language, iconSize, buttonWidth
        case ownTouchBarApps
    }

    public init(from decoder: Decoder) throws {
        let d = AppSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providerKind = (try? c.decodeIfPresent(TouchBarProviderKind.self, forKey: .providerKind)) ?? d.providerKind
        autoSwitchProfiles = try c.decodeIfPresent(Bool.self, forKey: .autoSwitchProfiles) ?? d.autoSwitchProfiles
        manualProfileID = try c.decodeIfPresent(UUID.self, forKey: .manualProfileID)
        allowShellCommands = try c.decodeIfPresent(Bool.self, forKey: .allowShellCommands) ?? d.allowShellCommands
        allowAppleScript = try c.decodeIfPresent(Bool.self, forKey: .allowAppleScript) ?? d.allowAppleScript
        shellTimeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .shellTimeoutSeconds) ?? d.shellTimeoutSeconds
        keepControlStrip = try c.decodeIfPresent(Bool.self, forKey: .keepControlStrip) ?? d.keepControlStrip
        enableGlobalHotKeys = try c.decodeIfPresent(Bool.self, forKey: .enableGlobalHotKeys) ?? d.enableGlobalHotKeys
        language = (try? c.decodeIfPresent(AppLanguage.self, forKey: .language)) ?? d.language
        iconSize = IconSize.clamp((try? c.decodeIfPresent(Double.self, forKey: .iconSize)) ?? d.iconSize)
        buttonWidth = (try? c.decodeIfPresent(Double.self, forKey: .buttonWidth)).flatMap { $0 }.map(ButtonWidth.clamp)
        ownTouchBarApps = (try? c.decodeIfPresent([String].self, forKey: .ownTouchBarApps)) ?? d.ownTouchBarApps
    }
}

/// Everything persisted in `config.json`.
public struct AppConfiguration: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var profiles: [Profile]
    public var defaultProfileID: UUID
    public var settings: AppSettings
    public var customPresets: [Preset]

    public init(profiles: [Profile], defaultProfileID: UUID, settings: AppSettings = AppSettings(), customPresets: [Preset] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.profiles = profiles
        self.defaultProfileID = defaultProfileID
        self.settings = settings
        self.customPresets = customPresets
    }

    enum CodingKeys: String, CodingKey { case schemaVersion, profiles, defaultProfileID, settings, customPresets }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw ConfigurationError.unsupportedSchemaVersion(schemaVersion)
        }
        profiles = try c.decode([Profile].self, forKey: .profiles)
        defaultProfileID = try c.decode(UUID.self, forKey: .defaultProfileID)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        customPresets = try c.decodeIfPresent([Preset].self, forKey: .customPresets) ?? []
        schemaVersion = Self.currentSchemaVersion
        normalize()
    }

    /// Repairs invariants: at least one profile exists and the default/manual IDs point at real profiles.
    public mutating func normalize() {
        if profiles.isEmpty {
            let p = Profile(name: L("Default"))
            profiles = [p]
            defaultProfileID = p.id
        }
        if !profiles.contains(where: { $0.id == defaultProfileID }) {
            defaultProfileID = profiles[0].id
        }
        if let m = settings.manualProfileID, !profiles.contains(where: { $0.id == m }) {
            settings.manualProfileID = nil
        }
    }

    public var defaultProfile: Profile {
        profiles.first { $0.id == defaultProfileID } ?? profiles[0]
    }

    public func profile(id: UUID) -> Profile? { profiles.first { $0.id == id } }

    public static func makeDefault() -> AppConfiguration {
        let base = BuiltInPresets.productivity.makeProfile(named: L("Default"))
        let finder = BuiltInPresets.finder.makeProfile(named: "Finder", bundleIdentifiers: ["com.apple.finder"])
        let safari = BuiltInPresets.browser.makeProfile(named: "Safari", bundleIdentifiers: ["com.apple.Safari"])
        return AppConfiguration(profiles: [base, finder, safari], defaultProfileID: base.id)
    }
}

public enum ConfigurationError: Error, LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let v):
            L("The configuration was written by a newer version of TouchBar Studio (schema %d).", v)
        }
    }
}
