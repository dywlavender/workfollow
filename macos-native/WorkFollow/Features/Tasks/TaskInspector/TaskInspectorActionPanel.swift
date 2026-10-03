import Foundation

enum TaskInspectorActionPanel: Equatable, CaseIterable {
    case more, tags, attributes, relation, parent, activity
}

enum TaskActionSubmenu: Equatable { case focus }

/// Owns mutually exclusive footer action surfaces, not task values or schedule
/// presentation. Submenu ownership will be added with its actual presenter.
struct TaskInspectorActionPresentationState: Equatable {
    private(set) var panel: TaskInspectorActionPanel?
    private(set) var submenu: TaskActionSubmenu?

    mutating func open(_ panel: TaskInspectorActionPanel) {
        self.panel = panel
        submenu = nil
    }

    mutating func dismiss() {
        panel = nil
        submenu = nil
    }

    mutating func dismiss(_ expected: TaskInspectorActionPanel) {
        if panel == expected { dismiss() }
    }

    mutating func openSubmenu(_ submenu: TaskActionSubmenu) {
        guard panel == .more else { return }
        self.submenu = submenu
    }

    mutating func dismissSubmenu() { submenu = nil }

    @discardableResult
    mutating func handleEscape() -> Bool {
        if submenu != nil { dismissSubmenu(); return true }
        guard panel != nil else { return false }
        dismiss()
        return true
    }
}
