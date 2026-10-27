import SwiftUI

/// 引导任务详情里的「开始使用」行动条（对齐滴答预设任务的 action cell）。
struct WelcomeGuideActionView: View {
    let action: WelcomeGuide.Action
    let perform: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12, weight: .semibold))
                Text("开始使用")
                    .font(WFType.body.weight(.medium))
                Spacer(minLength: 8)
                Text(action.title)
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(WFColors.accent)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(WFColors.accentFaint.opacity(hovering ? 1 : 0.72),
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("开始使用：\(action.title)")
        .accessibilityLabel("开始使用：\(action.title)")
    }
}
