import AppKit
import SwiftUI
import TouchBarStudioCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        #if DEBUG
        DebugSnapshots.runIfRequested(model: model)
        #endif
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // The standard Touch Bar provider is found through the key window's responder
        // chain: with no window open, macOS shows an empty bar. Bring the window back.
        ensureMainWindow()
        // Permissions may have been granted in System Settings meanwhile.
        model.permissions.refresh()
        model.refreshTouchBar(force: true)
    }

    private func ensureMainWindow() {
        let hasMainWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        if !hasMainWindow { model.openMainWindow?() }
    }

    // Keep running with the window closed: the menu bar item and (in experimental
    // mode) the Touch Bar layout stay available.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        model.saveNow()
        model.hideTouchBar()
    }
}

@main
struct TouchBarStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("TouchBar Studio", id: "main") {
            RootView()
                .environment(delegate.model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { AppCommands(model: delegate.model) }

        Settings {
            SettingsView()
                .environment(delegate.model)
                .frame(width: 640, height: 620)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        // Undo/redo go to the focused text field when editing text, otherwise to the layout editor.
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                if NSApp.keyWindow?.firstResponder is NSText { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                else { model.editor.undo() }
            }
            .keyboardShortcut("z")
            Button("Redo") {
                if NSApp.keyWindow?.firstResponder is NSText { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                else { model.editor.redo() }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(after: .sidebar) {
            ForEach(Array(SidebarSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { model.section = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        CommandMenu("Layout") {
            Button("Add Button") { model.section = .editor; model.editor.add(LayoutComponent.named("button")!) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Duplicate") { if let id = model.editor.selection { model.editor.duplicate(id) } }
                .keyboardShortcut("d")
            Button("Delete") { if let id = model.editor.selection { model.editor.delete(id) } }
                .keyboardShortcut(.delete, modifiers: .command)
            Divider()
            Button("Move Left") { model.editor.moveSelection(by: -1) }
                .keyboardShortcut("[", modifiers: [.command, .option])
            Button("Move Right") { model.editor.moveSelection(by: 1) }
                .keyboardShortcut("]", modifiers: [.command, .option])
            Divider()
            Button("Save Layout") { model.editor.save() }
                .keyboardShortcut("s")
        }
        CommandMenu("Touch Bar") {
            Button("Show Layout on Touch Bar") { model.showTouchBar() }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Button("Hide Layout from Touch Bar") { model.hideTouchBar() }
        }
    }
}

/// Always-rendered menu bar label; also hands the scene's `openWindow` action to the
/// model so AppKit code can reopen the main window.
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "rectangle.and.hand.point.up.left.filled")
            .onAppear {
                model.openMainWindow = {
                    openWindow(id: "main")
                }
            }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open TouchBar Studio") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Divider()
        Text("On Touch Bar: \(model.config.profile(id: model.displayedProfileID ?? model.config.defaultProfileID)?.name ?? "–")")
        Menu("Show Profile") {
            ForEach(model.config.profiles) { profile in
                Button(profile.name) { model.config.settings.manualProfileID = profile.id }
            }
        }
        if model.providerShowsOverOtherApps {
            Toggle("Switch Profiles Automatically", isOn: Binding(
                get: { model.config.settings.autoSwitchProfiles },
                set: { model.config.settings.autoSwitchProfiles = $0 }))
        }
        Button(model.touchBarHidden ? "Show Layout on Touch Bar" : "Hide Layout from Touch Bar") {
            model.touchBarHidden ? model.showTouchBar() : model.hideTouchBar()
        }
        Divider()
        Button("Quit TouchBar Studio") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
