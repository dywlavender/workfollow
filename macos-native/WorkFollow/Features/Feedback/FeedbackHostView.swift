import SwiftUI

/// 结果 HUD 的唯一绘制处，由 RootShellView 在底部居中挂载一次。
/// 当前条目、停留时长与竞争仲裁都在 FeedbackCenter；这里只负责外观与过渡。
struct FeedbackHostView: View {
    @ObservedObject var center: FeedbackCenter

    var body: some View {
        ZStack {
            if let presentation = center.presentation {
                FeedbackToastView(event: presentation.event, onAction: { center.undo() })
                    .id(presentation.id)
                    // 打勾的安静动效：短淡入 + 自底部轻移，无弹簧。
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, WFSpace.lg)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.16), value: center.presentation?.id)
    }
}

/// 深色胶囊卡片：`任务已完成    ↶`。
/// 不持有计时器也不持有状态——何时出现、何时离开由宿主决定。
private struct FeedbackToastView: View {
    let event: FeedbackEvent
    let onAction: () -> Void

    /// 文案上限：超过即截断，短文案不被撑出一条死面。
    private static let messageWidthCap: CGFloat = 360
    private static let dangerColor = Color(nsColor: .systemRed)

    var body: some View {
        // 第一选：按文案自然收缩；放不下时退到定宽截断。
        ViewThatFits(in: .horizontal) {
            capsule(messageWidthCap: nil).fixedSize(horizontal: true, vertical: false)
            capsule(messageWidthCap: Self.messageWidthCap)
        }
        .shadow(color: .black.opacity(0.16), radius: 9, y: 3)
        .accessibilityElement(children: .combine)
    }

    private func capsule(messageWidthCap: CGFloat?) -> some View {
        HStack(spacing: WFSpace.sm) {
            // 失败不可与成功混为一谈；完成条目带强调色对勾。
            if event.kind.isFailure {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Self.dangerColor)
            } else if event.kind == .completion {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(WFColors.accent)
            }
            Text(event.message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .allowsTightening(true)
                .truncationMode(.tail)
                .frame(maxWidth: messageWidthCap, alignment: .leading)
            if event.actionTitle != nil {
                Button(action: onAction) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(WFColors.secondaryText)
                .help(event.actionTitle ?? "撤销")
                .accessibilityLabel(event.actionTitle ?? "撤销")
            }
        }
        .padding(.horizontal, WFSpace.lg)
        .padding(.vertical, WFSpace.sm)
        .frame(minHeight: 36)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(WFColors.border))
    }
}
