import Foundation

/// 笔记页的列分配结果。做成纯函数是为了让 1430 / 1140 两档边界可测。
struct NotesColumnLayout: Equatable {
    var wide: Bool
    var paneWidth: CGFloat
    var maximumPaneWidth: CGFloat
    var showList: Bool
    var aiVisible: Bool
    var aiWidth: CGFloat
}

enum NotesColumnLayoutEngine {
    /// - Parameters:
    ///   - contentWidth: 笔记页实际可用宽度（已扣除图标栏，以及壳层决定保留的文件夹列）。
    ///   - storedPaneWidth: 用户保存的列表宽度。
    ///   - storedAIWidth: 用户保存的 AI 栏宽度。
    ///   - aiOpen: 用户是否打开了 AI 助手。
    ///   - detailOnly: 窄栏下是否只看正文（列表/正文单栏切换）。
    static func layout(contentWidth: CGFloat, storedPaneWidth: CGFloat, storedAIWidth: CGFloat,
                       aiOpen: Bool, detailOnly: Bool, noteExists: Bool, trash: Bool) -> NotesColumnLayout {
        let maximum = max(WFMetrics.listMinimum,
                          min(WFMetrics.listMaximum,
                              contentWidth - WFMetrics.inspectorMinimum - WFMetrics.divider))
        let paneWidth = min(max(storedPaneWidth, WFMetrics.listMinimum), maximum)
        let wantsAI = aiOpen && noteExists && !trash
        let wide = contentWidth >= WFMetrics.splitMinimum
        let aiVisible = wantsAI && (wide || detailOnly)
        let editorMinimum = wide ? NoteAIPaneMetrics.editorMinimumWidth
                                 : NoteAIPaneMetrics.compactEditorMinimumWidth
        // AI 打开时，列表只在与正文、AI 最小宽度都放得下时保留；
        // 放不下就让列表让位，正文和 AI 保持舒适宽度（原来窗口不足时的行为）。
        let listWithAI = paneWidth + editorMinimum + NoteAIPaneMetrics.minimumWidth
            + WFMetrics.divider * 2
        let showList = !aiVisible || contentWidth >= listWithAI
        let desired = min(max(storedAIWidth, NoteAIPaneMetrics.minimumWidth),
                          NoteAIPaneMetrics.maximumWidth)
        var aiWidth = desired
        if aiVisible {
            let base = contentWidth - (showList ? paneWidth + WFMetrics.divider : 0)
            aiWidth = min(desired, max(NoteAIPaneMetrics.minimumWidth,
                                       base - editorMinimum - WFMetrics.divider))
        }
        return NotesColumnLayout(wide: wide, paneWidth: paneWidth, maximumPaneWidth: maximum,
                                 showList: showList, aiVisible: aiVisible, aiWidth: aiWidth)
    }
}

/// 文件夹列显隐与五栏/四栏宽度的换算。
enum NotesFolderColumnMetrics {
    static func clampedListWidth(_ value: CGFloat) -> CGFloat {
        min(max(value, WFMetrics.listMinimum), WFMetrics.listMaximum)
    }

    static func clampedAIWidth(_ value: CGFloat) -> CGFloat {
        min(max(value, NoteAIPaneMetrics.minimumWidth), NoteAIPaneMetrics.maximumWidth)
    }

    /// 五栏（图标栏 + 文件夹 + 列表 + 正文 + AI）并排所需的窗口宽度。
    static func requiredWindowWidth(listWidth: CGFloat, aiWidth: CGFloat) -> CGFloat {
        WFMetrics.railWidth + WFMetrics.navigationWidth
            + clampedListWidth(listWidth)
            + NoteAIPaneMetrics.editorMinimumWidth
            + clampedAIWidth(aiWidth)
            + WFMetrics.divider * 2
    }

    /// 收起文件夹后，列表 + 正文 + AI（AI 用最小宽度）并排所需的窗口宽度。
    /// 低于这个宽度时列表本来就要让位，再收文件夹没有收益，保留文件夹作为导航。
    static func requiredWindowWidthForList(listWidth: CGFloat) -> CGFloat {
        WFMetrics.railWidth + clampedListWidth(listWidth)
            + NoteAIPaneMetrics.editorMinimumWidth
            + NoteAIPaneMetrics.minimumWidth
            + WFMetrics.divider * 2
    }
}
