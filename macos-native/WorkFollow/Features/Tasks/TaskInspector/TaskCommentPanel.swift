import SwiftUI

/// 任务级评论面板（滴答详情底栏 💬 出口的单机版）。
/// 列表按创建时间正序（旧→新），底部输入框发表新评论。
struct TaskCommentPanel: View {
    let taskID: UUID
    @ObservedObject var store: TaskCommentStore
    let onClose: () -> Void
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("评论").font(.headline)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭评论")
            }
            .padding(16)
            Divider()

            let comments = store.comments(for: taskID)
            if comments.isEmpty {
                VStack(spacing: 8) {
                    Text("暂无评论").foregroundStyle(WFColors.text)
                    Text("写下第一条评论吧。").font(WFType.caption)
                        .foregroundStyle(WFColors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(comments) { comment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(comment.text)
                                    .font(WFType.body)
                                    .foregroundStyle(WFColors.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(comment.createdAt,
                                     format: .dateTime.year().month().day().hour().minute())
                                    .font(WFType.caption)
                                    .foregroundStyle(WFColors.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }
            }

            Divider()
            HStack(spacing: 8) {
                TextField("添加评论…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(WFType.body)
                    .onSubmit(submit)
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(canSubmit ? WFColors.accent : WFColors.secondaryText)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .accessibilityLabel("发送评论")
            }
            .padding(12)
        }
        .frame(width: 320, height: 400)
        .accessibilityIdentifier("task-comment-panel")
    }

    private var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.add(taskID: taskID, text: text)
        draft = ""
    }
}
