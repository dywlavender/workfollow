import SwiftUI

/// 底栏评论出口的条数角标（TI2-09 的一部分）。
///
/// 滴答的评论头 `TTTaskDetailCommentHeaderView` 带 `countLabel`；本地此前只有一个
/// 无信息的 💬 图标，有没有评论、有几条都看不出来。角标只读 store，不参与点击。
struct TaskCommentCountBadge: View {
    @ObservedObject var store: TaskCommentStore
    let taskID: UUID

    var body: some View {
        let count = store.count(for: taskID)
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 3)
                .frame(minWidth: 14, minHeight: 14)
                .background(WFColors.accent, in: Capsule())
                .offset(x: 5, y: -2)
                .allowsHitTesting(false)
                .inspectorRenderAnchor(.commentBadge)
                .accessibilityLabel("评论 \(count) 条")
        }
    }
}
