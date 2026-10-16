import SwiftUI

struct FocusPresetEditor: View {
    @ObservedObject var store: FocusStore
    let workspace: TaskWorkspaceModel?
    @State var preset: FocusStore.TimerPreset
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("编辑常用专注").font(.title3.weight(.semibold))
            TextField("名称", text: $preset.name)
            Picker("表情", selection: $preset.emoji) {
                ForEach(FocusTheme.emojiChoices, id: \.self) { Text($0).tag($0) }
            }
            Toggle("正计时", isOn: $preset.stopwatch)
            if !preset.stopwatch { Stepper("\(preset.minutes) 分钟", value: $preset.minutes, in: PomodoroSettings.focusRange) }
            Picker("关联任务", selection: $preset.taskID) {
                Text("不关联").tag(Optional<UUID>.none)
                ForEach(workspace?.allTasks.filter { $0.deletedAt == nil && !$0.isAbandoned } ?? []) {
                    Text($0.title.isEmpty ? "未命名任务" : $0.title).tag(Optional($0.id))
                }
            }
            HStack {
                Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { if store.updateTimer(preset) { dismiss() } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 400)
    }
}
