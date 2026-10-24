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
    /// 正在编辑的评论 id 与它的草稿（TI2-09 剩余项：`editButton` / 编辑评论）。
    @State private var editingID: UUID?
    @State private var editingDraft = ""
    /// 正在回复的父评论 id（`replyOrRemoveButton`）。nil = 发顶层评论。
    @State private var replyToID: UUID?

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
                            ForEach(topLevelComments) { comment in
                                commentRow(comment, depth: 0)
                                ForEach(store.replies(to: comment.id, in: comments)) { reply in
                                    commentRow(reply, depth: 1)
                                }
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

    private func commentRow(_ comment: TaskComment, depth: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if editingID == comment.id {
                editingRow(comment)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(comment.text)
                        .font(WFType.body)
                        .foregroundStyle(WFColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    // 回复只对顶层评论开放（滴答的回复是一级缩进，不做嵌套回复）。
                    if depth == 0 {
                        Button { beginReply(comment) } label: {
                            Image(systemName: "arrowshape.turn.up.left")
                                .font(.system(size: 9))
                                .foregroundStyle(WFColors.tertiaryText)
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("回复")
                        .accessibilityLabel("回复评论")
                    }
                    Button { beginEdit(comment) } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(WFColors.tertiaryText)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("编辑评论")
                    .accessibilityLabel("编辑评论")
                    Button { store.delete(comment.id) } label: {
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
            }
            HStack(spacing: 6) {
                Text(Self.timeText(comment.createdAt))
                    .font(WFType.caption)
                    .foregroundStyle(WFColors.tertiaryText)
                if comment.editedAt != nil {
                    Text("已编辑")
                        .font(WFType.caption)
                        .foregroundStyle(WFColors.tertiaryText)
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, depth == 0 ? 0 : 16)
    }

    private func editingRow(_ comment: TaskComment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("编辑评论…", text: $editingDraft)
                .textFieldStyle(.plain)
                .font(WFType.body)
                .onSubmit { commitEdit(comment) }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(WFColors.hover, in: RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("取消") { cancelEdit() }
                    .buttonStyle(.plain)
                    .font(WFType.control)
                    .foregroundStyle(WFColors.secondaryText)
                Button("保存") { commitEdit(comment) }
                    .buttonStyle(.plain)
                    .font(WFType.control)
                    .foregroundStyle(canCommitEdit ? WFColors.accent : WFColors.tertiaryText)
                    .disabled(!canCommitEdit)
                    .accessibilityLabel("保存评论")
            }
        }
    }

    private var canCommitEdit: Bool {
        !editingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func beginEdit(_ comment: TaskComment) {
        editingID = comment.id
        editingDraft = comment.text
        replyToID = nil
    }

    private func cancelEdit() {
        editingID = nil
        editingDraft = ""
    }

    private func commitEdit(_ comment: TaskComment) {
        guard canCommitEdit else { return }
        _ = store.update(comment.id, text: editingDraft)
        cancelEdit()
    }

    private func beginReply(_ comment: TaskComment) {
        replyToID = comment.id
        editingID = nil
    }

    private var inputRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let replyToID, let target = comments.first(where: { $0.id == replyToID }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 9))
                        .foregroundStyle(WFColors.secondaryText)
                    Text("回复 \(Self.preview(target.text))")
                        .font(WFType.caption)
                        .foregroundStyle(WFColors.secondaryText)
                        .lineLimit(1)
                    Button {
                        self.replyToID = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8))
                            .foregroundStyle(WFColors.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .help("取消回复")
                    .accessibilityLabel("取消回复")
                }
            }
            HStack(spacing: 8) {
            TextField(replyToID == nil ? "添加评论…" : "回复…", text: $draft)
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
    }

    private var canPost: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func post() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.add(taskID: taskID, text: text, parentID: replyToID)
        draft = ""
        replyToID = nil
    }

    private var topLevelComments: [TaskComment] {
        comments.filter { $0.parentID == nil }
    }

    private static func preview(_ text: String) -> String {
        let flattened = text.replacingOccurrences(of: "\n", with: " ")
        return flattened.count > 24 ? String(flattened.prefix(24)) + "…" : flattened
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
