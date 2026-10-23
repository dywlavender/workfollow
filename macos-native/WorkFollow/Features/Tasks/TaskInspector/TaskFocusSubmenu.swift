import SwiftUI

struct TaskFocusSubmenu: View {
    let onStart: (Bool) -> Void
    /// 预计专注入口跟着专注动作走（滴答的 focus 动作同属一个委托：
    /// `StartPomoFocus` / `StartStopWatchFocus` / `SetFocusEstimate`）。
    let onSetEstimate: () -> Void
    var estimateTitle = "设置预计专注"
    var onCancel: () -> Void = {}
    @StateObject private var controller = BusinessMenuController()

    var body: some View {
        BusinessMenuContent(controller: controller, close: onCancel, dismissAll: {}) {
            Button("开始番茄专注") { onStart(false) }
                .inspectorRenderAnchor(.focusPomodoro)
            Button("开始正计时") { onStart(true) }
                .inspectorRenderAnchor(.focusStopwatch)
            Divider().padding(.vertical, 2)
            Button(estimateTitle, action: onSetEstimate)
                .inspectorRenderAnchor(.focusEstimate)
        }
    }
}

@MainActor
enum TaskInspectorFocusAction {
    static func start(taskID: UUID, stopwatch: Bool, store: FocusStore,
                      presentation: inout TaskInspectorActionPresentationState) -> Bool {
        guard store.start(taskID: taskID, stopwatch: stopwatch) else { return false }
        presentation.dismiss()
        return true
    }
}
