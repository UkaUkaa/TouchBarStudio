import Foundation
import Testing
@testable import TouchBarStudioCore

struct ConfigurationTests {
    func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tbs-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func firstLaunchUsesDefaults() {
        let result = ConfigurationStore(directory: tempDir()).load()
        #expect(result.isFirstLaunch)
        #expect(result.configuration.profiles.count >= 1)
        #expect(result.configuration.profiles.contains { $0.id == result.configuration.defaultProfileID })
    }

    @Test func roundTripsThroughDisk() throws {
        let store = ConfigurationStore(directory: tempDir())
        var config = AppConfiguration.makeDefault()
        config.profiles[0].items.append(.button("Hi", symbol: "star", color: .teal, action: .shortcut(KeyCombo("K", [.command, .shift]), in: "com.apple.Terminal")))
        config.profiles[0].items[0].hotKey = KeyCombo("F5", [.control, .option])
        config.settings.allowShellCommands = true
        config.settings.providerKind = .systemModalExperimental
        try store.save(config)

        let loaded = store.load()
        #expect(!loaded.isFirstLaunch)
        #expect(loaded.recoveredFromError == nil)
        #expect(loaded.configuration == config)
    }

    @Test func corruptFileIsBackedUpNotOverwritten() throws {
        let dir = tempDir()
        let store = ConfigurationStore(directory: dir)
        try Data("{ not json".utf8).write(to: store.configURL)
        let result = store.load()
        #expect(result.recoveredFromError != nil)
        let backup = try #require(result.backupURL)
        #expect(try String(contentsOf: backup, encoding: .utf8) == "{ not json")
    }

    @Test func newerSchemaIsRejected() throws {
        let store = ConfigurationStore(directory: tempDir())
        var json = try JSONSerialization.jsonObject(with: ConfigurationStore.encoder.encode(AppConfiguration.makeDefault())) as! [String: Any]
        json["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: json).write(to: store.configURL)
        let result = store.load()
        #expect(result.recoveredFromError?.contains("newer version") == true)
    }

    @Test func lenientDecodingFillsDefaults() throws {
        let json = #"""
        {"schemaVersion":1,"defaultProfileID":"00000000-0000-0000-0000-000000000000",
         "profiles":[{"name":"Mini","items":[{"title":"X","action":{"kind":"copyText","text":"x"}}]}]}
        """#
        let config = try ConfigurationStore.decoder.decode(AppConfiguration.self, from: Data(json.utf8))
        #expect(config.profiles[0].items[0].kind == .button)
        #expect(config.profiles[0].items[0].showsTitle)
        // Dangling default ID gets repaired.
        #expect(config.defaultProfileID == config.profiles[0].id)
        #expect(config.settings == AppSettings())
    }

    @Test func profileResolution() {
        var config = AppConfiguration.makeDefault()
        let safari = config.profiles.first { $0.bundleIdentifiers.contains("com.apple.Safari") }!
        let other = config.profiles.first { $0.id != config.defaultProfileID && $0.id != safari.id }!

        #expect(ProfileResolver.activeProfile(frontmostBundleIdentifier: "com.apple.Safari", config: config, canFollowFrontmostApp: true).id == safari.id)
        #expect(ProfileResolver.activeProfile(frontmostBundleIdentifier: "com.unknown", config: config, canFollowFrontmostApp: true).id == config.defaultProfileID)
        // Provider that can't follow other apps: manual choice wins.
        config.settings.manualProfileID = other.id
        #expect(ProfileResolver.activeProfile(frontmostBundleIdentifier: "com.apple.Safari", config: config, canFollowFrontmostApp: false).id == other.id)
        config.settings.autoSwitchProfiles = false
        #expect(ProfileResolver.activeProfile(frontmostBundleIdentifier: "com.apple.Safari", config: config, canFollowFrontmostApp: true).id == other.id)
    }

    @MainActor @Test func trustStorePersists() {
        let url = tempDir().appendingPathComponent("trust.json")
        let action = ActionConfig.sequence([.shell("ls"), .appleScript("beep")])
        let store = ScriptTrustStore(fileURL: url)
        #expect(!store.isFullyApproved(action))
        store.approve(action)
        #expect(ScriptTrustStore(fileURL: url).isFullyApproved(action))
        #expect(!ScriptTrustStore(fileURL: url).isApproved(.shell("ls -la")))
    }

    @Test func keyComboDisplay() {
        #expect(KeyCombo("K", [.command, .shift]).displayString == "⇧⌘K")
        #expect(KeyCombo("Space", [.control, .option]).displayString == "⌃⌥Space")
        #expect(!KeyCombo(keyCode: 999, modifiers: .command).isValid)
    }
}
