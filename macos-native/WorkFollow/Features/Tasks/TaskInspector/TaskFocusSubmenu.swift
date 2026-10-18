import SwiftUI

struct TaskFocusSubmenu: View {
    let onStart: (Bool) -> Void
    /// 预计专注入口跟着专注动作走（滴答的 focus 动作同属一个委托：
    /// `StartPomoFocus` / `StartStopWatchFocus` / `SetFocusEstimate`）。
    let onSetEstimate: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Button { onStart(false) } label: { row("开始番茄专注") }
                .inspectorRenderAnchor(.focusPomodoro)
            Button { onStart(true) } label: { row("开始正计时") }
                .inspectorRenderAnchor(.focusStopwatch)
            Divider().padding(.vertical, 2)
            Button { onSetEstimate() } label: { row("设置预计专注") }
                .inspectorRenderAnchor(.focusEstimate)
        }
        .buttonStyle(.plain)
        .font(WFType.menu)
        .foregroundStyle(WFColors.text)
        .padding(8)
    }

    private func row(_ title: String) -> some View {
        Text(title).frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(.horizontal, 8).contentShape(Rectangle())
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
