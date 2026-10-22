import Foundation

struct TaskWorkspaceLayout {
    let showsInspector: Bool
    let maximumListWidth: CGFloat
    let listWidth: CGFloat

    init(availableWidth: CGFloat, preferredListWidth: CGFloat, wideView: Bool,
         hasSelection: Bool, hasBulkSelection: Bool) {
        // 普通列表始终保留详情列；选择、切换和关闭任务都不改变列表宽度。
        // 看板和时间线在未选任务时使用完整内容区。
        showsInspector = !wideView || hasSelection || hasBulkSelection
        if !showsInspector {
            maximumListWidth = availableWidth
            listWidth = availableWidth
        } else {
            maximumListWidth = max(WFMetrics.listMinimum,
                min(wideView ? availableWidth : WFMetrics.listMaximum,
                    availableWidth - WFMetrics.inspectorMinimum - WFMetrics.divider))
            listWidth = wideView ? maximumListWidth
                : min(max(preferredListWidth, WFMetrics.listMinimum), maximumListWidth)
        }
    }
}
