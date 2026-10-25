import Foundation

/// A reusable layout template.
public struct Preset: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var summary: String
    public var symbol: String
    public var items: [TouchBarItemConfig]
    /// Apps this preset is designed for (used when creating a profile from it).
    public var suggestedBundleIdentifiers: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        summary: String = "",
        symbol: String = "square.grid.2x2",
        items: [TouchBarItemConfig],
        suggestedBundleIdentifiers: [String] = []
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbol = symbol
        self.items = items
        self.suggestedBundleIdentifiers = suggestedBundleIdentifiers
    }

    enum CodingKeys: String, CodingKey { case id, name, summary, symbol, items, suggestedBundleIdentifiers }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "square.grid.2x2"
        items = try c.decode([TouchBarItemConfig].self, forKey: .items)
        suggestedBundleIdentifiers = try c.decodeIfPresent([String].self, forKey: .suggestedBundleIdentifiers) ?? []
    }

    /// Creates a profile whose items are fresh copies of the preset's items.
    public func makeProfile(named name: String? = nil, bundleIdentifiers: [String]? = nil) -> Profile {
        Profile(
            name: name ?? self.name,
            bundleIdentifiers: bundleIdentifiers ?? suggestedBundleIdentifiers,
            items: items.map { $0.withNewID() }
        )
    }
}

/// On-disk envelope for exported presets: `*.tbpreset.json`.
public struct PresetDocument: Codable, Sendable {
    public static let formatIdentifier = "com.touchbarstudio.preset"
    public static let currentFormatVersion = 1
    public static let fileExtension = "json"

    public var format: String
    public var formatVersion: Int
    public var exportedAt: Date?
    public var preset: Preset

    public init(preset: Preset, exportedAt: Date = Date()) {
        self.format = Self.formatIdentifier
        self.formatVersion = Self.currentFormatVersion
        self.exportedAt = exportedAt
        self.preset = preset
    }
}
