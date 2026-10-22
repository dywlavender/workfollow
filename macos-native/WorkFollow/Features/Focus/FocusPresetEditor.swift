import SwiftUI

struct FocusPresetEditor: View {
    @ObservedObject var store: FocusStore
    let workspace: TaskWorkspaceModel?
    @State var preset: FocusStore.TimerPreset
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            DialogHeader(title: "编辑常用专注")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("名称", text: $preset.name)
                    BusinessPicker("表情", selection: $preset.emoji, options:
                        FocusTheme.emojiChoices.map { BusinessChoice($0, $0) })
                    Toggle("正计时", isOn: $preset.stopwatch)
                    if !preset.stopwatch { Stepper("\(preset.minutes) 分钟", value: $preset.minutes, in: PomodoroSettings.focusRange) }
                    BusinessPicker("关联任务", selection: $preset.taskID, options:
                        [BusinessChoice(nil, "不关联")] + (workspace?.allTasks.filter { $0.deletedAt == nil && !$0.isAbandoned } ?? []).map {
                            BusinessChoice(Optional($0.id), $0.title.isEmpty ? "未命名任务" : $0.title, symbol: "checklist")
                        }, width: PopupMetrics.relationPickerWidth)
                }.padding(PopupMetrics.formInset)
            }
            DialogFooter(canSubmit: !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                         onCancel: { dismiss() }, onSubmit: {
                if store.updateTimer(preset) { dismiss() }
                else { error = "无法保存，请检查名称和时长。" }
            }) {
                Text(error ?? "").foregroundStyle(WFColors.danger)
            }
        }.frame(width: 400, height: 380).background(WFColors.content)
    }
}
