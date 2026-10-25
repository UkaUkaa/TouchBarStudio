import SwiftUI
import TouchBarStudioCore
import UniformTypeIdentifiers

struct PresetsView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var pendingImport: PresetImportResult?
    @ViewState private var importError: String?
    @ViewState private var applyTarget: Preset?
    @ViewState private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L("Presets are layout templates. Apply one to a profile, or create a new profile from it."))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Import…"), systemImage: "square.and.arrow.down") { importPreset() }
                }
                if let message {
                    Banner(text: message, style: .info) { self.message = nil }
                }
                section(L("Built-in"), presets: BuiltInPresets.all)
                section(L("My Presets"), presets: model.config.customPresets)
                if model.config.customPresets.isEmpty {
                    Text(L("Save a layout from the editor with “Save as Preset…”, or import a .json preset file."))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .sheet(item: Binding(get: { pendingImport.map(ImportBox.init) }, set: { pendingImport = $0?.result })) { box in
            ImportReviewSheet(result: box.result) { accept in
                if accept {
                    model.config.customPresets.append(box.result.preset)
                    message = L("Imported “%@”.", box.result.preset.name) + (box.result.containsScripts ? " " + L("Its scripts stay disabled until you approve each one in the editor.") : "")
                }
                pendingImport = nil
            }
        }
        .alert(L("Import Failed"), isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button(L("OK")) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .confirmationDialog(L("Apply “%@”", applyTarget?.name ?? ""), isPresented: Binding(get: { applyTarget != nil }, set: { if !$0 { applyTarget = nil } })) {
            if let preset = applyTarget {
                Button(L("Replace Layout of “%@”", model.editor.profile?.name ?? "")) {
                    model.editor.replaceAll(with: preset.items.map { $0.withNewID() })
                    message = L("Applied “%@” to “%@”. Use Undo in the editor to go back.", preset.name, model.editor.profile?.name ?? "")
                    applyTarget = nil
                }
                Button(L("Create New Profile")) {
                    let id = model.addProfile(preset.makeProfile())
                    model.editor.selectProfile(id)
                    model.section = .editor
                    applyTarget = nil
                }
            }
        } message: {
            Text(L("Replace the layout of the profile open in the editor, or create a new profile from this preset."))
        }
    }

    private func section(_ title: String, presets: [Preset]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 14)], spacing: 14) {
                ForEach(presets) { preset in card(preset) }
            }
        }
    }

    private func card(_ preset: Preset) -> some View {
        Card {
            HStack {
                Image(systemName: preset.symbol).font(.title2).frame(width: 30)
                VStack(alignment: .leading) {
                    Text(preset.name).font(.headline)
                    Text(preset.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
            }
            TouchBarPreview(items: preset.items, selection: .constant(nil), compact: true, showsControlStrip: false)
            HStack {
                Button(L("Apply…")) { applyTarget = preset }
                Button(L("Export…")) { export(preset) }
                Spacer()
                if !model.isBuiltIn(preset) {
                    Button(L("Delete"), role: .destructive) { model.config.customPresets.removeAll { $0.id == preset.id } }
                }
            }
        }
    }

    private func export(_ preset: Preset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(preset.name).tbpreset.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PresetCodec.export(preset).write(to: url, options: .atomic)
            message = L("Exported “%@” to %@.", preset.name, url.lastPathComponent)
        } catch {
            importError = L("Could not write the file: %@", error.localizedDescription)
        }
    }

    private func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? Int, size > PresetCodec.maxFileBytes {
                throw PresetImportError.fileTooLarge(size)
            }
            pendingImport = try PresetCodec.importPreset(from: Data(contentsOf: url))
        } catch {
            importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct ImportBox: Identifiable {
    let result: PresetImportResult
    var id: UUID { result.preset.id }
}

/// Shows what an imported preset contains before it is added. Scripts are listed
/// verbatim so the user sees exactly what they would later approve.
struct ImportReviewSheet: View {
    let result: PresetImportResult
    let completion: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Import “%@”?", result.preset.name)).font(.headline)
            Text(Lp("%d items", result.preset.items.count) + ". " + L("The file passed validation.")).foregroundStyle(.secondary)
            TouchBarPreview(items: result.preset.items, selection: .constant(nil), compact: true, showsControlStrip: false)
            if !result.warnings.isEmpty {
                GroupBox(L("Warnings")) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.warnings, id: \.self) { w in
                            Label(w.message, systemImage: "exclamationmark.triangle").font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if result.containsScripts {
                GroupBox(L("Scripts in this preset (not approved — they will not run)")) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(result.preset.items.flatMap(\.action.scriptActions).enumerated()), id: \.offset) { _, a in
                                VStack(alignment: .leading) {
                                    Text(a.kind == .shellCommand ? L("Shell") : "AppleScript").font(.caption.weight(.semibold))
                                    Text(a.script ?? "").font(.caption.monospaced()).textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
            }
            HStack {
                Spacer()
                Button(L("Cancel")) { completion(false) }.keyboardShortcut(.cancelAction)
                Button(L("Import")) { completion(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
