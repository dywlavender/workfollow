import SwiftUI

struct AIChatWorkspaceView: View {
    @ObservedObject var store: AIChatStore
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.openSettings) private var openSettings
    @State private var historyPresented = false
    @State private var deletionTarget: AIConversationRecord?
    @State private var referencesPresented = false

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            HStack(spacing: 0) {
                if wide { history.frame(width: 224).workfollowPageSurface(0.85); Divider() }
                conversation(showHistoryButton: !wide)
            }
        }.accessibilityIdentifier("ai.chat.page").workflowActionAnchor("ai.chat.page")
            .workfollowAlert(
                "删除这段对话？",
                message: "将删除“\(deletionTarget?.title ?? "")”及其本地会话记录，无法恢复。已创建的待办和笔记会保留。",
                isPresented: Binding(
                    get: { deletionTarget != nil }, set: { if !$0 { deletionTarget = nil } }
                ),
                actions: [
                    .cancel(),
                    .destructive("删除") {
                        guard let record = deletionTarget else { return }
                        deletionTarget = nil
                        _Concurrency.Task {
                            await store.delete(record.id) { id in
                                try await environment.conversationClient().delete(id: id)
                            }
                        }
                    }
                ])
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                store.newConversation(); historyPresented = false
            } label: {
                Label("新对话", systemImage: "square.and.pencil")
                    .font(WFType.control)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WFColors.border))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("新对话").accessibilityIdentifier("ai.chat.new").workflowActionAnchor("ai.chat.new")
                .padding(.horizontal, 12).padding(.top, 36).padding(.bottom, 24)
            Text("历史对话").font(WFType.sectionSemibold)
                .padding(.horizontal, 18).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 4) {
                    if store.records.isEmpty {
                        Text("暂无对话").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }
                    ForEach(store.records.sorted { $0.updatedAt > $1.updatedAt }) { record in
                        AIChatHistoryRow(record: record, selected: record.id == store.current.record.id,
                                         deleting: store.deletingIDs.contains(record.id)) {
                            store.select(record.id); historyPresented = false
                        } onDelete: {
                            historyPresented = false; deletionTarget = record
                        }
                    }
                }.padding(.horizontal, 8)
            }.compactScrollbars()
            Divider()
            PiChatModelButton(store: environment.meetingStore, disabled: store.current.isRunning).padding(.horizontal, 8)
            Button { environment.settingsSection = .ai; openSettings() } label: {
                Label("模型设置", systemImage: "slider.horizontal.3")
                    .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).padding(8)
                .accessibilityLabel("AI 模型设置").accessibilityIdentifier("ai.chat.settings")
                .workflowActionAnchor("ai.chat.settings")
        }.frame(maxHeight: .infinity)
            .accessibilityIdentifier("ai.chat.history").workflowActionAnchor("ai.chat.history")
    }

    private func conversation(showHistoryButton: Bool) -> some View {
        let current = store.current
        return VStack(spacing: 0) {
            HStack(spacing: 16) {
                if showHistoryButton {
                    Button("历史对话", systemImage: "clock.arrow.circlepath") { historyPresented = true }
                        .propertyPanelTrigger("ai.chat.history")
                }
                Text("AI 对话").font(WFType.detailTitle)
                Spacer()
                Button("引用资料", systemImage: "paperclip") { referencesPresented = true }
                    .workflowActionAnchor("ai.chat.reference")
                    .propertyPanelTrigger("ai.chat.references")
            }
            .buttonStyle(.plain).padding(.horizontal, 24).padding(.top, 36).padding(.bottom, 14)
            .anchoredPropertyPanel(isPresented: $historyPresented, trigger: "ai.chat.history",
                                   width: 250, placement: .vertical, title: "历史对话") {
                history.frame(height: 420)
            }
            .anchoredPropertyPanel(isPresented: $referencesPresented, trigger: "ai.chat.references",
                                   width: 340, placement: .dropdown,
                                   focusPolicy: .panel, title: "引用资料") {
                AIReferencePicker { reference in
                    var values = store.current.record.references ?? []
                    if !values.contains(where: { $0.id == reference.id }) { values.append(reference) }
                    store.current.setReferences(values); referencesPresented = false
                }.environmentObject(environment)
            }
            if let references = store.current.record.references, !references.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(references) { reference in
                            HStack(spacing: 6) {
                                Image(systemName: reference.kind == "note" ? "text.document" : "checkmark.square")
                                Text(reference.title).lineLimit(1)
                                Button { store.current.setReferences(references.filter { $0.id != reference.id }) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain).accessibilityLabel("移除引用：\(reference.title)")
                            }.font(WFType.supporting).padding(8).background(WFColors.secondarySurface, in: Capsule())
                        }
                    }.padding(.horizontal, 24)
                }.padding(.bottom, 8)
            }
            AIConversationView(model: current, generate: environment.conversationClient().generator(for: current),
               undoAction: { environment.undoAIAction($0) },
               canUndoAction: { environment.taskWorkspace.automationUndoID == $0.undoID }).id(store.current.record.id)
                .disabled(store.deletingIDs.contains(store.current.record.id))
                .environment(\.openURL, OpenURLAction { url in
                    environment.openResourceLink(url) ? .handled : .systemAction
                })
            if let error = store.storageError { Text(error).font(WFType.caption).foregroundStyle(WFColors.danger) }
        }
    }
}

private struct AIChatHistoryRow: View {
    let record: AIConversationRecord
    let selected: Bool
    let deleting: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                Text(record.title).font(WFType.supporting).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12).padding(.vertical, 12).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityIdentifier("ai.chat.history.\(record.id)")
                .workflowActionAnchor("ai.chat.history.\(record.id)")
            Button(action: onDelete) {
                Image(systemName: "trash").font(WFType.supporting).frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(WFColors.secondaryText)
                .opacity(hovered || selected ? 1 : 0)
                .hoverTip("删除对话").accessibilityLabel("删除对话：\(record.title)")
                .accessibilityIdentifier("ai.chat.delete.\(record.id)")
                .workflowActionAnchor("ai.chat.delete.\(record.id)")
        }.padding(.trailing, 6)
            .background(selected ? WFColors.selection : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle()).onHover { hovered = $0 }.disabled(deleting)
            .contextMenu {
                Button("删除对话", systemImage: "trash", role: .destructive, action: onDelete).disabled(deleting)
            }
    }
}
