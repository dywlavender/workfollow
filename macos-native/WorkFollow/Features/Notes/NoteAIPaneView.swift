import AppKit
import SwiftUI

enum NoteAIPaneMetrics {
    static let defaultWidth: CGFloat = 360
    static let minimumWidth: CGFloat = 280
    static let maximumWidth: CGFloat = 440
    static let editorMinimumWidth: CGFloat = 480
    static let compactEditorMinimumWidth: CGFloat = 320
    static let draftEditorSize = CGSize(width: 400, height: 356)
}

/// 笔记编辑栏右侧的 AI 对话栏。动作与消息都在这里完成，不再为「整理/润色/提取」
/// 各开一个 sheet；任务候选行复用任务行的勾选框、标题、日期与原文预览。
struct NoteAIPaneView: View {
    @ObservedObject var model: NoteAIConversationModel
    @ObservedObject var tasks: TaskWorkspaceModel
    let noteID: UUID
    let noteTitle: String
    let noteContentIsEmpty: Bool
    let canReplaceBody: Bool
    @Binding var destination: String
    @Binding var sectionID: String?
    let makeContext: () -> NoteAIContext
    let onPrepareDocument: () -> Void
    let onReplaceBody: (String) -> Void
    let onEditDraft: (UUID, UUID, CGRect) -> Void
    let onRevealTasks: ([UUID]) -> Void
    let onOpenNote: (UUID) -> Void
    let onClose: () -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.workfollowPageCanvasActive) private var pageCanvasActive

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            AIConversationView(model: model.conversation, generate: generate,
                undoAction: { environment.undoAIAction($0) },
                canUndoAction: { environment.taskWorkspace.automationUndoID == $0.undoID },
                compact: true, identifierPrefix: "note.ai",
                leadingContent: AnyView(VStack(alignment: .leading, spacing: 14) { greeting; actionCards }),
                artifactContent: { message in AnyView(resultCards(message)) },
                submit: sendMessage)
                .id(model.conversation.record.id)
                .environment(\.openURL, OpenURLAction { url in
                    environment.openResourceLink(url) ? .handled : .systemAction
                })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 它是笔记页的一栏，不是浮层：整窗画布生效时让出灰底，
        // 编辑区和 AI 栏才会落在同一层连续底色上。
        .background(pageCanvasActive ? Color.clear : WFColors.panelFill)
        .hidesSystemFocusEffect()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI 助手")
        .workflowActionAnchor("note.ai.pane")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WFColors.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("AI 助手").font(.system(size: 13, weight: .semibold))
                Text("基于当前笔记「\(noteTitle)」")
                    .font(.system(size: 10))
                    .foregroundStyle(WFColors.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { model.reset() } label: {
                Image(systemName: "plus").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .hoverTip("新对话")
            .disabled(model.isRunning || model.conversation.record.messages.isEmpty)
            .opacity(model.isRunning || model.conversation.record.messages.isEmpty ? 0.35 : 1)
            Button(action: onClose) {
                Image(systemName: "xmark").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .hoverTip("关闭 AI 助手")
        }
        .padding(.horizontal, 16)
        // 与编辑栏顶栏同高，两栏的分割线才能连成一条。
        .frame(height: 44)
    }

    private var greeting: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle().fill(WFColors.selection)
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WFColors.accent)
            }
            .frame(width: 24, height: 24)
            Text("可以直接与我交流，也可以一键整理、润色或提取待办。")
                .font(.system(size: 12))
                .foregroundStyle(WFColors.text)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionCards: some View {
        VStack(spacing: 6) {
            ForEach(NoteAIAction.allCases) { action in
                Button { start(action) } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7).fill(WFColors.secondarySurface)
                            Image(systemName: action.symbol)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WFColors.secondaryText)
                        }
                        .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(action.title).font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(WFColors.text)
                            Text(action.subtitle).font(.system(size: 10))
                                .foregroundStyle(WFColors.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 48)
                    .background(WFColors.content,
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(WFColors.overlayBorder, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isAllowed(action) || model.isRunning || model.attachments.isImporting)
                .opacity(isAllowed(action) ? 1 : 0.45)
                .hoverTip(isAllowed(action) ? action.title : disabledTip(action))
                .workflowActionAnchor(action.workflowAnchor)
            }
        }
    }

    private func isAllowed(_ action: NoteAIAction) -> Bool {
        if !model.attachments.items.isEmpty { return true }
        return switch action {
        case .extract: !noteContentIsEmpty || !noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .organize, .polish: !noteContentIsEmpty
        }
    }

    private func disabledTip(_ action: NoteAIAction) -> String {
        action == .extract ? "笔记还没有内容" : "笔记还没有正文"
    }

    @ViewBuilder
    private func resultCards(_ message: AIConversationMessage) -> some View {
        ForEach(model.results(for: message)) { exchange in
            if let session = exchange.taskSession {
                NoteAITaskExchangeView(exchange: exchange, session: session,
                    destination: $destination, sectionID: $sectionID, tasks: tasks,
                    onEditDraft: { draftID, rect in onEditDraft(exchange.id, draftID, rect) },
                    onReveal: onRevealTasks,
                    onRetry: { model.retry(messageID: message.id, using: generate) })
            } else if let session = exchange.rewriteSession {
                NoteAIRewriteExchangeView(exchange: exchange, session: session,
                    canReplaceBody: canReplaceBody, onReplaceBody: onReplaceBody, onOpenNote: onOpenNote,
                    onRetry: { model.retry(messageID: message.id, using: generate) })
            }
        }
    }

    private func start(_ action: NoteAIAction) {
        guard !model.isRunning, isAllowed(action) else { return }
        onPrepareDocument()
        model.ask(action, context: makeContext(), using: generate)
    }

    private func sendMessage() {
        guard model.canSend else { return }
        onPrepareDocument()
        model.send(context: makeContext(), using: generate)
    }

    private var generate: AIConversationModel.Generate {
        environment.conversationClient().generator(for: model.conversation)
    }

}

// MARK: - 提取待办结果

private struct NoteAITaskExchangeView: View {
    @ObservedObject var exchange: NoteAIExchange
    @ObservedObject var session: AITaskDraftSession
    @Binding var destination: String
    @Binding var sectionID: String?
    @ObservedObject var tasks: TaskWorkspaceModel
    let onEditDraft: (UUID, CGRect) -> Void
    let onReveal: ([UUID]) -> Void
    let onRetry: () -> Void

    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        switch session.phase {
        case .loading:
            streaming
        case let .failed(message):
            AIWorkflowFailureView(message: message, retryAt: session.retryAt, retry: onRetry)
                .padding(12)
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).stroke(WFColors.overlayBorder, lineWidth: 1)
                }
        case .ready:
            ready
        }
    }

    private var streaming: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text(session.status).font(.system(size: 11)).foregroundStyle(WFColors.secondaryText)
            }
            if !session.preview.isEmpty {
                Text(session.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(WFColors.secondaryText)
                    .lineLimit(10)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(WFColors.overlayBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var ready: some View {
        if session.drafts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("没有发现新的\(exchange.taskRequest?.isBreakdown == true ? "子任务" : "待办")")
                    .font(.system(size: 12, weight: .medium))
                Text("原有内容和任务保持不变").font(.system(size: 11))
                    .foregroundStyle(WFColors.secondaryText)
                Button("重新生成", action: onRetry).font(.system(size: 11))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).stroke(WFColors.overlayBorder, lineWidth: 1)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(session.drafts.count) 项待办")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button(session.drafts.allSatisfy { $0.selected } ? "全不选" : "全选") {
                        let next = !session.drafts.allSatisfy { $0.selected }
                        for index in session.drafts.indices { session.drafts[index].selected = next }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(WFColors.accent)
                    .disabled(exchange.isApplied)
                }
                VStack(spacing: 0) {
                    ForEach(session.drafts.indices, id: \.self) { index in
                        NoteAITaskDraftRow(index: index, draft: $session.drafts[index],
                                           now: tasks.clock(), calendar: tasks.calendar,
                                           isApplied: exchange.isApplied,
                                           onEdit: { rect in
                                               onEditDraft(session.drafts[index].id, rect)
                                           })
                        if index < session.drafts.count - 1 {
                            Divider().padding(.leading, 27)
                        }
                    }
                }
                if !exchange.isApplied {
                    createButton
                }
                destinationRow
                if exchange.isApplied {
                    appliedSummary
                }
                if let error = exchange.applyError {
                    Text(error).font(.system(size: 10.5)).foregroundStyle(WFColors.danger)
                }
            }
        }
    }

    private var createButton: some View {
        Button(action: apply) {
            Text("创建 \(session.selectedCount) 项待办")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(WFColors.accent, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(session.selectedCount == 0)
        .opacity(session.selectedCount == 0 ? 0.45 : 1)
        .workflowActionAnchor("note.ai.create")
    }

    private var destinationRow: some View {
        HStack(spacing: 6) {
            if exchange.isApplied {
                Text("已保存到「\(destination)」")
                    .font(.system(size: 9.5))
                    .foregroundStyle(WFColors.tertiaryText)
            } else {
                Text("保存到").font(.system(size: 9.5)).foregroundStyle(WFColors.secondaryText)
                BusinessMenu {
                    ForEach(environment.taskWorkspace.availableListNames, id: \.self) { name in
                        BusinessMenuOption(name, selected: destination == name, symbol: "list.bullet") {
                            destination = name
                            sectionID = nil
                        }
                    }
                } label: {
                    Label(destination, systemImage: destination == TaskList.inbox.name ? "tray" : "list.bullet")
                        .font(.system(size: 9.5))
                }
                let sections = environment.taskWorkspace.listSections(forList: destination)
                if !sections.isEmpty {
                    BusinessMenu {
                        BusinessMenuOption("未分组", selected: sectionID == nil) { sectionID = nil }
                        ForEach(sections) { section in
                            BusinessMenuOption(section.title, selected: sectionID == section.id) {
                                sectionID = section.id
                            }
                        }
                    } label: {
                        Text(sections.first { $0.id == sectionID }?.title ?? "未分组")
                            .font(.system(size: 9.5))
                    }
                }
            }
            Spacer(minLength: 4)
            Text("保留来源与原文").font(.system(size: 9)).foregroundStyle(WFColors.tertiaryText)
        }
    }

    private var appliedSummary: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(WFColors.accent)
            Text("已创建 \(exchange.appliedIDs.count) 项待办")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Button("撤销") { undo() }
                .buttonStyle(.plain).font(.system(size: 10.5))
                .foregroundStyle(WFColors.secondaryText)
                .workflowActionAnchor("note.ai.undoCreated")
            Button("查看") { onReveal(exchange.appliedIDs) }
                .buttonStyle(.plain).font(.system(size: 10.5))
                .foregroundStyle(WFColors.accent)
        }
        .padding(.top, 2)
    }

    private func apply() {
        guard let request = exchange.taskRequest else { return }
        do {
            let ids = try environment.applyAITasks(session.drafts, request: request,
                                                   list: destination, sectionID: sectionID)
            guard !ids.isEmpty else {
                exchange.applyError = "这些任务已存在，无需重复添加"
                return
            }
            exchange.markApplied(ids)
        } catch {
            exchange.applyError = error.localizedDescription
        }
    }

    private func undo() {
        for id in exchange.appliedIDs {
            _ = environment.taskWorkspace.delete(id)
        }
        exchange.markUnapplied()
    }
}

// MARK: - 候选任务行

private struct NoteAITaskDraftRow: View {
    let index: Int
    @Binding var draft: AITaskDraft
    let now: Date
    let calendar: Calendar
    let isApplied: Bool
    let onEdit: (CGRect) -> Void

    @State private var anchor = PlanningAnchorRef()
    @State private var hovering = false

    private var dueText: String? {
        draft.plan.schedule.dueAt.map {
            TaskDateLabel.text($0, hasTime: draft.plan.schedule.hasTime,
                               now: now, calendar: calendar)
        }
    }

    private var deadlineText: String? {
        draft.plan.schedule.deadlineAt.map {
            "截止 " + TaskDateLabel.text($0, hasTime: false, now: now, calendar: calendar)
        }
    }

    private var dueColor: Color {
        guard let due = draft.plan.schedule.dueAt else { return WFColors.secondaryText }
        let day = calendar.startOfDay(for: due)
        let today = calendar.startOfDay(for: now)
        return day < today ? WFColors.danger : WFColors.accent
    }

    private var checkboxStroke: Color {
        draft.priority == .none ? WFColors.borderStrong : draft.priority.menuColor
    }

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Button { draft.selected.toggle() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4.3)
                        .fill(draft.selected ? WFColors.accent : Color.clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4.3)
                                .stroke(draft.selected ? WFColors.accent : checkboxStroke, lineWidth: 1.5)
                        }
                        .frame(width: 17, height: 17)
                    if draft.selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 19, height: 19)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isApplied)
            .hoverTip(draft.selected ? "不创建这项" : "创建这项")
            .accessibilityLabel("采用候选任务：\(draft.title)")

            Button {
                guard !isApplied else { return }
                if let rect = anchor.rect { onEdit(rect) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(draft.title.isEmpty ? "未命名任务" : draft.title)
                            .font(WFType.listBody)
                            .foregroundStyle(draft.selected ? WFColors.text : WFColors.secondaryText)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        if let dueText {
                            Text(dueText)
                                .font(.system(size: 10))
                                .foregroundStyle(draft.selected ? dueColor : WFColors.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    if draft.quote.isEmpty == false || deadlineText != nil {
                        HStack(spacing: 6) {
                            if !draft.quote.isEmpty {
                                Text(draft.quote)
                                    .font(.system(size: 10))
                                    .foregroundStyle(WFColors.tertiaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if let deadlineText {
                                Text(deadlineText)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(WFColors.tertiaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isApplied)
            .accessibilityLabel("编辑候选任务：\(draft.title)")
            .workflowActionAnchor("note.ai.draft.\(index)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(hovering && !isApplied ? WFColors.hover : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7))
        .onHover { hovering = $0 }
        .background(PlanningAnchorProbe(ref: anchor))
        .opacity(isApplied ? 0.62 : 1)
    }
}

// MARK: - 润色 / 整理结果

private struct NoteAIRewriteExchangeView: View {
    @ObservedObject var exchange: NoteAIExchange
    @ObservedObject var session: NoteRewriteSession
    let canReplaceBody: Bool
    let onReplaceBody: (String) -> Void
    let onOpenNote: (UUID) -> Void
    let onRetry: () -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @State private var confirmReplace = false
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            switch session.phase {
            case .loading:
                streaming
            case let .failed(message):
                AIWorkflowFailureView(message: message, retryAt: session.retryAt, retry: onRetry)
                .padding(12)
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
            case .ready:
                ready
            }
        }
    }

    private var streaming: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text(session.status).font(.system(size: 11)).foregroundStyle(WFColors.secondaryText)
            }
            if !session.preview.isEmpty {
                Text(session.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(WFColors.secondaryText)
                    .lineLimit(12)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(WFColors.overlayBorder, lineWidth: 1)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextEditor(text: $session.draft)
                .font(WFType.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 200)
                .compactTextEditorScrollbars()
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).stroke(WFColors.overlayBorder, lineWidth: 1)
                }
                .accessibilityLabel("AI 笔记草稿")
            HStack(spacing: 8) {
                Button("保存为新笔记") { save() }
                    .buttonStyle(.bordered)
                    .disabled(saving || exchange.savedNoteID != nil)
                    .workflowActionAnchor("note.ai.save")
                Button("替换正文") { confirmReplace = true }
                    .buttonStyle(.bordered)
                    .disabled(!canReplaceBody || exchange.didReplaceBody)
                    .workflowActionAnchor("note.ai.replace")
                    .hoverTip(canReplaceBody ? "用结果覆盖当前笔记正文" : "浮窗编辑中或笔记保留了原始富文本，暂不支持替换")
                Spacer()
                Button { copy() } label: {
                    Image(systemName: "doc.on.doc").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .hoverTip("复制结果")
            }
            if let noteID = exchange.savedNoteID {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(WFColors.accent)
                    Text("已保存为新笔记").font(.system(size: 10.5))
                    Button("打开") { onOpenNote(noteID) }
                        .buttonStyle(.plain).font(.system(size: 10.5))
                        .foregroundStyle(WFColors.accent)
                }
            }
            if exchange.didReplaceBody {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(WFColors.accent)
                    Text("已替换当前正文").font(.system(size: 10.5))
                }
            }
            if let error = exchange.saveError {
                Text(error).font(.system(size: 10.5)).foregroundStyle(WFColors.danger)
            }
            Text("保存会另建笔记并附来源链接，不覆盖原文")
                .font(.system(size: 9))
                .foregroundStyle(WFColors.tertiaryText)
        }
        .workfollowAlert(
            "替换当前笔记正文？",
            message: "原文将被 AI 结果覆盖，标题保持不变。",
            isPresented: $confirmReplace,
            actions: [
                .cancel(),
                .destructive("替换") { replace() }
            ])
    }

    private func save() {
        guard !saving, let request = exchange.rewriteRequest else { return }
        saving = true
        defer { saving = false }
        do {
            let id = try environment.notesWorkspace.createAIRewrite(session.draft, request: request, select: false)
            exchange.markSaved(noteID: id)
        } catch {
            exchange.saveError = error.localizedDescription
        }
    }

    private func replace() {
        guard canReplaceBody else { return }
        onReplaceBody(session.draft)
        exchange.markReplaced()
    }

    private func copy() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(session.draft, forType: .string)
    }
}
