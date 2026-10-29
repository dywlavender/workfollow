import AppKit
import SwiftUI

/// Shared transcript and composer for full-page and selected-text conversations.
struct AIConversationView: View {
    @ObservedObject var model: AIConversationModel
    let generate: AIConversationModel.Generate
    var adopt: ((String, Bool) -> Void)?
    @State private var pinned = true
    @State private var viewportHeight: CGFloat = 0
    @State private var bottom: CGFloat = 0
    @State private var inputIsLiveEmpty = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if model.record.messages.isEmpty {
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
                    .frame(maxWidth: 760).padding(24).frame(maxWidth: .infinity)
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
                .onAppear { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
            }
            if let text = model.latestResult, let adopt {
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
            HStack(alignment: .bottom, spacing: 12) {
                AIConversationInput(text: $model.input,
                                    submit: { model.send(using: generate) },
                                    onLiveTextIsEmptyChange: { inputIsLiveEmpty = $0 })
                    .frame(height: 72).accessibilityIdentifier("ai.chat.input")
                    .overlay(alignment: .topLeading) {
                        if model.input.isEmpty && inputIsLiveEmpty {
                            Text(model.scene == .chat ? "查询笔记、安排待办…" : "输入修改要求…")
                                .font(WFType.body).foregroundStyle(WFColors.tertiaryText)
                                .padding(.top, 6).padding(.leading, 7).allowsHitTesting(false)
                                .livePlaceholderProbe("ai.chat.placeholder")
                        }
                    }
                Button {
                    if model.isRunning { model.stop() } else { model.send(using: generate) }
                } label: {
                    Image(systemName: model.isRunning ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .semibold)).frame(width: 32, height: 32)
                }
                .buttonStyle(.borderedProminent).clipShape(Circle())
                .disabled(!model.isRunning && !model.canSend)
                .accessibilityLabel(model.isRunning ? "停止生成" : "发送消息")
                .accessibilityIdentifier("ai.chat.send").workflowActionAnchor("ai.chat.send")
                .workflowActionAnchor("ai.chat.send.\(model.record.id)")
            }
            .padding(12)
            .background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(WFColors.overlayBorder, lineWidth: 1))
            .frame(maxWidth: 800).padding(.horizontal, 24).padding(.bottom, 20)
        }.background(WFColors.content)
    }

    @ViewBuilder private func messageView(_ message: AIConversationMessage) -> some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 8) {
                if !message.text.isEmpty {
                    Text(displayText(message)).font(WFType.body).lineSpacing(4).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Button("重试") {
                        if let question = model.record.messages.last(where: { $0.role == .user })?.text {
                            model.input = question; model.send(using: generate)
                        }
                    }.buttonStyle(.link).disabled(model.isRunning)
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

    private func displayText(_ message: AIConversationMessage) -> AttributedString {
        guard message.role == .assistant else { return AttributedString(message.text) }
        return (try? AttributedString(markdown: message.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text)
    }
}

private struct AIConversationBottom: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Return sends; Shift-Return inserts a line break. Composition Return stays with the IME.
struct AIConversationInput: NSViewRepresentable {
    @Binding var text: String
    var submit: () -> Void
    /// 编辑区实时是否为空（输入法组合串也算有字）。占位文案不能等上屏才让位。
    var onLiveTextIsEmptyChange: (Bool) -> Void = { _ in }
    final class Input: NSTextView {
        var submit: () -> Void = {}
        var onLiveTextChange: (() -> Void)?
        var onCompositionEnded: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            if (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText(),
               event.modifierFlags.intersection([.shift, .option, .control]).isEmpty {
                submit(); return
            }
            super.keyDown(with: event)
        }

        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            onLiveTextChange?()
        }

        override func unmarkText() {
            super.unmarkText()
            onCompositionEnded?()
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AIConversationInput
        private var lastReported: Bool?
        init(_ parent: AIConversationInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            apply(view)
        }
        func compositionEnded(_ view: NSTextView) { apply(view) }
        func reportLiveEmptiness(_ view: NSTextView) {
            let empty = view.string.isEmpty
            guard lastReported != empty else { return }
            lastReported = empty
            parent.onLiveTextIsEmptyChange(empty)
        }
        /// 视图更新期间清空/换稿不能当场发布状态，等本轮结束再读 storage。
        func reportAfterViewUpdate(_ view: NSTextView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.reportLiveEmptiness(view)
            }
        }
        private func apply(_ view: NSTextView) {
            parent.text = view.string
            reportLiveEmptiness(view)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let input = Input(frame: NSRect(x: 0, y: 0, width: 300, height: 64))
        input.minSize = NSSize(width: 0, height: 64)
        input.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        input.isRichText = false; input.drawsBackground = false
        input.allowsUndo = true
        input.font = .systemFont(ofSize: 14); input.textColor = .labelColor
        input.textContainerInset = NSSize(width: 2, height: 6)
        input.isVerticallyResizable = true; input.isHorizontallyResizable = false
        input.autoresizingMask = [.width]; input.textContainer?.widthTracksTextView = true
        input.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        input.delegate = context.coordinator; input.setAccessibilityLabel("输入消息")
        input.onLiveTextChange = { [weak input, weak coordinator = context.coordinator] in
            guard let input, let coordinator else { return }
            coordinator.reportLiveEmptiness(input)
        }
        input.onCompositionEnded = { [weak input, weak coordinator = context.coordinator] in
            guard let input, let coordinator else { return }
            coordinator.compositionEnded(input)
        }
        scroll.documentView = input
        context.coordinator.reportAfterViewUpdate(input)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let input = scroll.documentView as? Input else { return }
        input.submit = submit
        if input.string != text, !input.hasMarkedText() {
            input.string = text
            context.coordinator.reportAfterViewUpdate(input)
        }
    }
}
