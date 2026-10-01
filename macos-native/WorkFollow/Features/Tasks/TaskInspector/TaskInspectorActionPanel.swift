import Foundation

enum TaskInspectorActionPanel: Equatable, CaseIterable {
    case more, tags, attributes, relation
}

/// Owns mutually exclusive footer action surfaces, not task values or schedule
/// presentation. Submenu ownership will be added with its actual presenter.
struct TaskInspectorActionPresentationState: Equatable {
    private(set) var panel: TaskInspectorActionPanel?

    mutating func open(_ panel: TaskInspectorActionPanel) {
        self.panel = panel
    }

    mutating func dismiss() {
        panel = nil
    }

    mutating func dismiss(_ expected: TaskInspectorActionPanel) {
        if panel == expected { dismiss() }
    }
}
