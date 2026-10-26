import Foundation

/// Flutter TaskListMetrics: list-specific geometry, independent of global controls.
enum TaskListMetrics {
    // MARK: 分组头

    /// 日期/优先级这类系统分组前的留白。滴答实测：分组行 42 = 18 留白 + 24 内容。
    static let groupTopGap: CGFloat = 18
    /// 日期/优先级分组头的内容高度（不含上方留白）。
    static let dateGroupHeaderHeight: CGFloat = 24
    /// 自定义小节头。滴答 `TTTaskListSectionCell.nib` 整枚 626×34，行内不再加留白。
    static let sectionHeaderHeight: CGFloat = 34
    static let groupChevronSize: CGFloat = 11
    /// 分组头 `+` / `…` 的命中格。滴答这两枚都是 24×24（`TTTaskListSectionCell.nib`
    /// 里 `addButton` / `moreButton` 的 frame）。
    static let groupActionHit: CGFloat = 24

    // MARK: 快速添加

    /// 滴答输入条视觉高度约 33–34（AX 里真实输入区 28，圆角底更高一档）。
    static let quickAddHeight: CGFloat = 34
    static let quickAddRadius: CGFloat = 10
    /// 列表页头右侧的排序/更多按钮，滴答实测 30×30。
    static let headerActionSize: CGFloat = 30

    // MARK: 任务行

    /// 勾选框外边距：行背景从行左 16 开始，勾选框在 31，标题在 52。
    static let rowHorizontalPadding: CGFloat = 16
    /// 勾选框左侧的展开/拖拽槽。自定义小节的 15pt 与分组箭头 15pt 对齐。
    static let leadingGutter: CGFloat = 15
    static let checkboxSize: CGFloat = 19
    static let checkboxTitleGap: CGFloat = 2
    /// 滴答实测：基础行 40；每多一行内容（预览或标签）加 21。
    static let baseRowHeight: CGFloat = 40
    /// 行内上下留白：标题/勾选框都从行顶 +10 开始（40 = 19 勾选 + 10 + 11）。
    static let rowVerticalPadding: CGFloat = 10
    static let previewRowIncrement: CGFloat = 21
    static let tagRowIncrement: CGFloat = 21
    static let hierarchyIndent: CGFloat = 21

    static var checkboxLeading: CGFloat { rowHorizontalPadding + leadingGutter }
    static var titleLeading: CGFloat {
        checkboxLeading + checkboxSize + checkboxTitleGap
    }
    /// 行分割线从标题起点开始（滴答实测，不再从勾选框左侧起）。
    static var dividerLeading: CGFloat { titleLeading }
    static func dividerLeading(completed: Bool, depth: Int) -> CGFloat {
        titleLeading + CGFloat(depth) * hierarchyIndent
    }

    /// 「倒数纪念日」小节里那行的高度。只有图标 + 名称 + 右侧标签，没有第二行。
    static let countdownRowHeight: CGFloat = 36
    static let dragMarkerHeight: CGFloat = 1
    static let dragPreviewMaxWidth: CGFloat = 220

    /// 任务行里最多平铺几个标签胶囊（其余折成「+N」），避免行被撑爆。
    static let maxVisibleTags = 3
    static let tagRowSpacing: CGFloat = 2
    static let tagChipHeight: CGFloat = 20

    /// 批量动作条高度（列表区多选时出现）。
    static let bulkBarHeight: CGFloat = 36

    /// 已完成组每页条数（滴答 `countToShowOfCompleted` + `didClickLoadMore`：
    /// 已完成是"看历史"，不该和待办一样一次性全铺出来）。
    static let completedPageSize = 30
    /// 「显示更多」行高。比任务行矮：它只是一枚文字按钮 + 转圈位。
    static let loadMoreRowHeight: CGFloat = 34

    /// 分组头内容高度；自定义小节 34，日期/优先级这类系统分组 24。
    static func groupHeaderHeight(isSection: Bool) -> CGFloat {
        isSection ? sectionHeaderHeight : dateGroupHeaderHeight
    }

    /// 分组头上方留白；小节头的 34 已经自带呼吸感，不再叠 18。
    static func headerTopGap(isSection: Bool) -> CGFloat {
        isSection ? 0 : groupTopGap
    }

    /// 任务行高度：滴答实测 40 / 61 / 82（多预览行或多标签行各 21）。
    /// 标签单独出现时 62：20pt 胶囊 + 2pt 间距放不进 61。
    /// 行高必须由这里给出确定值——`NSOutlineView` 的 `heightOfRowByItem` 不能反查
    /// SwiftUI 的 fittingSize（cell 高度与内容高度会互相依赖）。
    static func taskRowHeight(hasPreview: Bool, hasTags: Bool) -> CGFloat {
        if hasPreview {
            return 61 + (hasTags ? tagRowIncrement : 0)
        }
        return hasTags ? 62 : baseRowHeight
    }
}
