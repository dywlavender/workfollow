import SwiftUI

struct MeetingCorrectionTarget: Identifiable {
    let meetingID: UUID
    let line: MeetingTranscriptLine
    var id: UUID { line.id }
}

struct MeetingTranscriptEditor: View {
    let save: (String, String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var speaker: String
    @State private var renameAll = false
    init(line: MeetingTranscriptLine, save: @escaping (String, String, Bool) -> Void) {
        self.save = save; _text = State(initialValue: line.text); _speaker = State(initialValue: line.speakerDisplayName)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("校正对话").font(WFType.detailTitle)
            TextField("讲话人", text: $speaker).textFieldStyle(.roundedBorder)
            Toggle("同时修改该讲话人的其他片段", isOn: $renameAll).font(WFType.supporting)
            TextEditor(text: $text).font(WFType.body).frame(minHeight: 150)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(WFColors.border))
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") { save(text, speaker, renameAll); dismiss() }
                    .workflowActionAnchor("meeting.correction.save")
                    .keyboardShortcut(.defaultAction).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(22).frame(width: 500)
            .workfollowPopupSurface(fallback: WFColors.canvas)
    }
}
