import Foundation

public struct ValidationIssue: Hashable, Sendable, CustomStringConvertible {
    public enum Severity: String, Sendable { case error, warning }
    public var severity: Severity
    public var message: String
    public var description: String { "\(severity.rawValue): \(message)" }
}

public struct PresetImportResult: Sendable {
    public var preset: Preset
    /// Warnings only; any error makes `PresetCodec.importPreset` throw instead.
    public var warnings: [ValidationIssue]
    /// True when the preset contains AppleScript or shell actions. These are never
    /// pre-approved, so they will not run until the user reviews them.
    public var containsScripts: Bool
}

public enum PresetImportError: Error, LocalizedError, Equatable {
    case fileTooLarge(Int)
    case notJSON(String)
    case wrongFormat(String)
    case unsupportedVersion(Int)
    case invalid([ValidationIssue])

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge(let bytes): L("The file is too large (%d KB; the limit is %d KB).", bytes / 1024, PresetCodec.maxFileBytes / 1024)
        case .notJSON(let detail): L("The file is not a valid preset: %@", detail)
        case .wrongFormat(let f): L("This is not a TouchBar Studio preset (format “%@”).", f)
        case .unsupportedVersion(let v): L("Preset format version %d is not supported. This app reads version %d.", v, PresetDocument.currentFormatVersion)
        case .invalid(let issues): L("The preset is invalid:") + "\n" + issues.filter { $0.severity == .error }.map { "• \($0.message)" }.joined(separator: "\n")
        }
    }
}

/// Versioned JSON import/export with validation.
public enum PresetCodec {
    public static let maxFileBytes = 512 * 1024
    public static let maxItems = 48
    public static let maxTitleLength = 64
    public static let maxScriptLength = 20_000
    public static let maxSequenceSteps = 20

    public static func export(_ preset: Preset) throws -> Data {
        try ConfigurationStore.encoder.encode(PresetDocument(preset: preset))
    }

    /// Decodes and validates a preset file. Imported items always receive new IDs.
    public static func importPreset(from data: Data, catalog: AppCommandCatalog = .standard) throws -> PresetImportResult {
        guard data.count <= maxFileBytes else { throw PresetImportError.fileTooLarge(data.count) }

        // Check the envelope before decoding the payload, so a wrong file type gets a clear message.
        guard let object = try? JSONSerialization.jsonObject(with: data), let root = object as? [String: Any] else {
            throw PresetImportError.notJSON(L("not a JSON object"))
        }
        guard let format = root["format"] as? String else { throw PresetImportError.wrongFormat("missing") }
        guard format == PresetDocument.formatIdentifier else { throw PresetImportError.wrongFormat(format) }
        guard let version = root["formatVersion"] as? Int else { throw PresetImportError.notJSON(L("missing formatVersion")) }
        guard version == PresetDocument.currentFormatVersion else { throw PresetImportError.unsupportedVersion(version) }

        let document: PresetDocument
        do {
            document = try ConfigurationStore.decoder.decode(PresetDocument.self, from: data)
        } catch let DecodingError.dataCorrupted(ctx) {
            throw PresetImportError.notJSON(ctx.debugDescription)
        } catch let DecodingError.keyNotFound(key, _) {
            throw PresetImportError.notJSON(L("missing field “%@”", key.stringValue))
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw PresetImportError.notJSON(L("wrong value type at %@", ctx.codingPath.map(\.stringValue).joined(separator: ".")))
        } catch {
            throw PresetImportError.notJSON(error.localizedDescription)
        }

        var preset = document.preset
        let issues = validate(preset, catalog: catalog)
        if issues.contains(where: { $0.severity == .error }) { throw PresetImportError.invalid(issues) }

        preset.id = UUID()
        preset.items = preset.items.map { $0.withNewID() }
        return PresetImportResult(
            preset: preset,
            warnings: issues,
            containsScripts: preset.items.contains { $0.action.containsScript }
        )
    }

    public static func validate(_ preset: Preset, catalog: AppCommandCatalog = .standard) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func error(_ m: String) { issues.append(.init(severity: .error, message: m)) }
        func warning(_ m: String) { issues.append(.init(severity: .warning, message: m)) }

        if preset.name.trimmingCharacters(in: .whitespaces).isEmpty { error(L("Preset name is empty.")) }
        if preset.name.count > maxTitleLength { error(L("Preset name is longer than %d characters.", maxTitleLength)) }
        if preset.items.isEmpty { error(L("Preset has no items.")) }
        if preset.items.count > maxItems { error(L("Preset has %d items; the limit is %d.", preset.items.count, maxItems)) }

        var hotKeys = Set<KeyCombo>()
        for (index, item) in preset.items.enumerated() {
            let label = L("Item %d", index + 1) + (item.title.isEmpty ? "" : " (“\(item.title.prefix(20))”)")
            if item.title.count > maxTitleLength { error(L("%@: title is too long.", label)) }
            if item.kind == .button {
                if item.icon.source == .imageFile { warning(L("%@: uses an image file that may not exist on this Mac.", label)) }
                if let hk = item.hotKey {
                    if !hk.isValid || hk.modifiers.isEmpty { error(L("%@: hotkey needs at least one modifier and a known key.", label)) }
                    if !hotKeys.insert(hk).inserted { warning(L("%@: hotkey %@ is used more than once.", label, hk.displayString)) }
                }
                validateAction(item.action, label: label, depth: 0, catalog: catalog, error: error, warning: warning)
            }
        }
        return issues
    }

    private static func validateAction(
        _ action: ActionConfig, label: String, depth: Int, catalog: AppCommandCatalog,
        error: (String) -> Void, warning: (String) -> Void
    ) {
        if depth > ActionExecutor.maxNestingDepth { error(L("%@: sequences are nested too deeply.", label)); return }
        switch action.kind {
        case .none:
            warning(L("%@: has no action.", label))
        case .openApplication:
            if (action.bundleIdentifier ?? "").isEmpty { error(L("%@: application is missing.", label)) }
        case .openURL:
            guard let s = action.url, let url = URL(string: s), let scheme = url.scheme?.lowercased() else {
                error(L("%@: URL is invalid.", label)); return
            }
            if scheme == "javascript" { error(L("%@: javascript: URLs are not allowed.", label)) }
            if scheme == "file" { warning(L("%@: opens a local file URL.", label)) }
        case .openFile:
            if (action.path ?? "").isEmpty { error(L("%@: path is missing.", label)) }
        case .keyboardShortcut:
            if !(action.keyCombo?.isValid ?? false) { error(L("%@: keyboard shortcut is invalid.", label)) }
        case .copyText:
            if (action.text ?? "").count > maxScriptLength { error(L("%@: text is too long.", label)) }
        case .appleScript, .shellCommand:
            let s = action.script ?? ""
            if s.isEmpty { error(L("%@: script is empty.", label)) }
            if s.count > maxScriptLength { error(L("%@: script is too long.", label)) }
            warning(action.kind == .shellCommand
                    ? L("%@: contains a shell command. It will not run until you review and approve it.", label)
                    : L("%@: contains an AppleScript. It will not run until you review and approve it.", label))
        case .appCommand:
            if catalog.command(id: action.appCommandID ?? "") == nil { error(L("%@: unknown app command “%@”.", label, action.appCommandID ?? "")) }
        case .mediaKey:
            if action.mediaKey == nil { error(L("%@: media key is missing.", label)) }
        case .sequence:
            let steps = action.steps ?? []
            if steps.isEmpty { error(L("%@: sequence is empty.", label)) }
            if steps.count > maxSequenceSteps { error(L("%@: sequence has more than %d steps.", label, maxSequenceSteps)) }
            for (i, step) in steps.enumerated() {
                validateAction(step, label: L("%@ step %d", label, i + 1), depth: depth + 1, catalog: catalog, error: error, warning: warning)
            }
        }
    }
}
