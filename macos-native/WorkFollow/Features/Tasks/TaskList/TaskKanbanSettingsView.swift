import SwiftUI

struct TaskKanbanSettingsView: View {
    @ObservedObject var preferences: TaskViewPreferenceStore
    let key: String
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TaskDateDisplayMode.defaultsKey) private var dateMode = TaskDateDisplayMode.taskTime.rawValue

    private func value<T>(_ path: WritableKeyPath<TaskKanbanOptions, T>) -> Binding<T> {
        Binding(get: { preferences.kanbanOptions(for: key)[keyPath: path] }, set: { value in
            var options = preferences.kanbanOptions(for: key); options[keyPath: path] = value
            preferences.setKanbanOptions(options, for: key)
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("显示设置").font(WFType.section)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).hoverTip("关闭显示设置").accessibilityLabel("关闭显示设置")
            }
            WFFormSection {
                WFFormRow("看板尺寸") {
                    BusinessPicker("看板尺寸", selection: value(\.size), options:
                        TaskKanbanSize.allCases.map { BusinessChoice($0, $0.title) }).labelsHidden()
                }
                WFFormToggleRow("显示输入框", isOn: value(\.showsInput))
                WFFormToggleRow("显示检查事项", isOn: value(\.showsChecklist))
                WFFormRow("日期显示为", showsDivider: false) {
                    BusinessPicker("日期显示为", selection: $dateMode, options:
                        TaskDateDisplayMode.menuOrder.map { BusinessChoice($0.rawValue, $0.title) }).labelsHidden()
                }
            }
        }.padding(24).frame(width: 420)
            .workfollowPopupSurface()
            .onExitCommand { dismiss() }
    }
}
