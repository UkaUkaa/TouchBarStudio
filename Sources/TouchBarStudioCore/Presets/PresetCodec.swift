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
        case .fileTooLarge(let bytes): "The file is too large (\(bytes / 1024) KB; the limit is \(PresetCodec.maxFileBytes / 1024) KB)."
        case .notJSON(let detail): "The file is not a valid preset: \(detail)"
        case .wrongFormat(let f): "This is not a TouchBar Studio preset (format “\(f)”)."
        case .unsupportedVersion(let v): "Preset format version \(v) is not supported. This app reads version \(PresetDocument.currentFormatVersion)."
        case .invalid(let issues): "The preset is invalid:\n" + issues.filter { $0.severity == .error }.map { "• \($0.message)" }.joined(separator: "\n")
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
            throw PresetImportError.notJSON("not a JSON object")
        }
        guard let format = root["format"] as? String else { throw PresetImportError.wrongFormat("missing") }
        guard format == PresetDocument.formatIdentifier else { throw PresetImportError.wrongFormat(format) }
        guard let version = root["formatVersion"] as? Int else { throw PresetImportError.notJSON("missing formatVersion") }
        guard version == PresetDocument.currentFormatVersion else { throw PresetImportError.unsupportedVersion(version) }

        let document: PresetDocument
        do {
            document = try ConfigurationStore.decoder.decode(PresetDocument.self, from: data)
        } catch let DecodingError.dataCorrupted(ctx) {
            throw PresetImportError.notJSON(ctx.debugDescription)
        } catch let DecodingError.keyNotFound(key, _) {
            throw PresetImportError.notJSON("missing field “\(key.stringValue)”")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw PresetImportError.notJSON("wrong value type at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
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

        if preset.name.trimmingCharacters(in: .whitespaces).isEmpty { error("Preset name is empty.") }
        if preset.name.count > maxTitleLength { error("Preset name is longer than \(maxTitleLength) characters.") }
        if preset.items.isEmpty { error("Preset has no items.") }
        if preset.items.count > maxItems { error("Preset has \(preset.items.count) items; the limit is \(maxItems).") }

        var hotKeys = Set<KeyCombo>()
        for (index, item) in preset.items.enumerated() {
            let label = "Item \(index + 1)" + (item.title.isEmpty ? "" : " (“\(item.title.prefix(20))”)")
            if item.title.count > maxTitleLength { error("\(label): title is too long.") }
            if item.kind == .button {
                if item.icon.source == .imageFile { warning("\(label): uses an image file that may not exist on this Mac.") }
                if let hk = item.hotKey {
                    if !hk.isValid || hk.modifiers.isEmpty { error("\(label): hotkey needs at least one modifier and a known key.") }
                    if !hotKeys.insert(hk).inserted { warning("\(label): hotkey \(hk.displayString) is used more than once.") }
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
        if depth > ActionExecutor.maxNestingDepth { error("\(label): sequences are nested too deeply."); return }
        switch action.kind {
        case .none:
            warning("\(label): has no action.")
        case .openApplication:
            if (action.bundleIdentifier ?? "").isEmpty { error("\(label): application is missing.") }
        case .openURL:
            guard let s = action.url, let url = URL(string: s), let scheme = url.scheme?.lowercased() else {
                error("\(label): URL is invalid."); return
            }
            if scheme == "javascript" { error("\(label): javascript: URLs are not allowed.") }
            if scheme == "file" { warning("\(label): opens a local file URL.") }
        case .openFile:
            if (action.path ?? "").isEmpty { error("\(label): path is missing.") }
        case .keyboardShortcut:
            if !(action.keyCombo?.isValid ?? false) { error("\(label): keyboard shortcut is invalid.") }
        case .copyText:
            if (action.text ?? "").count > maxScriptLength { error("\(label): text is too long.") }
        case .appleScript, .shellCommand:
            let s = action.script ?? ""
            if s.isEmpty { error("\(label): script is empty.") }
            if s.count > maxScriptLength { error("\(label): script is too long.") }
            warning("\(label): contains a\(action.kind == .shellCommand ? " shell command" : "n AppleScript"). It will not run until you review and approve it.")
        case .appCommand:
            if catalog.command(id: action.appCommandID ?? "") == nil { error("\(label): unknown app command “\(action.appCommandID ?? "")”.") }
        case .mediaKey:
            if action.mediaKey == nil { error("\(label): media key is missing.") }
        case .sequence:
            let steps = action.steps ?? []
            if steps.isEmpty { error("\(label): sequence is empty.") }
            if steps.count > maxSequenceSteps { error("\(label): sequence has more than \(maxSequenceSteps) steps.") }
            for (i, step) in steps.enumerated() {
                validateAction(step, label: "\(label) step \(i + 1)", depth: depth + 1, catalog: catalog, error: error, warning: warning)
            }
        }
    }
}
