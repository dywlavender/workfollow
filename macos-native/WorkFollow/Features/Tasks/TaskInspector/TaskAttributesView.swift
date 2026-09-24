import SwiftUI

struct TaskAttributesView: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    @State private var tagsDraft = ""
    @EnvironmentObject private var environment: AppEnvironment
    var body: some View {
        DisclosureGroup("更多属性") {
            VStack(alignment: .leading, spacing: 12) {
                ReminderAttributesView(task: task, workspace: workspace, service: environment.reminders)
                AttachmentListView(attachments: task.attachments) { workspace.setAttachments(task.id, $0) }
                Picker("重复", selection: Binding(get: { task.recurrence }, set: { workspace.setRepeat(task.id, $0) })) {
                    ForEach(TaskRepeat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                HStack {
                    TextField("标签，用逗号分隔", text: $tagsDraft)
                        .onSubmit(saveTags)
                    Button("应用", action: saveTags)
                }
                if !task.tags.isEmpty { Text(task.tags.map { "#" + $0 }.joined(separator: "  ")).foregroundStyle(WFColors.accent) }
                if let due = task.schedule.dueAt {
                    Toggle("指定时间", isOn: Binding(get: { task.schedule.hasTime }, set: { enabled in
                        var value = task.schedule
                        value.hasTime = enabled
                        if !enabled { value.dueAt = Calendar.current.startOfDay(for: due) }
                        _ = workspace.setSchedule(task.id, value)
                    }))
                    if task.schedule.hasTime {
                        DatePicker("时间", selection: Binding(get: { task.schedule.dueAt ?? due }, set: { date in
                            var value = task.schedule
                            value.dueAt = date
                            _ = workspace.setSchedule(task.id, value)
                        }), displayedComponents: [.hourAndMinute])
                    }
                }
            }.padding(.top, 8)
        }.padding(.horizontal, WFSpace.page).padding(.vertical, 8)
            .onAppear { tagsDraft = task.tags.joined(separator: ", ") }
    }
    private func saveTags() {
        workspace.setTags(task.id, tagsDraft.replacingOccurrences(of: "，", with: ",").components(separatedBy: ","))
    }
}

private struct ReminderAttributesView: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var service: NativeReminderService
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("提醒", isOn: Binding(get: { task.reminderAt != nil }, set: {
                workspace.setReminder(task.id, $0 ? Date().addingTimeInterval(3600) : nil)
            }))
            if let reminder = task.reminderAt {
                DatePicker("提醒时间", selection: Binding(get: { reminder }, set: { workspace.setReminder(task.id, $0) }))
                Button("允许系统通知") { service.enable(for: workspace.allTasks) }
            }
            if let message = service.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
