import SwiftUI

struct NoteRewriteComposerView: View {
    let request: NoteRewriteRequest
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: NoteRewriteSession
    @State private var attempt = 0
    @State private var saving = false
    @State private var error: String?

    init(request: NoteRewriteRequest, session: NoteRewriteSession? = nil) {
        self.request = request
        _session = StateObject(wrappedValue: session ?? NoteRewriteSession())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(request.action.title).font(WFType.detailTitle)
                Text(request.title).font(WFType.supporting).foregroundStyle(WFColors.secondaryText).lineLimit(1)
            }.padding(20)
            Divider()
            Group {
                switch session.phase {
                case .loading:
                    AIStreamingTextView(text: session.preview, status: session.status)
                case let .failed(message):
                    AIWorkflowFailureView(message: message, retryAt: session.retryAt) { attempt += 1 }.padding(24)
                case .ready:
                    TextEditor(text: $session.draft).font(WFType.body).padding(16)
                        .scrollContentBackground(.hidden).accessibilityLabel("AI 笔记草稿")
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error { Text(error).foregroundStyle(WFColors.danger).padding(.horizontal, 20).padding(.bottom, 8) }
            Divider()
            HStack {
                Text("保留原笔记，结果另存并附来源链接").font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存为新笔记") { save() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                    .disabled(session.phase != .ready || session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                    .accessibilityIdentifier("note.ai.save")
                    .workflowActionAnchor("note.ai.save")
            }.padding(16)
        }
        .frame(width: 640, height: 540)
        .background(WFColors.content)
        .task(id: attempt) {
            await session.generate(request: request) { source, updates in
                try await environment.textAIClient().rewriteNote(source, updates: updates)
            }
        }
    }

    private func save() {
        guard !saving else { return }; saving = true
        do {
            let id = try environment.notesWorkspace.createAIRewrite(session.draft, request: request)
            _ = NativeResourceLinkRouter.open(.note(id), tasks: environment.taskWorkspace,
                notes: environment.notesWorkspace, navigation: environment.navigation)
            dismiss()
        } catch { self.error = error.localizedDescription; saving = false }
    }
}
