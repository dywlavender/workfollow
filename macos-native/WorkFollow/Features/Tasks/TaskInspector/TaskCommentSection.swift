import SwiftUI

/// 详情内联评论区（TI2-09）。
///
/// 滴答把评论做成详情底部的一块（`TTTaskDetailBottomView.showAddCommentView:` +
/// 评论 cell 的展开/收起），本地此前是底栏 💬 弹浮层。这里改成正文流里的
/// 折叠区块：有评论时显示"评论 n"标题行，点开是列表 + 原位输入框。
struct TaskCommentSection: View {
    let taskID: UUID
    @ObservedObject var store: TaskCommentStore
    @Binding var isExpanded: Bool
    @State private var draft = ""

    private var comments: [TaskComment] { store.comments(for: taskID) }

    var body: some View {
        if isExpanded || !comments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                header
                if isExpanded {
                    if comments.isEmpty {
                        Text("暂无评论，写下第一条吧。")
                            .font(WFType.supporting)
                            .foregroundStyle(WFColors.tertiaryText)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(comments) { comment in
                                commentRow(comment)
                            }
                        }
                    }
                    inputRow
                }
            }
            .inspectorRenderAnchor(.commentSection)
        }
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 11))
                    .foregroundStyle(WFColors.secondaryText)
                Text(comments.isEmpty ? "评论" : "评论 \(comments.count)")
                    .font(WFType.listTitleMedium)
                    .foregroundStyle(WFColors.text)
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WFColors.tertiaryText)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "收起评论" : "展开评论")
        .accessibilityLabel(isExpanded ? "收起评论" : "展开评论")
    }

    private func commentRow(_ comment: TaskComment) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(comment.text)
                    .font(WFType.body)
                    .foregroundStyle(WFColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    store.delete(comment.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(WFColors.tertiaryText)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("删除评论")
                .accessibilityLabel("删除评论")
            }
            Text(Self.timeText(comment.createdAt))
                .font(WFType.caption)
                .foregroundStyle(WFColors.tertiaryText)
        }
        .padding(.vertical, 2)
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("添加评论…", text: $draft)
                .textFieldStyle(.plain)
                .font(WFType.body)
                .onSubmit(post)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(WFColors.hover, in: RoundedRectangle(cornerRadius: 6))
            Button("发送", action: post)
                .buttonStyle(.plain)
                .font(WFType.control)
                .foregroundStyle(canPost ? WFColors.accent : WFColors.tertiaryText)
                .disabled(!canPost)
                .accessibilityLabel("发送评论")
        }
    }

    private var canPost: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func post() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.add(taskID: taskID, text: text)
        draft = ""
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
