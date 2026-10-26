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
            Section(L("Language")) {
                Picker(L("Interface language"), selection: Binding(
                    get: { model.config.settings.language },
                    set: { model.setLanguage($0) })) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                if model.needsRelaunchForLanguage {
                    HStack {
                        Text(L("Standard macOS menus and file dialogs switch language after a restart."))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(L("Restart Now")) { model.relaunch() }
                    }
                }
            }

            Section(L("Touch Bar Integration")) {
                Picker(L("Mode"), selection: Binding(
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
                    StatusBadge(text: L("Experimental mode unavailable on this macOS version"), style: .warning)
                }
                if model.config.settings.providerKind == .systemModalExperimental {
                    Toggle(L("Keep the system Control Strip and a close button"), isOn: setting(\.keepControlStrip))
                    Text(L("Off: your layout takes the whole Touch Bar (no brightness/volume controls) and there is no close button."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("✕ hides your layout in the app that is in front, until you switch to another app. Next time you return to it, the layout is back."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(L("Switch profiles automatically by frontmost app"), isOn: setting(\.autoSwitchProfiles))
                    .disabled(!model.providerShowsOverOtherApps)
                Toggle(L("Enable global hotkeys for buttons"), isOn: setting(\.enableGlobalHotKeys))
            }

            Section(L("Permissions")) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Accessibility"))
                        Text(PermissionManager.accessibilityReason).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if model.permissions.accessibilityGranted {
                        StatusBadge(text: L("Granted"), style: .ok)
                    } else {
                        Button(L("Grant Access…")) { model.permissions.requestAccessibility() }
                    }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Automation"))
                        Text(PermissionManager.automationReason).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(L("Open Settings…")) { model.permissions.openAutomationSettings() }
                }
                Button(L("Check Again")) { model.permissions.refresh() }
                Text(L("This build is ad-hoc signed: after rebuilding the app, macOS may treat it as a new app and you may need to re-enable Accessibility for it."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L("Security")) {
                Toggle(L("Allow AppleScript actions"), isOn: setting(\.allowAppleScript))
                Toggle(L("Allow shell commands"), isOn: Binding(
                    get: { model.config.settings.allowShellCommands },
                    set: { on in if on { confirmShell = true } else { model.config.settings.allowShellCommands = false } }))
                Stepper(L("Shell command timeout: %d s", model.config.settings.shellTimeoutSeconds),
                        value: setting(\.shellTimeoutSeconds), in: 1...600)
                Text(L("Every AppleScript and shell command must be approved before its first run, and again after any edit. Imported presets never carry approvals."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Revoke All Script Approvals")) { model.revokeAllApprovals() }
            }

            Section(L("General")) {
                Toggle(L("Launch at login"), isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                LabeledContent(L("Configuration folder")) {
                    Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([model.store.configURL]) }
                }
                Button(L("Reset Profiles to Defaults…"), role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .alert(L("Enable experimental mode?"), isPresented: $confirmExperimental) {
            Button(L("Enable")) { model.config.settings.providerKind = .systemModalExperimental }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("This shows your layout over every app using an undocumented macOS API. Apple doesn't support it, and a macOS update may break it. You can switch back at any time."))
        }
        .alert(L("Allow shell commands?"), isPresented: $confirmShell) {
            Button(L("Allow"), role: .destructive) { model.config.settings.allowShellCommands = true }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Shell commands run with your user's full permissions and can modify or delete files. Each command still needs your approval before it first runs."))
        }
        .alert(L("Reset all profiles?"), isPresented: $confirmReset) {
            Button(L("Reset"), role: .destructive) { model.resetToDefaults() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("All profiles and layouts are replaced with the defaults. Settings and custom presets are kept."))
        }
    }
}
