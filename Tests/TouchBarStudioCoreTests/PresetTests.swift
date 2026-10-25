import Foundation
import Testing
@testable import TouchBarStudioCore

struct PresetTests {
    @Test func builtInPresetsAreValid() {
        #expect(Set(BuiltInPresets.all.map(\.name)).isSuperset(of: ["Developer", "Browser", "Writer", "Productivity", "Creative Work"]))
        for preset in BuiltInPresets.all {
            let errors = PresetCodec.validate(preset).filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(preset.name): \(errors)")
        }
    }

    @Test func builtInPresetsFitNextToControlStrip() {
        // Tightest case: experimental mode with Control Strip and close button.
        let available = LayoutMetrics.availableWidth(showsControlStrip: true, showsCloseButton: true)
        for preset in BuiltInPresets.all {
            #expect(LayoutMetrics.estimatedWidth(of: preset.items) <= available, "\(preset.name) is too wide: \(LayoutMetrics.estimatedWidth(of: preset.items)) > \(available)")
        }
    }

    @Test func exportImportRoundTrip() throws {
        let original = BuiltInPresets.developer
        let data = try PresetCodec.export(original)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["format"] as? String == PresetDocument.formatIdentifier)
        #expect(json["formatVersion"] as? Int == 1)

        let imported = try PresetCodec.importPreset(from: data)
        #expect(imported.preset.name == original.name)
        #expect(imported.preset.items.count == original.items.count)
        // Fresh identities so imports never collide with existing items.
        #expect(imported.preset.id != original.id)
        #expect(Set(imported.preset.items.map(\.id)).isDisjoint(with: original.items.map(\.id)))
        #expect(zip(imported.preset.items, original.items).allSatisfy { $0.action == $1.action && $0.title == $1.title })
        #expect(!imported.containsScripts)
    }

    @Test func rejectsWrongFormat() {
        #expect(throws: PresetImportError.wrongFormat("something.else")) {
            try PresetCodec.importPreset(from: Data(#"{"format":"something.else","formatVersion":1}"#.utf8))
        }
        #expect(throws: PresetImportError.notJSON(L("not a JSON object"))) {
            try PresetCodec.importPreset(from: Data("[1,2]".utf8))
        }
    }

    @Test func rejectsFutureVersion() {
        let json = #"{"format":"com.touchbarstudio.preset","formatVersion":7,"preset":{}}"#
        #expect(throws: PresetImportError.unsupportedVersion(7)) { try PresetCodec.importPreset(from: Data(json.utf8)) }
    }

    @Test func rejectsOversizedFiles() {
        let data = Data(count: PresetCodec.maxFileBytes + 1)
        #expect(throws: PresetImportError.self) { try PresetCodec.importPreset(from: data) }
    }

    @Test func rejectsStructurallyBrokenPayload() {
        let json = #"{"format":"com.touchbarstudio.preset","formatVersion":1,"preset":{"name":"X","items":[{"action":{"kind":"teleport"}}]}}"#
        #expect(throws: PresetImportError.self) { try PresetCodec.importPreset(from: Data(json.utf8)) }
    }

    @Test func rejectsDangerousOrInvalidContent() throws {
        let preset = Preset(name: "Bad", items: [
            .button("JS", action: .openURL("javascript:alert(1)")),
            .button("Cmd", action: .command("does.not.exist")),
            .button("Seq", action: .sequence([])),
        ])
        let data = try PresetCodec.export(preset)
        do {
            _ = try PresetCodec.importPreset(from: data)
            Issue.record("Expected import to fail")
        } catch let PresetImportError.invalid(issues) {
            let messages = issues.map(\.message).joined(separator: "\n")
            #expect(messages.contains("javascript"))
            #expect(messages.contains("does.not.exist"))
            #expect(messages.contains("sequence is empty"))
        }
    }

    @Test func scriptsImportAsWarningsAndStayUnapproved() async throws {
        let preset = Preset(name: "Scripts", items: [.button("Say", action: .shell("say hi"))])
        let result = try PresetCodec.importPreset(from: PresetCodec.export(preset))
        #expect(result.containsScripts)
        #expect(result.warnings.contains { $0.severity == .warning && $0.message.contains("approve") })
        await MainActor.run {
            #expect(!ScriptTrustStore(fileURL: nil).isFullyApproved(result.preset.items[0].action))
        }
    }

    @Test func tooManyItemsIsAnError() {
        let preset = Preset(name: "Huge", items: Array(repeating: .button("x", action: .copy("x")), count: PresetCodec.maxItems + 1))
        #expect(PresetCodec.validate(preset).contains { $0.severity == .error })
    }

    @Test func makeProfileCopiesWithNewIDs() {
        let profile = BuiltInPresets.browser.makeProfile()
        #expect(profile.bundleIdentifiers == ["com.apple.Safari"])
        #expect(Set(profile.items.map(\.id)).isDisjoint(with: BuiltInPresets.browser.items.map(\.id)))
    }
}
