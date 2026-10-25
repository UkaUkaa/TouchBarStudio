import SwiftUI
import TouchBarStudioCore

/// Overview of the action registry, the built-in app commands, a scratch area for
/// trying actions, and the activity log.
struct ActionsView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var scratch = ActionConfig.openApp("com.apple.calculator")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "Action Types", symbol: "bolt") {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        ForEach(ActionRegistry.descriptors) { d in
                            GridRow {
                                Image(systemName: d.symbol).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.title).font(.callout.weight(.semibold))
                                    Text(d.summary).font(.caption).foregroundStyle(.secondary)
                                }
                                HStack { ForEach(d.requirements, id: \.self) { requirementBadge($0) } }
                            }
                        }
                    }
                }

                Card(title: "Try an Action", symbol: "play.circle") {
                    Text("Configure any action and run it right away. Nothing here is saved.")
                        .font(.caption).foregroundStyle(.secondary)
                    Form {
                        ActionEditor(action: $scratch, associatedBundleIdentifier: nil, depth: 0)
                    }
                    .formStyle(.grouped)
                    .frame(minHeight: 260)
                }

                Card(title: "Built-in App Commands", symbol: "square.grid.3x3") {
                    ForEach(AppCommandCatalog.standard.groupedByApp, id: \.app) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                AppIconView(bundleIdentifier: group.commands.first?.bundleIdentifier, size: 16)
                                Text(group.app).font(.callout.weight(.semibold))
                                if let id = group.commands.first?.bundleIdentifier, IconProvider.appName(bundleIdentifier: id) == nil {
                                    StatusBadge(text: "Not installed", style: .warning)
                                }
                            }
                            ForEach(group.commands) { cmd in
                                HStack {
                                    Image(systemName: cmd.symbol).frame(width: 20)
                                    Text(cmd.title)
                                    Spacer()
                                    Text(cmd.action.summary).font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.leading, 22)
                            }
                        }
                        .padding(.bottom, 6)
                    }
                }

                ActivityLogView()
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func requirementBadge(_ r: ActionRequirement) -> some View {
        switch r {
        case .accessibility:
            StatusBadge(text: "Accessibility", style: model.permissions.accessibilityGranted ? .ok : .warning)
        case .automation:
            StatusBadge(text: "Automation", style: .info)
        case .shellEnabled:
            StatusBadge(text: model.config.settings.allowShellCommands ? "Enabled" : "Disabled in Settings",
                        style: model.config.settings.allowShellCommands ? .ok : .warning)
        case .scriptApproval:
            StatusBadge(text: "Needs approval", style: .info)
        }
    }
}
