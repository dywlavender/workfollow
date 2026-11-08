import SwiftUI

/// All conversation surfaces share the complete composer. The caller owns its scene and request.
struct AIConversationComposer<Model: AIConversationComposing>: View {
    @ObservedObject var model: Model
    let placeholder: String
    let submit: () -> Void
    var compact = false
    var identifierPrefix = "ai.chat"
    var instanceID: UUID? = nil
    @Environment(\.workfollowBackgroundTheme) private var backgroundTheme
    @Environment(\.workfollowPageCanvasActive) private var pageCanvasActive
    @State private var inputIsLiveEmpty = true

    private var attachments: AIAttachmentDraft { model.attachments }
    private var canSubmit: Bool { model.canSend && !model.isRunning && !attachments.isImporting }
    private var actionID: String { identifierPrefix + ".send" }
    private var themedInput: Bool { pageCanvasActive && backgroundTheme.isThemed }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AIAttachmentStrip(items: attachments.items, remove: attachments.remove)
            AIAttachmentDraftStatus(draft: attachments)
            if let steer = model.pendingSteerText {
                // 引导已排队：本轮回复结束后自动发出。
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 10))
                    Text("已排队：\(steer)").font(WFType.caption).lineLimit(1)
                        .foregroundStyle(WFColors.secondaryText)
                    Spacer()
                    Button { model.cancelSteer() } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    }.buttonStyle(.plain).foregroundStyle(WFColors.secondaryText)
                        .accessibilityLabel("取消排队消息")
                }.padding(8)
                .background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: 8))
            }
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
            if model.isRunning, !model.input.isEmpty {
                Text("生成中：按回车把这句话排入队尾，本轮结束后自动发送")
                    .font(WFType.caption).foregroundStyle(WFColors.tertiaryText)
            }
        }
        .padding(12)
        .background(themedInput ? backgroundTheme.inputFill : WFColors.secondarySurface,
                    in: RoundedRectangle(cornerRadius: compact ? 12 : 16))
        .overlay(RoundedRectangle(cornerRadius: compact ? 12 : 16)
            .stroke(themedInput ? WFColors.border : WFColors.overlayBorder, lineWidth: 1))
        .workflowActionAnchor(identifierPrefix + ".composer")
    }

    private func send() {
        if canSubmit { submit(); return }
        // 生成中按回车 = 引导（steer）：排队的话在本轮结束后自动发送。
        if model.isRunning, !attachments.isImporting,
           !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.queueSteer(model.input)
            model.input = ""
        }
    }
}
