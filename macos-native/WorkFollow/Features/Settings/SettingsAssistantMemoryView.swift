import SwiftUI

struct SettingsAssistantMemoryView: View {
    @ObservedObject var memories: AssistantMemoryStore
    @ObservedObject var briefing: AssistantBriefingStore
    @ObservedObject var followUps: MeetingFollowUpStore
    var onAutomaticChanged: () -> Void = {}
    @State private var draft = ""
    @State private var editing: AssistantMemory?
    @State private var error: String?

    var body: some View {
        SettingsPage {
            SettingsGroup("助手记忆", footnote: "也可以在对话中说“记住，以后开会提前十分钟提醒”。这些偏好在新对话中继续有效。") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("输入一条长期偏好…", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain).lineLimit(1...4)
                        .accessibilityIdentifier("assistant.memory.input")
                    HStack {
                        Button(editing == nil ? "记住" : "保存") { save() }
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .workflowActionAnchor("assistant.memory.save")
                        if editing != nil { Button("取消") { editing = nil; draft = ""; error = nil } }
                        Spacer()
                    }
                }.padding(14)
                ForEach(memories.entries) { memory in
                    Divider().padding(.horizontal, 14)
                    HStack(alignment: .top, spacing: 12) {
                        Text(memory.content).font(WFType.body).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            editing = memory; draft = memory.content; error = nil
                        } label: { Image(systemName: "pencil") }
                            .accessibilityLabel("修改偏好：\(memory.content)")
                            .workflowActionAnchor("assistant.memory.edit.\(memory.id)")
                        Button {
                            do {
                                try memories.forget(memory.id, version: memory.version)
                                if editing?.id == memory.id { editing = nil; draft = "" }
                                error = nil
                            } catch { self.error = error.localizedDescription }
                        } label: { Image(systemName: "trash") }
                            .accessibilityLabel("忘记偏好：\(memory.content)")
                            .workflowActionAnchor("assistant.memory.forget.\(memory.id)")
                    }.buttonStyle(.plain).padding(14)
                }
                if let message = error ?? memories.storageError {
                    Text(message).font(WFType.supporting).foregroundStyle(WFColors.danger).padding(14)
                }
            }
            SettingsGroup("今日简报", footnote: "每天首次打开 App 时生成，保留在 AI 对话页；也可以手动刷新。") {
                Toggle("每天自动生成今日简报", isOn: Binding(get: { briefing.automaticEnabled }, set: { enabled in
                    do { try briefing.setAutomaticEnabled(enabled); error = nil; onAutomaticChanged() }
                    catch { self.error = error.localizedDescription }
                })).toggleStyle(.switch).padding(14)
                    .accessibilityIdentifier("assistant.briefing.automatic")
                Toggle("会后提取待办", isOn: Binding(get: { followUps.enabled }, set: { enabled in
                    do { try followUps.setEnabled(enabled); error = nil }
                    catch { self.error = error.localizedDescription }
                })).toggleStyle(.switch).padding(14)
                    .accessibilityIdentifier("assistant.meeting.followUp")
                Picker("助手默认提醒", selection: Binding(get: { briefing.defaultReminderMinutes }, set: { value in
                    do { try briefing.setDefaultReminderMinutes(value); error = nil }
                    catch { self.error = error.localizedDescription }
                })) {
                    Text("手动选择").tag(nil as Int?)
                    Text("准时").tag(0 as Int?)
                    ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                        Text("提前 \(minutes) 分钟").tag(Optional(minutes))
                    }
                }.padding(14)
                    .accessibilityIdentifier("assistant.reminder.default")
            }
        }.accessibilityIdentifier("assistant.memory.page")
    }

    private func save() {
        do {
            if let editing { try memories.update(editing.id, version: editing.version, content: draft) }
            else { try memories.add(draft) }
            editing = nil; draft = ""; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
