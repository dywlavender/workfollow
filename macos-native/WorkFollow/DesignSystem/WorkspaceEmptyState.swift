import SwiftUI

/// 页面级空态的统一范式（倒数纪念日 / 会议纪要 / 笔记 / 占位目的地）：
/// 目的地符号 + 标题 + 可选说明，全部 `secondaryText` 居中；可选主行动按钮。
/// 任务侧另有插画空态 `TaskEmptyStateView`；AI 对话的「今天想处理什么？」
/// 是对话引导语，不属于本范式（见设计文档空态白名单）。
struct WorkspaceEmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: WFSpace.md) {
            VStack(spacing: WFSpace.md) {
                Image(systemName: symbol).font(.largeTitle)
                Text(title).font(WFType.body)
                if let message {
                    Text(message).font(WFType.supporting)
                }
            }
            .foregroundStyle(WFColors.secondaryText)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .padding(.top, WFSpace.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}