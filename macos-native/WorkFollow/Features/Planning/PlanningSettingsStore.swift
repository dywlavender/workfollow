import Combine
import Foundation

/// Display settings have their own persistence and history. They never enter
/// the task undo stack or cause a task write when a page is opened.
@MainActor
final class PlanningSettingsStore: ObservableObject {
    static let shared = PlanningSettingsStore()
    @Published private(set) var calendar: CalendarPreferences
    @Published private(set) var matrix: MatrixConfiguration
    @Published private(set) var canUndoConfiguration = false
    @Published private(set) var canRedoConfiguration = false
    private let defaults: UserDefaults
    private let calendarKey: String
    private let matrixKey: String
    private var undoStack: [MatrixConfiguration] = []
    private var redoStack: [MatrixConfiguration] = []
    private var renameObserver: AnyCancellable?

    init(defaults: UserDefaults = .standard, namespace: String = "workfollow.planning") {
        self.defaults = defaults
        calendarKey = namespace + ".calendar.v1"
        matrixKey = namespace + ".matrix.v1"
        calendar = defaults.data(forKey: calendarKey).flatMap { try? JSONDecoder().decode(CalendarPreferences.self, from: $0) }
            ?? CalendarPreferences()
        matrix = defaults.data(forKey: matrixKey).flatMap { try? JSONDecoder().decode(MatrixConfiguration.self, from: $0) }
            ?? .legacy
        // 周计划页删除后，「安排任务」面板是待安排任务的唯一入口：升级时一次性打开，
        // 之后仍尊重用户在显示设置里的开关。
        let arrangeDefaultKey = namespace + ".calendar.arrange.default.v1"
        if !defaults.bool(forKey: arrangeDefaultKey) {
            defaults.set(true, forKey: arrangeDefaultKey)
            if !calendar.showArrangePane {
                calendar.showArrangePane = true
                persist()
            }
        }
        // 周首日统一到周一（与摘要周界一致）：只迁移仍然停留在旧默认值（周日）的设置。
        let mondayWeekKey = namespace + ".calendar.mondayWeek.v1"
        if !defaults.bool(forKey: mondayWeekKey) {
            defaults.set(true, forKey: mondayWeekKey)
            if calendar.firstWeekday == 1 {
                calendar.firstWeekday = 2
                persist()
            }
        }
        renameObserver = NotificationCenter.default.publisher(for: .workspaceOrganizationRenamed)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let kind = notification.userInfo?["kind"] as? String,
                      let old = notification.userInfo?["old"] as? String else { return }
                self?.renameReference(kind: kind, old: old, new: notification.userInfo?["new"] as? String)
            }
    }
    func updateCalendar(_ change: (inout CalendarPreferences) -> Void) {
        var value = calendar; change(&value)
        guard value != calendar else { return }
        calendar = value; persist()
    }
    func updateMatrix(_ change: (inout MatrixConfiguration) -> Void) {
        var value = matrix; change(&value)
        guard value != matrix else { return }
        undoStack.append(matrix); redoStack.removeAll()
        matrix = value; updateHistory(); persist()
    }
    func undoConfiguration() {
        guard let value = undoStack.popLast() else { return }
        redoStack.append(matrix); matrix = value; updateHistory(); persist()
    }
    func redoConfiguration() {
        guard let value = redoStack.popLast() else { return }
        undoStack.append(matrix); matrix = value; updateHistory(); persist()
    }
    private func updateHistory() {
        canUndoConfiguration = !undoStack.isEmpty
        canRedoConfiguration = !redoStack.isEmpty
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(calendar) { defaults.set(data, forKey: calendarKey) }
        if let data = try? JSONEncoder().encode(matrix) { defaults.set(data, forKey: matrixKey) }
    }
    private func renameReference(kind: String, old: String, new: String?) {
        func replaced(_ values: [String]) -> [String] {
            Array(Set(values.compactMap { $0 == old ? new : $0 })).sorted()
        }
        var preferences = calendar
        if kind == "list" { preferences.listNames = replaced(preferences.listNames) }
        if kind == "tag" { preferences.tagNames = replaced(preferences.tagNames) }
        calendar = preferences
        func renamed(_ configuration: MatrixConfiguration) -> MatrixConfiguration {
            var value = configuration
            for index in value.quadrants.indices {
                if kind == "list" { value.quadrants[index].rule.listNames = replaced(value.quadrants[index].rule.listNames) }
                if kind == "tag" { value.quadrants[index].rule.tagNames = replaced(value.quadrants[index].rule.tagNames) }
            }
            return value
        }
        matrix = renamed(matrix)
        undoStack = undoStack.map(renamed); redoStack = redoStack.map(renamed)
        persist()
    }
}
