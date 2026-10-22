import SwiftUI

struct TaskFocusEstimateEditor: View {
    let estimate: TaskFocusEstimate?
    let onSave: (TaskFocusEstimate?) -> Void
    let onCancel: () -> Void
    @State private var usesPomodoros: Bool
    @State private var count: Int

    init(estimate: TaskFocusEstimate?, onSave: @escaping (TaskFocusEstimate?) -> Void,
         onCancel: @escaping () -> Void) {
        self.estimate = estimate; self.onSave = onSave; self.onCancel = onCancel
        _usesPomodoros = State(initialValue: estimate?.pomodoros != nil)
        _count = State(initialValue: estimate?.pomodoros ?? estimate?.minutes ?? 25)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("预计专注").font(WFType.sectionSemibold)
            Picker("单位", selection: $usesPomodoros) {
                Text("时长").tag(false)
                Text("番茄数").tag(true)
            }.pickerStyle(.segmented)
            HStack {
                TextField("数值", value: $count, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 80)
                    .accessibilityLabel("预计专注数值")
                Text(usesPomodoros ? "个番茄" : "分钟")
                Stepper("调整", value: $count, in: 1...10_000).labelsHidden()
            }
            HStack {
                Button("清除") { onSave(nil) }
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSave(usesPomodoros ? TaskFocusEstimate(minutes: nil, pomodoros: count)
                                       : TaskFocusEstimate(minutes: count, pomodoros: nil))
                }.keyboardShortcut(.defaultAction).disabled(count < 1)
            }
        }
        .font(WFType.control)
        .padding(16).frame(width: PopupMetrics.focusEstimateWidth)
    }
}

private struct TaskFocusStoreKey: EnvironmentKey {
    static let defaultValue: FocusStore? = nil
}

extension EnvironmentValues {
    var taskFocusStore: FocusStore? {
        get { self[TaskFocusStoreKey.self] }
        set { self[TaskFocusStoreKey.self] = newValue }
    }
}

struct TaskFocusSummaryRow: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var focusStore: FocusStore
    let onOpenRecords: () -> Void

    var body: some View {
        TaskFocusEstimateControl(task: task, workspace: workspace,
            actualMinutes: focusStore.taskTotalActiveSeconds(taskID: task.id) / 60,
            onOpenRecords: onOpenRecords)
    }
}

/// A standalone inspector can edit estimates without constructing an app or
/// persistence store; the app injects its actual FocusStore through the host.
struct TaskFocusEstimateControl: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    var actualMinutes: Int?
    var onOpenRecords: (() -> Void)?
    @State private var showEstimate = false

    var body: some View {
        let estimate = task.focusEstimate
        let label = estimate?.minutes.map { "预计 \($0) 分钟" }
            ?? estimate?.pomodoros.map { "预计 \($0) 个番茄" } ?? "设置预计专注"
        HStack(spacing: 8) {
            Image(systemName: "timer").foregroundStyle(WFColors.tertiaryText)
            Button(label) { showEstimate = true }
                .buttonStyle(.plain)
                .background(AnchoredPropertyPanel(isPresented: $showEstimate, width: PopupMetrics.focusEstimateWidth) {
                    TaskFocusEstimateEditor(estimate: task.focusEstimate, onSave: { value in
                        _ = workspace.setFocusEstimate(task.id, value)
                        showEstimate = false
                    }, onCancel: { showEstimate = false })
                })
            if let actualMinutes {
                Text("·").foregroundStyle(WFColors.tertiaryText)
                Button("实际 \(actualMinutes) 分钟") { onOpenRecords?() }
                    .buttonStyle(.plain).accessibilityLabel("查看任务专注记录")
                    .disabled(onOpenRecords == nil)
            }
            Spacer(minLength: 0)
        }
        .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
    }
}
