import SwiftUI

enum InspectorRenderAnchor: Hashable {
    case header, back, completion, completionInk, divider, schedule, scheduleViewport
    /// 顶栏「设置日期」chip 本体（日程区里还并列着截止日期入口，点击要精确到 chip）。
    case scheduleChip
    /// 顶栏次要日期（任务已有截止日期时才渲染）。
    case deadlineLabel
    case reminder, repeatControl, priority, breadcrumb, title, emptyContent
    case document, childSection, addChild
    /// 子任务折叠提示「已折叠 N 项」（有折叠才渲染）。
    case collapsedCount
    /// 正文后、子任务前的两行属性：附件列表 / 标签 chips（TI2-02/TI2-03）。
    case attachments, tagStrip
    case footerList, footerFormatting, footerMore, footerTag, footerMerge, footerComment
    /// 评论出口的条数角标（有评论才渲染）。
    case commentBadge
    /// 内联评论区（TI2-09）。
    case commentSection
    /// 任务／笔记顶栏的公共「打开便签」入口。
    case detach
    /// 顶栏「笔记信息」（TI2-15）。
    case noteInfo
    /// 顶栏「任务类型」（TI2-05b）。
    case kind
    case moreMenu, focusMenuRow, parentMenuRow, parentPicker, duplicateMenuRow, tagsMenuRow, tagPicker, activityMenuRow
    case noteConversionMenuRow
    case aiBreakdownMenuRow
    case agentCopyInstructions, agentCopyCommand
    case focusPomodoro, focusStopwatch, focusEstimate, focusEstimateClear
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
