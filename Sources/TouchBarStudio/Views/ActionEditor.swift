import SwiftUI
import TouchBarStudioCore

/// Edits one `ActionConfig`. Recursive for sequence steps.
struct ActionEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var action: ActionConfig
    var associatedBundleIdentifier: String?
    var depth: Int
    @ViewState private var testResult: Result<String?, ActionError>?
    @ViewState private var testing = false

    private func field<T>(_ keyPath: WritableKeyPath<ActionConfig, T?>, default value: T) -> Binding<T> {
        Binding(get: { action[keyPath: keyPath] ?? value }, set: { action[keyPath: keyPath] = $0 })
    }

    var body: some View {
        Picker("Type", selection: Binding(
            get: { action.kind },
            set: { kind in if kind != action.kind { action = ActionRegistry.template(for: kind) } })) {
            Text("None").tag(ActionKind.none)
            ForEach(ActionRegistry.descriptors.filter { depth < 2 || $0.kind != .sequence }) { d in
                Label(d.title, systemImage: d.symbol).tag(d.kind)
            }
        }
        if let descriptor = ActionRegistry.descriptor(for: action.kind) {
            Text(descriptor.summary).font(.caption).foregroundStyle(.secondary)
        }
        fields
        if action.containsScript { approvalBox }
        if depth == 0 && action.kind != .none { diagnostics }
    }

    @ViewBuilder private var fields: some View {
        switch action.kind {
        case .none:
            EmptyView()
        case .openApplication:
            BundleIdentifierField(label: "Application", bundleIdentifier: field(\.bundleIdentifier, default: ""))
        case .openURL:
            TextField("URL", text: field(\.url, default: ""), prompt: Text("https://example.com"))
        case .openFile:
            HStack {
                TextField("Path", text: field(\.path, default: ""), prompt: Text("~/Documents"))
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = true
                    if panel.runModal() == .OK, let url = panel.url {
                        action.path = (url.path as NSString).abbreviatingWithTildeInPath
                    }
                }
            }
        case .keyboardShortcut:
            LabeledContent("Keys") {
                KeyRecorder(combo: Binding(get: { action.keyCombo }, set: { action.keyCombo = $0 }))
            }
            BundleIdentifierField(label: "Send to app", bundleIdentifier: field(\.targetBundleIdentifier, default: ""), allowsEmpty: true)
            if (action.targetBundleIdentifier ?? "").isEmpty && (associatedBundleIdentifier ?? "").isEmpty && !model.providerShowsOverOtherApps {
                Label("No target app: the keys go to the frontmost app. With the standard integration that is TouchBar Studio itself when you tap the button, so pick a target app.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        case .copyText:
            TextField("Text", text: field(\.text, default: ""), axis: .vertical).lineLimit(2...6)
        case .appleScript:
            scriptEditor(placeholder: "tell application \"Finder\" to activate")
        case .shellCommand:
            scriptEditor(placeholder: "open ~/Projects")
            if !model.config.settings.allowShellCommands {
                Label("Shell commands are disabled. Enable them in Settings › Security.", systemImage: "lock")
                    .font(.caption).foregroundStyle(.orange)
            }
        case .appCommand:
            Picker("Command", selection: field(\.appCommandID, default: "")) {
                ForEach(AppCommandCatalog.standard.groupedByApp, id: \.app) { group in
                    Section(group.app) {
                        ForEach(group.commands) { cmd in Text("\(group.app): \(cmd.title)").tag(cmd.id) }
                    }
                }
            }
            if let cmd = AppCommandCatalog.standard.command(id: action.appCommandID ?? "") {
                Text("Runs: \(cmd.action.summary)").font(.caption).foregroundStyle(.secondary)
            }
        case .mediaKey:
            Picker("Key", selection: field(\.mediaKey, default: .playPause)) {
                ForEach(MediaKey.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
            }
        case .sequence:
            sequenceEditor
        }
    }

    private func scriptEditor(placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: field(\.script, default: ""))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 70, maxHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
            if (action.script ?? "").isEmpty {
                Text("e.g. \(placeholder)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var approvalBox: some View {
        let approved = model.isApproved(action)
        return VStack(alignment: .leading, spacing: 6) {
            if approved {
                Label("Approved. Editing the script requires approving it again.", systemImage: "checkmark.shield")
                    .foregroundStyle(.green).font(.callout)
            } else {
                Label("This action runs code on your Mac and won't run until you approve the exact text above. Approve only scripts you wrote or fully understand.",
                      systemImage: "exclamationmark.shield")
                    .foregroundStyle(.orange).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Approve Script") { model.approve(action) }
            }
        }
    }

    private var sequenceEditor: some View {
        let steps = action.steps ?? []
        return VStack(alignment: .leading, spacing: 8) {
            Stepper("Delay between steps: \(action.delayMilliseconds ?? 0) ms",
                    value: field(\.delayMilliseconds, default: 0), in: 0...5000, step: 50)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                GroupBox {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Step \(index + 1)").font(.caption.weight(.semibold))
                            Spacer()
                            Button { moveStep(index, by: -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(index == 0).help("Move up")
                            Button { moveStep(index, by: 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(index == steps.count - 1).help("Move down")
                            Button(role: .destructive) { action.steps?.remove(at: index) } label: { Image(systemName: "trash") }
                                .help("Remove step")
                        }
                        .buttonStyle(.borderless)
                        AnyView(ActionEditor(
                            action: Binding(
                                get: { (action.steps ?? [])[safe: index] ?? .none },
                                set: { if action.steps?.indices.contains(index) == true { action.steps?[index] = $0 } }),
                            associatedBundleIdentifier: associatedBundleIdentifier,
                            depth: depth + 1))
                    }
                }
            }
            Menu("Add Step") {
                ForEach(ActionRegistry.descriptors.filter { $0.kind != .sequence || depth < 1 }) { d in
                    Button(d.title) { action.steps = steps + [ActionRegistry.template(for: d.kind)] }
                }
            }
            .fixedSize()
        }
    }

    private func moveStep(_ index: Int, by offset: Int) {
        guard var steps = action.steps, steps.indices.contains(index + offset) else { return }
        steps.swapAt(index, index + offset)
        action.steps = steps
    }

    @ViewBuilder private var diagnostics: some View {
        let problems = model.preflight(action, associatedBundleIdentifier: associatedBundleIdentifier)
        ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(problem.localizedDescription).font(.caption).fixedSize(horizontal: false, vertical: true)
                if problem == .accessibilityPermissionRequired {
                    Button("Grant…") { model.section = .settings }.buttonStyle(.link).font(.caption)
                }
            }
        }
        HStack {
            Button {
                testing = true
                Task {
                    testResult = await model.test(action, associatedBundleIdentifier: associatedBundleIdentifier)
                    testing = false
                }
            } label: {
                Label("Test Action", systemImage: "play.circle")
            }
            .disabled(testing)
            if testing { ProgressView().controlSize(.small) }
            switch testResult {
            case .success(let message):
                Label(message ?? "Succeeded", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
            case .failure(let error):
                Label(error.localizedDescription, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            case nil:
                EmptyView()
            }
        }
        .onChange(of: action) { testResult = nil }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
