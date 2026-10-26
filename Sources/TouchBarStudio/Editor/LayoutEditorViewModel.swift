import Foundation
import Observation
import TouchBarStudioCore

/// A component that can be dropped into a layout from the library.
struct LayoutComponent: Identifiable, Hashable {
    enum Group { case layout, widget, action }

    var id: String
    var group: Group = .layout
    var title: String
    var symbol: String
    var make: @MainActor () -> TouchBarItemConfig

    static func == (a: LayoutComponent, b: LayoutComponent) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Computed so titles follow the interface language.
    static var library: [LayoutComponent] {
        var list: [LayoutComponent] = [
            LayoutComponent(id: "button", title: L("Empty Button"), symbol: "rectangle") {
                TouchBarItemConfig(title: L("Button"), icon: .symbol("star"), action: .none)
            },
            LayoutComponent(id: "smallSpace", title: L("Small Space"), symbol: "arrow.left.and.right") { .space(.smallSpace) },
            LayoutComponent(id: "largeSpace", title: L("Large Space"), symbol: "arrow.left.and.right.square") { .space(.largeSpace) },
            LayoutComponent(id: "flexibleSpace", title: L("Flexible Space"), symbol: "arrow.left.and.line.vertical.and.arrow.right") { .space(.flexibleSpace) },
        ]
        list.append(LayoutComponent(id: "battery", group: .widget, title: L("Battery"), symbol: "battery.75") { .battery() })
        list.append(LayoutComponent(id: "microphone", group: .widget, title: L("Microphone"), symbol: "mic.fill") { .microphone() })
        for descriptor in ActionRegistry.descriptors {
            list.append(LayoutComponent(id: "action.\(descriptor.kind.rawValue)", group: .action, title: descriptor.title, symbol: descriptor.symbol) {
                TouchBarItemConfig(title: descriptor.title, icon: .symbol(descriptor.symbol), action: ActionRegistry.template(for: descriptor.kind))
            })
        }
        return list
    }

    static func named(_ id: String) -> LayoutComponent? { library.first { $0.id == id } }
}

/// Editing state for one profile's layout, with snapshot-based undo/redo.
@MainActor
@Observable
final class LayoutEditorViewModel {
    private unowned let model: AppModel
    private(set) var profileID: UUID
    var selection: UUID?

    private var undoStack: [[TouchBarItemConfig]] = []
    private var redoStack: [[TouchBarItemConfig]] = []
    private var lastCoalesceKey: String?
    private var lastCoalesceDate = Date.distantPast
    /// Layout as it was when this profile was opened, for “Revert”.
    private var openedSnapshot: [TouchBarItemConfig] = []
    private static let undoLimit = 100

    init(model: AppModel) {
        self.model = model
        self.profileID = model.config.settings.manualProfileID ?? model.config.defaultProfileID
        openedSnapshot = items
    }

    var profile: Profile? { model.config.profile(id: profileID) }
    var items: [TouchBarItemConfig] { profile?.items ?? [] }
    var selectedItem: TouchBarItemConfig? { items.first { $0.id == selection } }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasChangesSinceOpened: Bool { items != openedSnapshot }

    func selectProfile(_ id: UUID) {
        guard model.config.profile(id: id) != nil else { return }
        profileID = id
        selection = nil
        undoStack.removeAll()
        redoStack.removeAll()
        lastCoalesceKey = nil
        openedSnapshot = items
    }

    /// Ensures the editor points at an existing profile (after deletions/imports).
    func validateProfile() {
        if model.config.profile(id: profileID) == nil { selectProfile(model.config.defaultProfileID) }
    }

    // MARK: Mutations

    /// Applies a change and records an undo snapshot. Consecutive changes with the same
    /// `coalesceKey` (e.g. typing in one text field) collapse into one undo step.
    func mutate(coalesceKey: String? = nil, _ change: (inout [TouchBarItemConfig]) -> Void) {
        var newItems = items
        change(&newItems)
        guard newItems != items else { return }
        let now = Date()
        let coalesce = coalesceKey != nil && coalesceKey == lastCoalesceKey && now.timeIntervalSince(lastCoalesceDate) < 2
        if !coalesce {
            undoStack.append(items)
            if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        }
        redoStack.removeAll()
        lastCoalesceKey = coalesceKey
        lastCoalesceDate = now
        model.updateProfile(profileID) { $0.items = newItems }
    }

    func update(_ id: UUID, field: String, _ change: (inout TouchBarItemConfig) -> Void) {
        mutate(coalesceKey: "\(id)-\(field)") { items in
            if let i = items.firstIndex(where: { $0.id == id }) { change(&items[i]) }
        }
    }

    func add(_ component: LayoutComponent, at index: Int? = nil) {
        let item = component.make()
        mutate { items in items.insert(item, at: min(index ?? items.count, items.count)) }
        selection = item.id
    }

    func duplicate(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var copy = items[index].withNewID()
        copy.hotKey = nil // a hotkey can only trigger one button
        mutate { $0.insert(copy, at: index + 1) }
        selection = copy.id
    }

    func delete(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate { $0.remove(at: index) }
        let remaining = items
        selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        mutate { $0.move(fromOffsets: source, toOffset: destination) }
    }

    /// Drag-and-drop: moves `id` so it ends up just before `target` (or at the end).
    func move(_ id: UUID, before target: UUID?) {
        guard id != target, let from = items.firstIndex(where: { $0.id == id }) else { return }
        mutate { items in
            let item = items.remove(at: from)
            let to = target.flatMap { t in items.firstIndex { $0.id == t } } ?? items.count
            items.insert(item, at: to)
        }
    }

    func moveSelection(by offset: Int) {
        guard let id = selection, let from = items.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard items.indices.contains(to) else { return }
        mutate { $0.swapAt(from, to) }
    }

    func replaceAll(with newItems: [TouchBarItemConfig]) {
        mutate { $0 = newItems }
        selection = nil
    }

    // MARK: Undo / redo / revert

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(items)
        lastCoalesceKey = nil
        model.updateProfile(profileID) { $0.items = previous }
        fixSelection()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(items)
        lastCoalesceKey = nil
        model.updateProfile(profileID) { $0.items = next }
        fixSelection()
    }

    func revertToOpened() {
        mutate { $0 = openedSnapshot }
        fixSelection()
    }

    /// Marks the current layout as the new revert point and writes it to disk now.
    func save() {
        model.saveNow()
        openedSnapshot = items
    }

    private func fixSelection() {
        if let s = selection, !items.contains(where: { $0.id == s }) { selection = nil }
    }
}
