import SwiftUI

struct AIChatWorkspaceView: View {
    @ObservedObject var store: AIChatStore
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.openSettings) private var openSettings
    @State private var historyPresented = false

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            HStack(spacing: 0) {
                if wide { history.frame(width: 224); Divider() }
                conversation(showHistoryButton: !wide)
            }
        }.accessibilityIdentifier("ai.chat.page").workflowActionAnchor("ai.chat.page")
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("历史对话").font(WFType.sectionSemibold)
                .padding(.horizontal, 18).padding(.top, 40).padding(.bottom, 20)
            ScrollView {
                LazyVStack(spacing: 4) {
                    if store.records.isEmpty {
                        Text("暂无对话").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }
                    ForEach(store.records.sorted { $0.updatedAt > $1.updatedAt }) { record in
                        Button {
                            store.select(record.id); historyPresented = false
                        } label: {
                            Text(record.title).font(WFType.supporting).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12).contentShape(Rectangle())
                                .background(record.id == store.current.record.id ? WFColors.selection : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("ai.chat.history.\(record.id)")
                            .workflowActionAnchor("ai.chat.history.\(record.id)")
                    }
                }.padding(.horizontal, 8)
            }.compactScrollbars()
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
                Button { store.newConversation() } label: { Label("新对话", systemImage: "square.and.pencil") }
                    .accessibilityLabel("新对话").accessibilityIdentifier("ai.chat.new").workflowActionAnchor("ai.chat.new")
                Button { environment.settingsSection = .ai; openSettings() } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 28, height: 28)
                }.accessibilityLabel("AI 模型设置")
            }.buttonStyle(.plain).padding(.horizontal, 24).padding(.top, 36).padding(.bottom, 14)
            AIConversationView(model: store.current, generate: { id, scene, context, message, updates in
                try await environment.conversationClient().send(id: id, scene: scene, context: context, message: message, updates: updates)
            }).id(store.current.record.id)
                .environment(\.openURL, OpenURLAction { url in
                    environment.openResourceLink(url) ? .handled : .systemAction
                })
            if let error = store.storageError { Text(error).font(WFType.caption).foregroundStyle(WFColors.danger) }
        }
    }
}
