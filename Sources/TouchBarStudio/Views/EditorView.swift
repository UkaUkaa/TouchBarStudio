import SwiftUI
import TouchBarStudioCore

struct EditorView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var showSavePreset = false
    @ViewState private var presetName = ""

    private var editor: LayoutEditorViewModel { model.editor }

    var body: some View {
        @Bindable var editor = model.editor
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 16).padding(.vertical, 10)
            TouchBarPreview(
                items: editor.items,
                selection: $editor.selection,
                showsControlStrip: !(model.config.settings.providerKind == .systemModalExperimental && !model.config.settings.keepControlStrip),
                showsCloseButton: model.config.settings.providerKind == .systemModalExperimental && model.config.settings.keepControlStrip,
                onDrop: handleDrop
            )
            .padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            HStack(spacing: 0) {
                ComponentLibraryView()
                    .frame(width: 250)
                Divider()
                ItemListView()
                    .frame(width: 230)
                Divider()
                Group {
                    if let id = editor.selection, editor.items.contains(where: { $0.id == id }) {
                        ItemPropertiesView(itemID: id)
                    } else {
                        ContentUnavailableView(L("No Item Selected"), systemImage: "cursorarrow.click",
                                               description: Text(L("Select an item in the preview or the list, or add one from the library.")))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { editor.validateProfile() }
        .sheet(isPresented: $showSavePreset) { savePresetSheet }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker(L("Profile"), selection: Binding(get: { editor.profileID }, set: { editor.selectProfile($0) })) {
                ForEach(model.config.profiles) { profile in
                    Text(profile.id == model.config.defaultProfileID ? L("%@ (default)", profile.name) : profile.name).tag(profile.id)
                }
            }
            .frame(minWidth: 160, maxWidth: 260)
            if model.displayedProfileID == editor.profileID {
                StatusBadge(text: L("On Touch Bar now"), style: .ok)
            }
            Spacer()
            ControlGroup {
                Button { editor.undo() } label: { Label(L("Undo"), systemImage: "arrow.uturn.backward") }
                    .disabled(!editor.canUndo).help(L("Undo (⌘Z)"))
                Button { editor.redo() } label: { Label(L("Redo"), systemImage: "arrow.uturn.forward") }
                    .disabled(!editor.canRedo).help(L("Redo (⇧⌘Z)"))
            }
            .fixedSize()
            Button(L("Save")) { editor.save() }
                .help(saveHelp)
            Menu {
                Button(L("Revert")) { editor.revertToOpened() }
                    .disabled(!editor.hasChangesSinceOpened)
                Button(L("Save as Preset…")) {
                    presetName = editor.profile?.name ?? L("My Preset")
                    showSavePreset = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("More layout actions"))
        }
    }

    private var saveHelp: String {
        var text = L("Changes are saved automatically; this writes immediately and sets a new revert point (⌘S)")
        if let saved = model.lastSaved {
            text += "\n" + L("Saved %@", saved.formatted(.dateTime.hour().minute().second().locale(L10n.language.locale)))
        }
        return text
    }

    private var savePresetSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Save Layout as Preset")).font(.headline)
            TextField(L("Name"), text: $presetName).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(L("Cancel")) { showSavePreset = false }.keyboardShortcut(.cancelAction)
                Button(L("Save")) {
                    model.saveAsPreset(profileID: editor.profileID, name: presetName.trimmingCharacters(in: .whitespaces), summary: L("Saved from “%@”", editor.profile?.name ?? ""))
                    showSavePreset = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 360)
    }

    private func handleDrop(_ payload: String, before target: UUID?) {
        if payload.hasPrefix("item:"), let id = UUID(uuidString: String(payload.dropFirst(5))) {
            editor.move(id, before: target)
            editor.selection = id
        } else if payload.hasPrefix("component:"), let component = LayoutComponent.named(String(payload.dropFirst(10))) {
            let index = target.flatMap { t in editor.items.firstIndex { $0.id == t } }
            editor.add(component, at: index)
        }
    }
}

struct ComponentLibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section(L("Layout")) {
                ForEach(LayoutComponent.library.filter { $0.group == .layout }) { row($0) }
            }
            Section(L("Widgets")) {
                ForEach(LayoutComponent.library.filter { $0.group == .widget }) { row($0) }
            }
            Section(L("Buttons with Action")) {
                ForEach(LayoutComponent.library.filter { $0.group == .action }) { row($0) }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            Text(L("Component Library")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 8)
        }
    }

    private func row(_ component: LayoutComponent) -> some View {
        HStack {
            Label(component.title, systemImage: component.symbol)
            Spacer()
            Button { model.editor.add(component) } label: { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless)
                .help(L("Add to layout"))
                .accessibilityLabel(L("Add %@", component.title))
        }
        .help(component.title)
        .draggable("component:\(component.id)")
        .onTapGesture(count: 2) { model.editor.add(component) }
    }
}

struct ItemListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var editor = model.editor
        List(selection: $editor.selection) {
            ForEach(editor.items) { item in
                HStack {
                    itemIcon(item).frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title(item)).lineLimit(1)
                        if item.kind == .button {
                            Text(item.action.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        } else if item.kind == .battery {
                            Text(model.battery.status?.percentageText ?? L("No battery"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        } else if item.kind == .microphone {
                            Text(MicrophoneLabel.description(model.microphone.state))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    if item.action.containsScript && !model.isApproved(item.action) {
                        Image(systemName: "exclamationmark.shield").foregroundStyle(.orange).help(L("Contains a script that is not approved"))
                    }
                    if let hk = item.hotKey {
                        Text(hk.displayString).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .tag(item.id)
                .contextMenu {
                    Button(L("Duplicate")) { editor.duplicate(item.id) }
                    Button(L("Delete"), role: .destructive) { editor.delete(item.id) }
                }
            }
            .onMove { editor.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { offsets in
                for i in offsets.sorted(by: >) { editor.delete(editor.items[i].id) }
            }
        }
        .safeAreaInset(edge: .top) {
            Text(L("Items (drag to reorder)")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { editor.add(LayoutComponent.named("button")!) } label: { Image(systemName: "plus") }
                    .help(L("Add button"))
                Button { if let id = editor.selection { editor.delete(id) } } label: { Image(systemName: "minus") }
                    .disabled(editor.selection == nil).help(L("Delete selected"))
                Button { if let id = editor.selection { editor.duplicate(id) } } label: { Image(systemName: "plus.square.on.square") }
                    .disabled(editor.selection == nil).help(L("Duplicate selected"))
                Spacer()
                Button { editor.moveSelection(by: -1) } label: { Image(systemName: "arrow.left") }
                    .disabled(editor.selection == nil).help(L("Move left"))
                Button { editor.moveSelection(by: 1) } label: { Image(systemName: "arrow.right") }
                    .disabled(editor.selection == nil).help(L("Move right"))
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private func title(_ item: TouchBarItemConfig) -> String {
        switch item.kind {
        case .button: item.title.isEmpty ? L("(icon only)") : item.title
        case .smallSpace: L("Small Space")
        case .largeSpace: L("Large Space")
        case .flexibleSpace: L("Flexible Space")
        case .battery: L("Battery")
        case .microphone: L("Microphone")
        }
    }

    @ViewBuilder private func itemIcon(_ item: TouchBarItemConfig) -> some View {
        if item.kind == .battery {
            Image(systemName: model.battery.status?.symbolName ?? "powerplug")
        } else if item.kind == .microphone {
            Image(systemName: model.microphone.state?.symbolName ?? "mic.slash")
        } else if item.kind != .button {
            Image(systemName: "arrow.left.and.right").foregroundStyle(.secondary)
        } else if let image = IconProvider.image(for: item.icon, pointSize: 13) {
            Image(nsImage: image)
        } else {
            Image(systemName: "rectangle").foregroundStyle(.secondary)
        }
    }
}

struct ItemPropertiesView: View {
    @Environment(AppModel.self) private var model
    let itemID: UUID

    private var item: TouchBarItemConfig? { model.editor.items.first { $0.id == itemID } }

    private func binding<T>(_ field: String, _ keyPath: WritableKeyPath<TouchBarItemConfig, T>, default value: T) -> Binding<T> {
        Binding(
            get: { item?[keyPath: keyPath] ?? value },
            set: { newValue in model.editor.update(itemID, field: field) { $0[keyPath: keyPath] = newValue } }
        )
    }

    var body: some View {
        if let item {
            Form {
                if item.kind == .button {
                    buttonSections(item)
                } else if item.kind == .battery {
                    batterySections(item)
                } else if item.kind == .microphone {
                    microphoneSections(item)
                } else {
                    Section(L("Space")) {
                        Picker(L("Size"), selection: binding("kind", \.kind, default: .smallSpace)) {
                            Text(L("Small")).tag(ItemKind.smallSpace)
                            Text(L("Large")).tag(ItemKind.largeSpace)
                            Text(L("Flexible")).tag(ItemKind.flexibleSpace)
                        }
                        Text(L("Spaces separate groups of buttons. A flexible space pushes the following items to the right."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    HStack {
                        Button(L("Duplicate")) { model.editor.duplicate(itemID) }
                        Button(L("Delete"), role: .destructive) { model.editor.delete(itemID) }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private func microphoneSections(_ item: TouchBarItemConfig) -> some View {
        Section(L("Microphone")) {
            LabeledContent(L("Now")) {
                HStack {
                    MicrophoneLabel(state: model.microphone.state)
                    Text(model.microphone.state?.deviceName ?? "").font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(L("Show state text"), isOn: binding("showsTitle", \.showsTitle, default: true))
            LabeledContent(L("Color")) { ColorSwatchPicker(color: binding("color", \.color, default: .standard)) }
            Text(L("Mutes the current input device for every app. The widget turns red while the microphone is muted and follows changes made elsewhere (System Settings, other apps, a headset being plugged in)."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Section {
            ActionEditor(action: binding("action", \.action, default: .none),
                         associatedBundleIdentifier: nil, depth: 0)
        } header: {
            Text(L("On tap"))
        }
        hotKeySection(item)
    }

    @ViewBuilder
    private func hotKeySection(_ item: TouchBarItemConfig) -> some View {
        Section(L("Global hotkey")) {
            KeyRecorder(combo: binding("hotKey", \.hotKey, default: nil), requireModifier: true)
            if let failure = model.hotKeyFailures[itemID] {
                Text(failure).font(.caption).foregroundStyle(.red)
            } else if item.hotKey != nil && !model.config.settings.enableGlobalHotKeys {
                Text(L("Global hotkeys are turned off in Settings.")).font(.caption).foregroundStyle(.orange)
            } else {
                Text(L("Optional. Press it anywhere to run this button's action, even when the button isn't on screen."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func batterySections(_ item: TouchBarItemConfig) -> some View {
        Section(L("Battery")) {
            LabeledContent(L("Now")) {
                HStack {
                    BatteryLabel(status: model.battery.status)
                    if let status = model.battery.status {
                        Text(status.accessibilityDescription).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Toggle(L("Show percentage"), isOn: binding("showsTitle", \.showsTitle, default: true))
            LabeledContent(L("Color")) { ColorSwatchPicker(color: binding("color", \.color, default: .standard)) }
            Text(L("Updates automatically. On battery power the widget turns orange at 20% and red at 10%."))
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            ActionEditor(action: binding("action", \.action, default: .none),
                         associatedBundleIdentifier: nil, depth: 0)
        } header: {
            Text(L("On tap"))
        } footer: {
            Text(L("By default, tapping opens Battery settings. Choose “None” to make it display-only."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func buttonSections(_ item: TouchBarItemConfig) -> some View {
        Section(L("Button")) {
            TextField(L("Title"), text: binding("title", \.title, default: ""))
            Toggle(L("Show title"), isOn: binding("showsTitle", \.showsTitle, default: true))
            Picker(L("Icon"), selection: Binding(
                get: { item.icon.source },
                set: { source in
                    model.editor.update(itemID, field: "iconSource") { config in
                        config.icon.source = source
                        if source == .appIcon, config.icon.value.isEmpty || !config.icon.value.contains(".") {
                            config.icon.value = config.associatedBundleIdentifier ?? config.action.bundleIdentifier ?? ""
                        }
                    }
                })) {
                Text(L("None")).tag(ButtonIcon.Source.none)
                Text(L("SF Symbol")).tag(ButtonIcon.Source.symbol)
                Text(L("App Icon")).tag(ButtonIcon.Source.appIcon)
                Text(L("Image File")).tag(ButtonIcon.Source.imageFile)
            }
            switch item.icon.source {
            case .symbol:
                SymbolField(name: binding("iconValue", \.icon.value, default: ""))
            case .appIcon:
                BundleIdentifierField(label: L("App"), bundleIdentifier: binding("iconValue", \.icon.value, default: ""))
            case .imageFile:
                HStack {
                    TextField(L("Image path"), text: binding("iconValue", \.icon.value, default: ""))
                    Button(L("Choose…")) {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.image]
                        if panel.runModal() == .OK, let url = panel.url {
                            IconProvider.invalidate()
                            model.editor.update(itemID, field: "iconValue") { $0.icon.value = url.path }
                        }
                    }
                }
            case .none:
                EmptyView()
            }
            LabeledContent(L("Color")) { ColorSwatchPicker(color: binding("color", \.color, default: .standard)) }
        }

        Section {
            ActionEditor(
                action: binding("action", \.action, default: .none),
                associatedBundleIdentifier: item.associatedBundleIdentifier,
                depth: 0
            )
        } header: {
            Text(L("Action"))
        }

        Section(L("Options")) {
            BundleIdentifierField(
                label: L("Associated app"),
                bundleIdentifier: Binding(
                    get: { item.associatedBundleIdentifier ?? "" },
                    set: { v in model.editor.update(itemID, field: "app") { $0.associatedBundleIdentifier = v.isEmpty ? nil : v } }),
                allowsEmpty: true
            )
            Text(L("Keyboard shortcuts from this button are sent to the associated app (it is brought to the front first)."))
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent(L("Global hotkey")) {
                KeyRecorder(combo: binding("hotKey", \.hotKey, default: nil), requireModifier: true)
            }
            if let failure = model.hotKeyFailures[itemID] {
                Text(failure).font(.caption).foregroundStyle(.red)
            } else if item.hotKey != nil && !model.config.settings.enableGlobalHotKeys {
                Text(L("Global hotkeys are turned off in Settings.")).font(.caption).foregroundStyle(.orange)
            } else {
                Text(L("Optional. Press it anywhere to run this button's action, even when the button isn't on screen."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
