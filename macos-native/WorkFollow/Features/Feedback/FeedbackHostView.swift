import SwiftUI

/// 结果 HUD 的唯一绘制处，由 RootShellView 作为底部悬浮层挂载一次。
/// 当前条目、停留时长与竞争仲裁都在 FeedbackCenter；这里只负责外观与过渡。
struct FeedbackHostView: View {
    @ObservedObject var center: FeedbackCenter

    var body: some View {
        ZStack {
            if let presentation = center.presentation {
                FeedbackToastView(event: presentation.event, onAction: { center.undo() }, onDestination: { center.openDestination() })
                    .id(presentation.id)
                    .feedbackHUDRenderProbe()
                    // 打勾的安静动效：短淡入 + 自底部轻移，无弹簧。
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, WFSpace.lg)
            }
        }
        // 只占卡片大小：透明的横向空间不能拦截底栏按钮的点击。
        .animation(.easeOut(duration: 0.16), value: center.presentation?.id)
    }
}

#if DEBUG
/// 渲染回归用：HUD 胶囊在宿主坐标空间里的 frame；发布构建不包含。
struct FeedbackHUDRenderFrames: PreferenceKey {
    static let coordinateSpace = "feedback-hud-layout"
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

private extension View {
    func feedbackHUDRenderProbe() -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: FeedbackHUDRenderFrames.self,
                                       value: [geometry.frame(in: .named(FeedbackHUDRenderFrames.coordinateSpace))])
            }
        }
    }
}
#else
private extension View {
    func feedbackHUDRenderProbe() -> some View { self }
}
#endif

/// 深色圆角卡片：`任务已完成    ↶`。
/// 不持有计时器也不持有状态——何时出现、何时离开由宿主决定。
private struct FeedbackToastView: View {
    let event: FeedbackEvent
    let onAction: () -> Void
    let onDestination: () -> Void

    /// 文案上限：超过即截断，短文案不被撑出一条死面。
    private static let messageWidthCap: CGFloat = 360
    private static let dangerColor = Color(nsColor: .systemRed)
    /// 尾部撤销箭头：深色底上用琥珀橙拉开对比，和正文白色区分动作与结果。
    private static let undoColor = Color(red: 1, green: 0.631, blue: 0)
    private static let cornerRadius: CGFloat = 9
    private static let minHeight: CGFloat = 40

    var body: some View {
        // 第一选：按文案自然收缩；放不下时退到定宽截断。
        ViewThatFits(in: .horizontal) {
            card(messageWidthCap: nil).fixedSize(horizontal: true, vertical: false)
            card(messageWidthCap: Self.messageWidthCap)
        }
        .shadow(color: .black.opacity(0.24), radius: 14, y: 5)
        .accessibilityElement(children: .combine)
    }

    private func card(messageWidthCap: CGFloat?) -> some View {
        HStack(spacing: WFSpace.sm) {
            // 失败不可与成功混为一谈：只有失败带图标。
            if event.kind.isFailure {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Self.dangerColor)
            }
            Text(event.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WFColors.tooltipText)
                .lineLimit(1)
                .allowsTightening(true)
                .truncationMode(.tail)
                .frame(maxWidth: messageWidthCap, alignment: .leading)
            if let title = event.destinationTitle {
                Button(title, action: onDestination).buttonStyle(.plain).workflowActionAnchor("feedback.destination").foregroundStyle(WFColors.accent)
            }
            if event.actionTitle != nil {
                Button(action: onAction) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Self.undoColor)
                .hoverTip(event.actionTitle ?? "撤销")
                .accessibilityLabel(event.actionTitle ?? "撤销")
            }
        }
        .padding(.horizontal, WFSpace.lg)
        .padding(.vertical, WFSpace.sm)
        .frame(minHeight: Self.minHeight)
        .background(WFColors.tooltipSurface, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
    }
}
