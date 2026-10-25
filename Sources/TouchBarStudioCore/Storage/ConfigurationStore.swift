import Foundation

/// Loads and saves `config.json` in Application Support. Writes are atomic; an
/// unreadable file is moved aside (never silently overwritten) and defaults are used.
public final class ConfigurationStore: Sendable {
    public struct LoadResult: Sendable {
        public var configuration: AppConfiguration
        /// Set when the existing file could not be read and was backed up.
        public var recoveredFromError: String?
        public var backupURL: URL?
        public var isFirstLaunch: Bool
    }

    public let directory: URL
    public var configURL: URL { directory.appendingPathComponent("config.json") }
    public var trustURL: URL { directory.appendingPathComponent("approved-scripts.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TouchBarStudio", isDirectory: true)
    }

    public func load() -> LoadResult {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: configURL) else {
            return LoadResult(configuration: .makeDefault(), recoveredFromError: nil, backupURL: nil, isFirstLaunch: true)
        }
        do {
            let config = try Self.decoder.decode(AppConfiguration.self, from: data)
            return LoadResult(configuration: config, recoveredFromError: nil, backupURL: nil, isFirstLaunch: false)
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = directory.appendingPathComponent("config.unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: configURL, to: backup)
            let reason = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return LoadResult(configuration: .makeDefault(), recoveredFromError: reason, backupURL: backup, isFirstLaunch: false)
        }
    }

    public func save(_ configuration: AppConfiguration) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(configuration)
        try data.write(to: configURL, options: [.atomic])
    }

    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
