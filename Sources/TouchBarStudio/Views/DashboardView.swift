import SwiftUI
import TouchBarStudioCore

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    integrationCard
                    profileCard
                }
                HStack(alignment: .top, spacing: 16) {
                    permissionsCard
                    quickTestCard
                }
                ActivityLogView(limit: 8)
            }
            .padding(20)
        }
    }

    private var integrationCard: some View {
        Card(title: "Touch Bar Integration", symbol: "rectangle.and.hand.point.up.left") {
            HStack {
                Text(model.touchBar.provider.kind.title).font(.title3.weight(.semibold))
                Spacer()
                if model.touchBarHidden {
                    StatusBadge(text: "Hidden", style: .warning)
                } else {
                    StatusBadge(text: "Active", style: .ok)
                }
            }
            Text(model.touchBar.provider.kind.explanation)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !model.providerShowsOverOtherApps {
                Label("Your layout is on the Touch Bar now, while this window is active. Switch to another app and its own Touch Bar returns.",
                      systemImage: "info.circle")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(model.touchBarHidden ? "Show on Touch Bar" : "Refresh Touch Bar") { model.showTouchBar() }
                if !model.touchBarHidden { Button("Hide") { model.hideTouchBar() } }
                Spacer()
                Button("Change…") { model.section = .settings }.buttonStyle(.link)
            }
        }
    }

    private var profileCard: some View {
        Card(title: "Active Profile", symbol: "person.crop.rectangle.stack") {
            let displayed = model.config.profile(id: model.displayedProfileID ?? model.config.defaultProfileID)
            Text(displayed?.name ?? "–").font(.title3.weight(.semibold))
            LabeledContent("Frontmost app (detected)") {
                if let app = model.apps.lastExternalApp {
                    HStack(spacing: 4) {
                        AppIconView(bundleIdentifier: app.bundleIdentifier, size: 14)
                        Text(app.name)
                    }
                } else {
                    Text("–")
                }
            }
            LabeledContent("Matching profile") {
                Text(ProfileResolver.profile(for: model.apps.lastExternalApp?.bundleIdentifier, in: model.config)?.name ?? "None (default)")
            }
            if model.providerShowsOverOtherApps {
                Toggle("Switch profiles automatically", isOn: Binding(
                    get: { model.config.settings.autoSwitchProfiles },
                    set: { model.config.settings.autoSwitchProfiles = $0 }))
            } else {
                Text("App detection works, but with the standard integration the Touch Bar only shows your layout inside TouchBar Studio, so automatic switching has no effect. Choose the profile to show:")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.providerShowsOverOtherApps || !model.config.settings.autoSwitchProfiles {
                Picker("Show", selection: Binding(
                    get: { model.config.settings.manualProfileID ?? model.config.defaultProfileID },
                    set: { model.config.settings.manualProfileID = $0 })) {
                    ForEach(model.config.profiles) { Text($0.name).tag($0.id) }
                }
            }
            Button("Edit This Layout") {
                if let id = displayed?.id { model.editor.selectProfile(id) }
                model.section = .editor
            }
        }
    }

    private var permissionsCard: some View {
        Card(title: "Permissions", symbol: "hand.raised") {
            HStack {
                Text("Accessibility")
                Spacer()
                StatusBadge(text: model.permissions.accessibilityGranted ? "Granted" : "Not granted",
                            style: model.permissions.accessibilityGranted ? .ok : .warning)
            }
            Text(model.permissions.accessibilityGranted
                 ? "Keyboard-shortcut and media-key actions can run."
                 : "Needed only for keyboard-shortcut and media-key actions. Other actions work without it.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Automation")
                Spacer()
                StatusBadge(text: "Asked per app", style: .info)
            }
            Button("Review Permissions…") { model.section = .settings }.buttonStyle(.link)
        }
    }

    private var quickTestCard: some View {
        Card(title: "Current Layout", symbol: "rectangle.split.3x1") {
            let profile = model.config.profile(id: model.displayedProfileID ?? model.config.defaultProfileID)
            TouchBarPreview(items: profile?.items ?? [], selection: .constant(nil), compact: true,
                            onActivate: { item in if item.kind == .button { model.perform(item, source: "Preview") } })
            Text("Click a button in the preview to run its action from here. Tapping it on the physical Touch Bar does the same.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ActivityLogView: View {
    @Environment(AppModel.self) private var model
    var limit: Int?

    var body: some View {
        Card(title: "Recent Activity", symbol: "clock.arrow.circlepath") {
            if model.activity.isEmpty {
                Text("No actions have run yet. Tap a button on the Touch Bar or use a Test button.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(limit.map { Array(model.activity.prefix($0)) } ?? model.activity) { entry in
                    HStack(alignment: .top) {
                        Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(entry.succeeded ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.source).font(.callout.weight(.medium))
                            Text(entry.summary).font(.caption).foregroundStyle(.secondary)
                            if let message = entry.message {
                                Text(message).font(.caption).foregroundStyle(entry.succeeded ? Color.secondary : Color.red)
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer()
                        Text(entry.date, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                }
                Button("Clear") { model.clearActivity() }.buttonStyle(.link)
            }
        }
    }
}
