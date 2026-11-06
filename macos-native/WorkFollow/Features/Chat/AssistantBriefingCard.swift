import SwiftUI

struct AssistantBriefingCard: View {
    @ObservedObject var store: AssistantBriefingStore
    @ObservedObject var conversation: AIConversationModel
    let refresh: () -> Void
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 8) {
                        Text("今日简报").font(WFType.sectionSemibold)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(WFType.caption)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).workflowActionAnchor("assistant.briefing.expand")
                Spacer()
                if store.isRunning {
                    ProgressView().controlSize(.small)
                    Button("停止") { store.stop() }.buttonStyle(.plain)
                } else {
                    Button("刷新", systemImage: "arrow.clockwise", action: refresh)
                        .buttonStyle(.plain).disabled(conversation.isRunning)
                        .workflowActionAnchor("assistant.briefing.refresh")
                }
            }
            if expanded {
                if store.isRunning && !store.preview.isEmpty { AIMessageContent(text: store.preview) }
                else if let current = store.current {
                    AIMessageContent(text: current.text)
                    Text("更新于 " + current.generatedAt.formatted(date: .omitted, time: .shortened))
                        .font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                } else if !store.isRunning {
                    Text("查看今天的重点、逾期和临近截止事项。")
                        .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                }
                if let error = store.error {
                    Text(error).font(WFType.supporting).foregroundStyle(WFColors.danger)
                }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .workfollowCardSurface(in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("assistant.briefing.card")
            .onAppear { expanded = conversation.record.messages.isEmpty }
            .onChange(of: conversation.record.messages.isEmpty) { _, empty in if !empty { expanded = false } }
    }
}
