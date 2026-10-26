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
        DebugSnapshots.traceTouchBarIfRequested()
        DebugSnapshots.switchProviderIfRequested(model: model)
        DebugSnapshots.tapIfRequested(model: model)
        DebugSnapshots.traceVisibilityIfRequested(model: model)
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
                .localized(delegate.model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { AppCommands(model: delegate.model) }

        Settings {
            SettingsView()
                .environment(delegate.model)
                .localized(delegate.model)
                .frame(width: 640, height: 680)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(delegate.model)
                .localized(delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        // Reading the language registers a dependency, so menus rebuild when it changes.
        let _ = model.language
        // Undo/redo go to the focused text field when editing text, otherwise to the layout editor.
        CommandGroup(replacing: .undoRedo) {
            Button(L("Undo")) {
                if NSApp.keyWindow?.firstResponder is NSText { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                else { model.editor.undo() }
            }
            .keyboardShortcut("z")
            Button(L("Redo")) {
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
        CommandMenu(L("Layout")) {
            Button(L("Add Button")) { model.section = .editor; model.editor.add(LayoutComponent.named("button")!) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button(L("Duplicate")) { if let id = model.editor.selection { model.editor.duplicate(id) } }
                .keyboardShortcut("d")
            Button(L("Delete")) { if let id = model.editor.selection { model.editor.delete(id) } }
                .keyboardShortcut(.delete, modifiers: .command)
            Divider()
            Button(L("Move Left")) { model.editor.moveSelection(by: -1) }
                .keyboardShortcut("[", modifiers: [.command, .option])
            Button(L("Move Right")) { model.editor.moveSelection(by: 1) }
                .keyboardShortcut("]", modifiers: [.command, .option])
            Divider()
            Button(L("Save Layout")) { model.editor.save() }
                .keyboardShortcut("s")
        }
        CommandMenu(L("Touch Bar")) {
            Button(L("Show Layout on Touch Bar")) { model.showTouchBar() }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Button(L("Hide Layout from Touch Bar")) { model.hideTouchBar() }
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
        Button(L("Open TouchBar Studio")) {
            openWindow(id: "main")
            NSApp.activate()
        }
        Divider()
        Text(L("On Touch Bar: %@", model.config.profile(id: model.displayedProfileID ?? model.config.defaultProfileID)?.name ?? "–"))
        Menu(L("Show Profile")) {
            ForEach(model.config.profiles) { profile in
                Button(profile.name) { model.config.settings.manualProfileID = profile.id }
            }
        }
        if model.providerShowsOverOtherApps {
            Toggle(L("Switch Profiles Automatically"), isOn: Binding(
                get: { model.config.settings.autoSwitchProfiles },
                set: { model.config.settings.autoSwitchProfiles = $0 }))
        }
        if let app = model.frontmostHiddenApp {
            Button(L("Show Layout in %@", app.name)) { model.showLayoutInCurrentApp() }
        }
        Button(model.touchBarHidden ? L("Show Layout on Touch Bar") : L("Hide Layout from Touch Bar")) {
            model.touchBarHidden ? model.showTouchBar() : model.hideTouchBar()
        }
        Divider()
        Button(L("Quit TouchBar Studio")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

extension View {
    /// Rebuilds the view tree when the interface language changes (texts come from `L()`,
    /// which SwiftUI can't observe) and sets the locale for dates and numbers.
    func localized(_ model: AppModel) -> some View {
        environment(\.locale, model.language.locale)
            .id(model.language)
    }
}
