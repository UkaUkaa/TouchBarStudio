import SwiftUI
import TouchBarStudioCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var confirmExperimental = false
    @ViewState private var confirmShell = false
    @ViewState private var confirmReset = false

    private func setting<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { model.config.settings[keyPath: keyPath] }, set: { model.config.settings[keyPath: keyPath] = $0 })
    }

    var body: some View {
        Form {
            Section("Touch Bar Integration") {
                Picker("Mode", selection: Binding(
                    get: { model.config.settings.providerKind },
                    set: { kind in
                        if kind == .systemModalExperimental { confirmExperimental = true }
                        else { model.config.settings.providerKind = kind }
                    })) {
                    ForEach(TouchBarProviderKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(model.config.settings.providerKind.explanation)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !SystemModalTouchBarProvider.isAvailable {
                    StatusBadge(text: "Experimental mode unavailable on this macOS version", style: .warning)
                }
                if model.config.settings.providerKind == .systemModalExperimental {
                    Toggle("Keep the system Control Strip and a close button", isOn: setting(\.keepControlStrip))
                    Text("Off: your layout takes the whole Touch Bar (no brightness/volume controls). The close button hides the layout until you switch apps or choose Show on Touch Bar.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Switch profiles automatically by frontmost app", isOn: setting(\.autoSwitchProfiles))
                    .disabled(!model.providerShowsOverOtherApps)
                Toggle("Enable global hotkeys for buttons", isOn: setting(\.enableGlobalHotKeys))
            }

            Section("Permissions") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility")
                        Text(PermissionManager.accessibilityReason).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if model.permissions.accessibilityGranted {
                        StatusBadge(text: "Granted", style: .ok)
                    } else {
                        Button("Grant Access…") { model.permissions.requestAccessibility() }
                    }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automation")
                        Text(PermissionManager.automationReason).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Open Settings…") { model.permissions.openAutomationSettings() }
                }
                Button("Check Again") { model.permissions.refresh() }
                Text("This build is ad-hoc signed: after rebuilding the app, macOS may treat it as a new app and you may need to re-enable Accessibility for it.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Security") {
                Toggle("Allow AppleScript actions", isOn: setting(\.allowAppleScript))
                Toggle("Allow shell commands", isOn: Binding(
                    get: { model.config.settings.allowShellCommands },
                    set: { on in if on { confirmShell = true } else { model.config.settings.allowShellCommands = false } }))
                Stepper("Shell command timeout: \(model.config.settings.shellTimeoutSeconds) s",
                        value: setting(\.shellTimeoutSeconds), in: 1...600)
                Text("Every AppleScript and shell command must be approved before its first run, and again after any edit. Imported presets never carry approvals.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Revoke All Script Approvals") { model.revokeAllApprovals() }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                LabeledContent("Configuration folder") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.configURL]) }
                }
                Button("Reset Profiles to Defaults…", role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .alert("Enable experimental mode?", isPresented: $confirmExperimental) {
            Button("Enable") { model.config.settings.providerKind = .systemModalExperimental }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This shows your layout over every app using an undocumented macOS API. Apple doesn't support it, and a macOS update may break it. You can switch back at any time.")
        }
        .alert("Allow shell commands?", isPresented: $confirmShell) {
            Button("Allow", role: .destructive) { model.config.settings.allowShellCommands = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shell commands run with your user's full permissions and can modify or delete files. Each command still needs your approval before it first runs.")
        }
        .alert("Reset all profiles?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All profiles and layouts are replaced with the defaults. Settings and custom presets are kept.")
        }
    }
}
