import SwiftUI

struct TaskFocusEstimateEditor: View {
    let estimate: TaskFocusEstimate?
    let onSave: (TaskFocusEstimate?) -> Void
    let onCancel: () -> Void
    @State private var usesPomodoros: Bool
    @State private var minutes: Int
    @State private var pomodoros: Int

    init(estimate: TaskFocusEstimate?, onSave: @escaping (TaskFocusEstimate?) -> Void,
         onCancel: @escaping () -> Void) {
        self.estimate = estimate; self.onSave = onSave; self.onCancel = onCancel
        _usesPomodoros = State(initialValue: estimate?.pomodoros != nil)
        _minutes = State(initialValue: estimate?.minutes ?? 25)
        _pomodoros = State(initialValue: estimate?.pomodoros ?? 1)
    }

    private var quantity: Binding<Int> { usesPomodoros ? $pomodoros : $minutes }

    var body: some View {
        let value = quantity.wrappedValue
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("预计专注").font(WFType.sectionSemibold)
                EstimateUnitPicker(usesPomodoros: $usesPomodoros)
                HStack(spacing: 8) {
                    EstimateStepButton(symbol: "minus", tip: "减少") { step(-1) }
                        .disabled(value <= 1)
                    TextField("数值", value: quantity, format: .number)
                        .textFieldStyle(.plain)
                        .font(WFType.controlLarge)
                        .monospacedDigit()
                        .foregroundStyle(WFColors.text)
                        .multilineTextAlignment(.center)
                        .frame(width: 86, height: 30)
                        .background(WFColors.fieldFill, in: RoundedRectangle(cornerRadius: 7))
                        .accessibilityLabel("预计专注数值").onSubmit(save)
                    EstimateStepButton(symbol: "plus", tip: "增加") { step(1) }
                        .disabled(value >= 10_000)
                    Text(usesPomodoros ? "个番茄" : "分钟")
                        .foregroundStyle(WFColors.secondaryText)
                        .padding(.leading, 2)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PopupMetrics.contentInset)
            PopupActionBar {
                Button("清除") { onSave(nil) }.buttonStyle(.plain)
                    .disabled(estimate == nil).accessibilityLabel("清除预计专注")
                    .foregroundStyle(estimate == nil ? WFColors.tertiaryText : WFColors.secondaryText)
                    .inspectorRenderAnchor(.focusEstimateClear)
                Spacer()
                PopupActionButton(title: "取消", action: onCancel)
                    .frame(width: 64).keyboardShortcut(.cancelAction)
                PopupActionButton(title: "保存", primary: true, action: save)
                    .frame(width: 64).keyboardShortcut(.defaultAction).disabled(value < 1)
            }
        }
        .font(WFType.body).frame(width: PopupMetrics.focusEstimateWidth)
    }

    private func step(_ delta: Int) {
        quantity.wrappedValue = min(max(quantity.wrappedValue + delta, 1), 10_000)
    }

    private func save() {
        guard quantity.wrappedValue > 0 else { return }
        onSave(usesPomodoros ? TaskFocusEstimate(minutes: nil, pomodoros: pomodoros)
                            : TaskFocusEstimate(minutes: minutes, pomodoros: nil))
    }
}

/// 时长 / 番茄数分段：浅色轨道 + 白色选中胶囊，避免非激活浮层里系统
/// 分段控件退成整块灰底。
private struct EstimateUnitPicker: View {
    @Binding var usesPomodoros: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var trackFill: Color {
        colorScheme == .dark ? WFColors.onAccent.opacity(0.09) : Color.primary.opacity(0.06)
    }
    private var thumbFill: Color {
        colorScheme == .dark ? WFColors.onAccent.opacity(0.14) : .white
    }

    var body: some View {
        HStack(spacing: 2) {
            option("时长", anchor: .focusEstimateDuration,
                   selected: !usesPomodoros) { usesPomodoros = false }
            option("番茄数", anchor: .focusEstimatePomodoros,
                   selected: usesPomodoros) { usesPomodoros = true }
        }
        .padding(2)
        .background(trackFill, in: RoundedRectangle(cornerRadius: 8))
        .animation(.easeOut(duration: 0.14), value: usesPomodoros)
    }

    private func option(_ title: String, anchor: InspectorRenderAnchor, selected: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(selected ? WFType.controlLabelStrong : WFType.controlLabel)
                .foregroundStyle(selected ? WFColors.text : WFColors.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(thumbFill)
                            .shadow(color: .black.opacity(0.08), radius: 1.5, y: 0.5)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "已选择" : "未选择")
        .inspectorRenderAnchor(anchor)
    }
}

private struct EstimateStepButton: View {
    let symbol: String
    let tip: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.09 : 0.05)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .hoverTip(tip)
        .accessibilityLabel(tip)
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
