import SwiftUI

struct AIChatWorkspaceView: View {
    @ObservedObject var store: AIChatStore
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.openSettings) private var openSettings
    @State private var historyPresented = false
    @State private var deletionTarget: AIConversationRecord?

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            HStack(spacing: 0) {
                if wide { history.frame(width: 224); Divider() }
                conversation(showHistoryButton: !wide)
            }
        }.accessibilityIdentifier("ai.chat.page").workflowActionAnchor("ai.chat.page")
            .alert("删除这段对话？", isPresented: Binding(
                get: { deletionTarget != nil }, set: { if !$0 { deletionTarget = nil } }
            )) {
                Button("取消", role: .cancel) { deletionTarget = nil }
                Button("删除", role: .destructive) {
                    guard let record = deletionTarget else { return }
                    deletionTarget = nil
                    _Concurrency.Task {
                        await store.delete(record.id) { id in
                            try await environment.conversationClient().delete(id: id)
                        }
                    }
                }
            } message: {
                Text("将删除“\(deletionTarget?.title ?? "")”及其本地会话记录，无法恢复。已创建的待办和笔记会保留。")
            }
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
            Button { environment.settingsSection = .ai; openSettings() } label: {
                Label("模型设置", systemImage: "slider.horizontal.3")
                    .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).padding(8)
                .accessibilityLabel("AI 模型设置").accessibilityIdentifier("ai.chat.settings")
                .workflowActionAnchor("ai.chat.settings")
        }.frame(maxHeight: .infinity).background(WFColors.canvas)
            .accessibilityIdentifier("ai.chat.history").workflowActionAnchor("ai.chat.history")
    }

    private func conversation(showHistoryButton: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                if showHistoryButton {
                    Button("历史对话", systemImage: "clock.arrow.circlepath") { historyPresented = true }
                        .popover(isPresented: $historyPresented) { history.frame(width: 250, height: 420) }
                }
                Text("AI 对话").font(WFType.detailTitle)
                Spacer()
            }.buttonStyle(.plain).padding(.horizontal, 24).padding(.top, 36).padding(.bottom, 14)
            AIConversationView(model: store.current, generate: { id, scene, context, message, updates in
                try await environment.conversationClient().send(id: id, scene: scene, context: context, message: message, updates: updates)
            }).id(store.current.record.id)
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
