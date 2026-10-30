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
                VStack(alignment: .leading, spacing: WFSpace.lg) {
                    WFFormSection {
                        WFFormRow("名称") {
                            TextField("名称", text: $preset.name)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }
                        WFFormRow("表情") {
                            BusinessPicker("表情", selection: $preset.emoji, options:
                                FocusTheme.emojiChoices.map { BusinessChoice($0, $0) })
                                .labelsHidden()
                        }
                        WFFormToggleRow("正计时", isOn: $preset.stopwatch)
                        if !preset.stopwatch {
                            WFFormRow("专注时长") {
                                Stepper("\(preset.minutes) 分钟", value: $preset.minutes, in: PomodoroSettings.focusRange)
                            }
                        }
                        WFFormRow("关联任务", showsDivider: false) {
                            BusinessPicker("关联任务", selection: $preset.taskID, options:
                                [BusinessChoice(nil, "不关联")] + (workspace?.allTasks.filter { !$0.isNoteTask && $0.deletedAt == nil && !$0.isAbandoned } ?? []).map {
                                    BusinessChoice(Optional($0.id), $0.title.isEmpty ? "未命名任务" : $0.title, symbol: "checklist")
                                }, width: PopupMetrics.relationPickerWidth)
                                .labelsHidden()
                        }
                    }
                }.padding(PopupMetrics.formInset)
            }
            .compactScrollbars()
            DialogFooter(canSubmit: !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                         onCancel: { dismiss() }, onSubmit: {
                if store.updateTimer(preset) { dismiss() }
                else { error = "无法保存，请检查名称和时长。" }
            }) {
                Text(error ?? "").foregroundStyle(WFColors.danger)
            }
        }.frame(width: 400, height: 420)
            .workfollowPopupSurface()
    }
}
