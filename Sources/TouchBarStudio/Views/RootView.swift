import SwiftUI
import TouchBarStudioCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(SidebarSection.allCases, selection: Binding(get: { model.section }, set: { if let s = $0 { model.section = s } })) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                if let warning = model.loadWarning {
                    Banner(text: warning, style: .warning) { model.loadWarning = nil }
                }
                if let error = model.saveError {
                    Banner(text: error, style: .error) { model.saveError = nil }
                }
                detail
            }
            .navigationTitle(model.section.title)
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .dashboard: DashboardView()
        case .editor: EditorView()
        case .actions: ActionsView()
        case .profiles: ProfilesView()
        case .presets: PresetsView()
        case .settings: ScrollView { SettingsView().padding(20) }
        }
    }
}

struct Banner: View {
    var text: String
    var style: StatusBadge.Style
    var dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: style == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(style == .error ? .red : .orange)
            Text(text).textSelection(.enabled)
            Spacer()
            Button("Dismiss", action: dismiss).buttonStyle(.borderless)
        }
        .padding(10)
        .background((style == .error ? Color.red : Color.orange).opacity(0.12))
    }
}
