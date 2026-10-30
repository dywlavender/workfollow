import AppKit
import SwiftUI

/// Shared transcript and composer for full-page and selected-text conversations.
struct AIConversationView: View {
    @ObservedObject var model: AIConversationModel
    let generate: AIConversationModel.Generate
    var adopt: ((String, Bool) -> Void)?
    var undoAction: ((AIActionReceipt) -> Void)? = nil
    var canUndoAction: ((AIActionReceipt) -> Bool)? = nil
    var compact = false
    var identifierPrefix = "ai.chat"
    var leadingContent: AnyView? = nil
    var artifactContent: ((AIConversationMessage) -> AnyView)? = nil
    var submit: (() -> Void)? = nil
    @State private var pinned = true
    @State private var viewportHeight: CGFloat = 0
    @State private var bottom: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if let leadingContent { leadingContent }
                        if model.record.messages.isEmpty && leadingContent == nil {
                            Text(model.scene == .chat ? "今天想处理什么？" : "说说你希望怎样修改这段文字")
                                .font(WFType.detailTitle).foregroundStyle(WFColors.secondaryText)
                                .frame(maxWidth: .infinity).padding(.vertical, 72)
                        }
                        ForEach(model.record.messages) { message in
                            messageView(message).id(message.id)
                        }
                        Color.clear.frame(height: 1).id("conversation-bottom")
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: AIConversationBottom.self,
                                    value: geometry.frame(in: .named("conversation-scroll")).maxY)
                            })
                    }
                    .frame(maxWidth: 760).padding(compact ? 16 : 24).frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: "conversation-scroll")
                .background(GeometryReader { geometry in
                    Color.clear.onAppear { viewportHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, value in viewportHeight = value }
                })
                .onPreferenceChange(AIConversationBottom.self) { value in
                    bottom = value; pinned = value <= viewportHeight + 70
                }
                .compactScrollbars()
                .onChange(of: model.record.messages.count) { _, _ in
                    pinned = true; proxy.scrollTo("conversation-bottom", anchor: .bottom)
                }
                .onChange(of: model.record.messages.last?.text) { _, _ in
                    if pinned { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
                }
                .onChange(of: model.record.messages.last?.artifacts) { _, _ in
                    if pinned { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
                }
                .onAppear { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
            }
            if let text = model.latestWritingResult, let adopt {
                HStack(spacing: 18) {
                    Button("替换") { adopt(text, false) }
                        .accessibilityIdentifier("ai.selection.replace").workflowActionAnchor("ai.selection.replace")
                    Button("插入") { adopt(text, true) }
                        .accessibilityIdentifier("ai.selection.insert").workflowActionAnchor("ai.selection.insert")
                    Button("复制") { copy(text) }
                    Spacer()
                }.buttonStyle(.plain).foregroundStyle(WFColors.accent)
                    .padding(.horizontal, 24).padding(.bottom, 14).disabled(model.isRunning)
            }
            AIConversationComposer(model: model,
                placeholder: model.scene == .note ? "输入消息，或基于当前笔记提问…" : "输入消息…",
                submit: { if let submit { submit() } else { model.send(using: generate) } },
                compact: compact, identifierPrefix: identifierPrefix, instanceID: model.record.id)
                .frame(maxWidth: 800).padding(.horizontal, compact ? 16 : 24).padding(.bottom, compact ? 12 : 20)
        }.workfollowPageSurface(0.92)
    }

    @ViewBuilder private func messageView(_ message: AIConversationMessage) -> some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 8) {
                AIAttachmentStrip(items: message.attachments ?? [])
                if !message.text.isEmpty {
                    if message.role == .assistant { AIMessageContent(text: message.text) }
                    else { Text(message.text).font(WFType.body).lineSpacing(4).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading) }
                }
                if let artifactContent { artifactContent(message) }
                else { AIConversationArtifactsView(artifacts: message.artifacts ?? []) }
                ForEach(message.actions ?? []) { action in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(action.title).font(WFType.sectionSemibold)
                        Text(action.undone ? "已撤销" : action.details).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                        HStack(spacing: 16) {
                            if let raw = action.url, let url = URL(string: raw) { Link("打开", destination: url) }
                            if let undoAction, action.undoID != nil, !action.undone {
                                Button("撤销") { undoAction(action) }.disabled(model.isRunning || !(canUndoAction?(action) ?? true))
                                    .workflowActionAnchor("ai.action.undo.\(action.id)")
                            }
                        }.buttonStyle(.plain).font(WFType.supporting).foregroundStyle(WFColors.accent)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: 10))
                }
                if message.state == .generating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(model.status).font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                    }
                } else if message.state == .stopped {
                    Text("已停止").font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                }
                if let error = message.error {
                    Text(error).font(WFType.supporting).foregroundStyle(WFColors.danger)
                    Button("重试") { model.retry(message.id, using: generate) }.buttonStyle(.link).disabled(model.isRunning)
                }
                if message.role == .assistant, message.state != .generating, !message.text.isEmpty || message.artifacts?.isEmpty == false {
                    HStack(spacing: 16) {
                        Button("复制", systemImage: "doc.on.doc") {
                            copy(([message.text] + (message.artifacts ?? []).map(\.content)).filter { !$0.isEmpty }.joined(separator: "\n\n"))
                        }
                        if message.state == .stopped, message.id == model.record.messages.last?.id {
                            Button("继续回复", systemImage: "arrow.right") {
                                model.input = "请继续刚才未完成的回复"; model.send(using: generate)
                            }.disabled(model.isRunning)
                        }
                    }.buttonStyle(.plain).font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                }
            }
            .padding(message.role == .user ? 14 : 0)
            .background(message.role == .user ? WFColors.selection : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14))
            if message.role == .assistant { Spacer(minLength: 0) }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }

}

private struct AIConversationBottom: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
