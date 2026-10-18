import SwiftUI

enum InspectorRenderAnchor: Hashable {
    case header, back, completion, completionInk, divider, schedule, scheduleViewport
    /// 顶栏次要日期（有截止日期才渲染）。
    case deadlineLabel
    /// 顶栏下沿的子任务进度条（有子任务才渲染）。
    case progressBar
    /// 安排日期面板里的「截止日期」入口行（详情宿主专属；测试用它点开截止面板）。
    case deadlineRow
    case reminder, repeatControl, priority, breadcrumb, title, emptyContent
    case document, childSection, addChild
    /// 正文后、子任务前的两行属性：附件列表 / 标签 chips（TI2-02/TI2-03）。
    case attachments, tagStrip
    case footerList, footerFormatting, footerMore, footerTag, footerMerge, footerComment
    /// 评论出口的条数角标（有评论才渲染）。
    case commentBadge
    case moreMenu, focusMenuRow, parentMenuRow, parentPicker, duplicateMenuRow, tagsMenuRow, tagPicker, activityMenuRow
    case focusPomodoro, focusStopwatch, focusEstimate
}
struct InspectorFramesKey: PreferenceKey {
    static let defaultValue: [InspectorRenderAnchor: CGRect] = [:]
    static func reduce(value: inout [InspectorRenderAnchor: CGRect],
                       nextValue: () -> [InspectorRenderAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
extension View {
    @ViewBuilder
    func inspectorRenderAnchor(_ anchor: InspectorRenderAnchor) -> some View {
        #if DEBUG
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: InspectorFramesKey.self,
                    value: [anchor: geometry.frame(in: .named("inspector-render"))])
            }
            .allowsHitTesting(false)
        }
        #else
        self
        #endif
    }
}
