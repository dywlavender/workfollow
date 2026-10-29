import SwiftUI

struct KnowledgeAnswerView: View {
    @ObservedObject var session: KnowledgeAnswerSession
    @EnvironmentObject private var environment: AppEnvironment
    var retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !session.question.isEmpty { Text(session.question).font(WFType.sectionSemibold).textSelection(.enabled) }
                switch session.phase {
                case .idle:
                    Text("输入问题后点击“问 AI”，从任务、笔记和会议中查找依据。")
                        .foregroundStyle(WFColors.secondaryText)
                case .searching, .answering:
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(session.phase == .searching ? "正在查找本地资料…" : session.status)
                        Spacer()
                        Button("停止") { session.cancel() }.buttonStyle(.borderless)
                    }
                    if !session.preview.isEmpty { Text(session.preview).textSelection(.enabled) }
                case .noResults:
                    Text("没有找到相关资料。试试补充项目名、客户名或笔记中的关键词。")
                        .foregroundStyle(WFColors.secondaryText)
                case let .failed(message):
                    AIWorkflowFailureView(message: message, retryAt: session.retryAt, retry: retry)
                case .ready:
                    if let answer = session.answer {
                        if answer.insufficient {
                            Text("找到的资料不足以回答这个问题，请补充关键词或调整问题。")
                                .foregroundStyle(WFColors.secondaryText)
                            ForEach(session.usedSources) { source in sourceButton(source, quote: nil) }
                        } else {
                            ForEach(Array(answer.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(paragraph.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    ForEach(Array(paragraph.citations.enumerated()), id: \.offset) { _, citation in
                                        if let source = session.usedSources.first(where: { $0.id == citation.source }) {
                                            sourceButton(source, quote: citation.quote)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if !session.result.sources.isEmpty {
                    Text("仅依据本次检索选取的 \(session.usedSources.count) 处资料回答，未覆盖的内容可能遗漏。")
                        .font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                }
                if session.result.unreadableDocuments > 0 {
                    Text("\(session.result.unreadableDocuments) 份正文读取失败，未纳入本次检索。")
                        .font(WFType.caption).foregroundStyle(WFColors.danger)
                }
            }
            .font(WFType.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .compactScrollbars()
        .accessibilityIdentifier("knowledge.answer")
    }

    private func sourceButton(_ source: KnowledgePassage, quote: String?) -> some View {
        Button { environment.openKnowledgeSource(source) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: source.kind.symbol)
                    Text("[\(source.id.dropFirst())] \(source.title)").lineLimit(1)
                    Spacer(minLength: 4)
                    Text(source.location).lineLimit(1)
                    Image(systemName: "arrow.up.right")
                }.foregroundStyle(WFColors.accent)
                if let quote { Text(quote).foregroundStyle(WFColors.secondaryText).lineLimit(4) }
            }
            .font(WFType.supporting)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WFColors.canvas, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("knowledge.source.\(source.id)")
        .workflowActionAnchor("knowledge.source.\(source.id)")
    }
}
