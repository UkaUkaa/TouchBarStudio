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
                        Text(profile.name)
                        Spacer()
                        if profile.id == model.config.defaultProfileID {
                            Text("Default").font(.caption).foregroundStyle(.secondary)
                        }
                        if profile.id == model.displayedProfileID {
                            Image(systemName: "rectangle.and.hand.point.up.left.filled").foregroundStyle(.green)
                                .help("On the Touch Bar now")
                        }
                    }
                    .tag(profile.id)
                    .contextMenu {
                        Button("Duplicate") { selection = model.duplicateProfile(profile.id) }
                        Button("Set as Default") { model.config.defaultProfileID = profile.id }
                        Button("Delete", role: .destructive) { confirmDelete = profile.id }
                            .disabled(model.config.profiles.count < 2)
                    }
                }
            }
            .frame(width: 250)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Menu {
                        Button("Empty Profile") { selection = model.addProfile(Profile(name: "New Profile")) }
                        Divider()
                        ForEach(model.allPresets) { preset in
                            Button("From “\(preset.name)”") { selection = model.addProfile(preset.makeProfile()) }
                        }
                    } label: { Image(systemName: "plus") }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("New profile")
                    Button { if let s = selection { confirmDelete = s } } label: { Image(systemName: "minus") }
                        .disabled(selection == nil || model.config.profiles.count < 2)
                        .help("Delete profile")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }

            Divider()

            Group {
                if let id = selection, model.config.profile(id: id) != nil {
                    ProfileDetailView(profileID: id)
                } else {
                    ContentUnavailableView("Select a Profile", systemImage: "app.badge",
                                           description: Text("Profiles hold separate Touch Bar layouts and can be tied to applications."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if selection == nil { selection = model.config.defaultProfileID } }
        .confirmationDialog("Delete this profile?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let id = confirmDelete {
                    model.deleteProfile(id)
                    model.editor.validateProfile()
                    selection = model.config.defaultProfileID
                }
                confirmDelete = nil
            }
        } message: {
            Text("Its layout will be removed. This can't be undone.")
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
                Section("Profile") {
                    TextField("Name", text: Binding(
                        get: { profile.name },
                        set: { v in model.updateProfile(profileID) { $0.name = v } }))
                    Toggle("Default profile", isOn: Binding(
                        get: { model.config.defaultProfileID == profileID },
                        set: { if $0 { model.config.defaultProfileID = profileID } }))
                        .disabled(model.config.defaultProfileID == profileID)
                    Text("The default profile is shown when no app-specific profile matches.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Applications") {
                    if profile.bundleIdentifiers.isEmpty {
                        Text("Not associated with any app.").foregroundStyle(.secondary)
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
                            .help("Remove association")
                        }
                    }
                    AppPickerButton(title: "Add Application…") { id in model.assign(bundleIdentifier: id, to: profileID) }
                    Text("An app can belong to one profile; adding it here removes it from any other profile.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Automatic Switching") {
                    Toggle("Switch profiles when the frontmost app changes", isOn: Binding(
                        get: { model.config.settings.autoSwitchProfiles },
                        set: { model.config.settings.autoSwitchProfiles = $0 }))
                    if model.providerShowsOverOtherApps {
                        StatusBadge(text: "Supported by the current integration", style: .ok)
                    } else {
                        StatusBadge(text: "No effect with the standard integration", style: .warning)
                        Text("TouchBar Studio detects the frontmost app (now: \(model.apps.lastExternalApp?.name ?? "–")), but the documented Touch Bar API only shows this app's layout while TouchBar Studio itself is active. Enable the experimental “over all apps” mode in Settings to apply profiles in other apps.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Layout") {
                    TouchBarPreview(items: profile.items, selection: .constant(nil), compact: true)
                    Button("Edit Layout") {
                        model.editor.selectProfile(profileID)
                        model.section = .editor
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}
