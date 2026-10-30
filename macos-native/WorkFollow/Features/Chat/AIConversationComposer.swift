import SwiftUI

/// All conversation surfaces share the complete composer. The caller owns its scene and request.
struct AIConversationComposer<Model: AIConversationComposing>: View {
    @ObservedObject var model: Model
    let placeholder: String
    let submit: () -> Void
    var compact = false
    var identifierPrefix = "ai.chat"
    var instanceID: UUID? = nil
    @State private var inputIsLiveEmpty = true

    private var attachments: AIAttachmentDraft { model.attachments }
    private var canSubmit: Bool { model.canSend && !model.isRunning && !attachments.isImporting }
    private var actionID: String { identifierPrefix + ".send" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AIAttachmentStrip(items: attachments.items, remove: attachments.remove)
            AIAttachmentDraftStatus(draft: attachments)
            HStack(alignment: .bottom, spacing: 12) {
                Button { attachments.choose() } label: {
                    Image(systemName: "paperclip").font(.system(size: 16)).frame(width: 26, height: 32)
                }.buttonStyle(.plain).disabled(attachments.isImporting)
                    .accessibilityLabel("添加图片或文件").hoverTip("添加图片或文件")
                    .workflowActionAnchor(identifierPrefix + ".attach")
                AIConversationInput(text: $model.input, submit: send,
                    receiveFiles: { attachments.add(files: $0) },
                    receiveImage: { attachments.add(image: $0) },
                    onLiveTextIsEmptyChange: { inputIsLiveEmpty = $0 })
                    .frame(height: compact ? 48 : 72)
                    .accessibilityIdentifier(identifierPrefix + ".input")
                    .overlay(alignment: .topLeading) {
                        if model.input.isEmpty && inputIsLiveEmpty {
                            Text(placeholder).font(WFType.body).foregroundStyle(WFColors.tertiaryText)
                                .padding(.top, 6).padding(.leading, 7).allowsHitTesting(false)
                                .livePlaceholderProbe(identifierPrefix + ".placeholder")
                        }
                    }
                Button {
                    if model.isRunning { model.stop() } else { send() }
                } label: {
                    Image(systemName: model.isRunning ? "stop.fill" : "arrow.up")
                        .font(.system(size: compact ? 13 : 15, weight: .semibold))
                        .frame(width: compact ? 28 : 32, height: compact ? 28 : 32)
                }
                .buttonStyle(.borderedProminent).clipShape(Circle())
                .disabled(!model.isRunning && !canSubmit)
                .accessibilityLabel(model.isRunning ? "停止生成" : "发送消息")
                .accessibilityIdentifier(actionID).workflowActionAnchor(actionID)
                .workflowActionAnchor(instanceID.map { actionID + "." + $0.uuidString } ?? actionID)
            }
        }
        .padding(12)
        .background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: compact ? 12 : 16))
        .overlay(RoundedRectangle(cornerRadius: compact ? 12 : 16).stroke(WFColors.overlayBorder, lineWidth: 1))
        .workflowActionAnchor(identifierPrefix + ".composer")
    }

    private func send() { if canSubmit { submit() } }
}
