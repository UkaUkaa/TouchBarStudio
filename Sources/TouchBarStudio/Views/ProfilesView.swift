import SwiftUI
import TouchBarStudioCore

struct ProfilesView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var selection: UUID?
    @ViewState private var confirmDelete: UUID?

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(model.config.profiles) { profile in
                    HStack {
                        if let first = profile.bundleIdentifiers.first {
                            AppIconView(bundleIdentifier: first, size: 18)
                        } else {
                            Image(systemName: "rectangle.stack").frame(width: 18)
                        }
                        Text(profile.name).lineLimit(1)
                        Spacer()
                        if profile.id == model.config.defaultProfileID {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(.secondary)
                                .help(L("Default profile"))
                                .accessibilityLabel(L("Default profile"))
                        }
                        if profile.id == model.displayedProfileID {
                            Image(systemName: "rectangle.and.hand.point.up.left.filled").foregroundStyle(.green)
                                .help(L("On the Touch Bar now"))
                        }
                    }
                    .tag(profile.id)
                    .contextMenu {
                        Button(L("Duplicate")) { selection = model.duplicateProfile(profile.id) }
                        Button(L("Set as Default")) { model.config.defaultProfileID = profile.id }
                        Button(L("Delete"), role: .destructive) { confirmDelete = profile.id }
                            .disabled(model.config.profiles.count < 2)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Menu {
                        Button(L("Empty Profile")) { selection = model.addProfile(Profile(name: "New Profile")) }
                        Divider()
                        ForEach(model.allPresets) { preset in
                            Button(L("From “%@”", preset.name)) { selection = model.addProfile(preset.makeProfile()) }
                        }
                    } label: { Image(systemName: "plus") }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L("New profile"))
                    Button { if let s = selection { confirmDelete = s } } label: { Image(systemName: "minus") }
                        .disabled(selection == nil || model.config.profiles.count < 2)
                        .help(L("Delete profile"))
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 250)

            Divider()

            Group {
                if let id = selection, model.config.profile(id: id) != nil {
                    ProfileDetailView(profileID: id)
                } else {
                    ContentUnavailableView(L("Select a Profile"), systemImage: "app.badge",
                                           description: Text(L("Profiles hold separate Touch Bar layouts and can be tied to applications.")))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if selection == nil { selection = model.config.defaultProfileID } }
        .confirmationDialog(L("Delete this profile?"), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button(L("Delete"), role: .destructive) {
                if let id = confirmDelete {
                    model.deleteProfile(id)
                    model.editor.validateProfile()
                    selection = model.config.defaultProfileID
                }
                confirmDelete = nil
            }
        } message: {
            Text(L("Its layout will be removed. This can't be undone."))
        }
    }
}

struct ProfileDetailView: View {
    @Environment(AppModel.self) private var model
    let profileID: UUID

    private var profile: Profile? { model.config.profile(id: profileID) }

    var body: some View {
        if let profile {
            Form {
                Section(L("Profile")) {
                    TextField(L("Name"), text: Binding(
                        get: { profile.name },
                        set: { v in model.updateProfile(profileID) { $0.name = v } }))
                    Toggle(L("Default profile"), isOn: Binding(
                        get: { model.config.defaultProfileID == profileID },
                        set: { if $0 { model.config.defaultProfileID = profileID } }))
                        .disabled(model.config.defaultProfileID == profileID)
                    Text(L("The default profile is shown when no app-specific profile matches."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section(L("Applications")) {
                    if profile.bundleIdentifiers.isEmpty {
                        Text(L("Not associated with any app.")).foregroundStyle(.secondary)
                    }
                    ForEach(profile.bundleIdentifiers, id: \.self) { id in
                        HStack {
                            AppIconView(bundleIdentifier: id)
                            VStack(alignment: .leading) {
                                Text(IconProvider.appName(bundleIdentifier: id) ?? id)
                                Text(id).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                model.updateProfile(profileID) { $0.bundleIdentifiers.removeAll { $0 == id } }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help(L("Remove association"))
                        }
                    }
                    AppPickerButton(title: L("Add Application…")) { id in model.assign(bundleIdentifier: id, to: profileID) }
                    Text(L("An app can belong to one profile; adding it here removes it from any other profile."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section(L("Automatic Switching")) {
                    Toggle(L("Switch profiles when the frontmost app changes"), isOn: Binding(
                        get: { model.config.settings.autoSwitchProfiles },
                        set: { model.config.settings.autoSwitchProfiles = $0 }))
                    if model.providerShowsOverOtherApps {
                        StatusBadge(text: L("Supported by the current integration"), style: .ok)
                    } else {
                        StatusBadge(text: L("No effect with the standard integration"), style: .warning)
                        Text(L("TouchBar Studio detects the frontmost app (now: %@), but the documented Touch Bar API only shows this app's layout while TouchBar Studio itself is active. Enable the experimental “over all apps” mode in Settings to apply profiles in other apps.", model.apps.lastExternalApp?.name ?? "–"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section(L("Layout")) {
                    TouchBarPreview(items: profile.items, selection: .constant(nil), compact: true)
                    Button(L("Edit Layout")) {
                        model.editor.selectProfile(profileID)
                        model.section = .editor
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}
