import CoreGraphics
import Foundation

/// Shared presentation values. Content-specific widths remain named by purpose.
enum PopupMetrics {
    static let cornerRadius: CGFloat = 12
    static let screenInset: CGFloat = 8
    static let controlGap: CGFloat = 4
    static let scheduleGap: CGFloat = 6
    static let submenuGap: CGFloat = 6
    static let contentInset: CGFloat = 12
    static let actionSpacing: CGFloat = 12
    static let compactButtonHeight: CGFloat = 26
    static let buttonCornerRadius: CGFloat = 6
    /// 表单弹框的内边距（标题栏与内容区共用）。
    /// 原 24 在 400pt 宽弹框里四周留白 96pt（占 24%），内容显得空。
    /// 收到 18 后留白降到 14%，正文可用宽度多 12pt。
    static let formInset: CGFloat = 18
    static let formFooterInset: CGFloat = 16
    static let submenuIntent: TimeInterval = 0.22
    /// 菜单宽度的默认值（含图标列 + 较长词条 + 子菜单箭头）。
    static let menuWidth: CGFloat = 224
    /// 只有两三个短词条的菜单（如「更多属性」的提醒/重复）。
    /// 实测内容宽 76pt；用 224 会空出 148pt，肉眼一眼看得出。
    static let menuWidthTight: CGFloat = 132
    /// 清单选择这类「图标 + 短名称 + 勾」的菜单。实测 4 项宽 136pt。
    static let menuWidthCompact: CGFloat = 160
    /// 显示状态（有内容时显示 / 显示 / 隐藏）一类短菜单：160 会把长项截成
    /// 「有内…显示」，176 刚好放下且比 224 明显收窄（滴答实测 ≈160–190）。
    static let menuWidthNarrow = priorityMenuWidth
    /// 全站菜单行共用行高。原按滴答右键菜单实测 34（图标 20 + 上下留白）取值，
    /// 现与摘要弹层口径统一为 40，整站菜单疏密一致。
    /// 菜单行高。40 配 14pt 字（比例 2.86）在 6 项菜单上会撑到 322pt，
    /// 占 764pt 窗口的 42%，比滴答桌面版明显偏大；30 配 14pt 字（比例 2.14）
    /// 降到 242pt，点击区仍远高于 macOS HIG 的 22pt 下限。
    static let menuRowHeight: CGFloat = 30
    /// 菜单行图标边长。跟着行高一起收：行高 40 时图标约 17，
    /// 行高 30 后同步降到 15，保持图标与文字视觉平衡。
    static let menuIconSize: CGFloat = 15
    static let menuInset: CGFloat = 6
    /// 菜单最大高度。行高从 40 降到 30 后，384 能放 12 行；
    /// 任务右键菜单常有 18~22 项，频繁触发滚动。放到 480 能容 16 行，
    /// 仍不超过 764pt 窗口的 63%，不会盖满屏幕。
    static let menuMaximumHeight: CGFloat = 480

    /// 短菜单（任务类型 / 时间快捷项）：只放 2~3 个词条。
    ///
    /// 原先是 176，但实测三项菜单的内容只有 108pt、右侧空 68pt。176 那个值
    /// 其实是被**优先级菜单**拖着走的（「优先级」+ 四个选项 + 旗子），
    /// 一个常量背两种用途。现在拆开：短菜单 144，优先级用 `priorityMenuWidth`。
    static let taskMenuWidth: CGFloat = 144
    /// 优先级菜单：标题 + 无/低/中/高 + 旗子，比短菜单宽一档。
    static let priorityMenuWidth: CGFloat = 176
    /// 「⋯ 更多操作」菜单：实测内容最右墨迹 152pt，208 空出 56pt 显得太宽；
    /// 收到 176，保留约 24pt 右侧余量，且仍容得下「开始专注」行尾箭头。
    static let taskActionsWidth = priorityMenuWidth
    static let noteInfoWidth: CGFloat = 220
    /// 标签选择器。实测真实结构（输入行 + 列表行 + 底部两个按钮）自然宽 127pt，
    /// 原 264 空出 137pt。底部按钮是 `maxWidth: .infinity` 的并排布局，
    /// 收得太窄按钮文字会挤，184 给每个按钮约 74pt。
    static let tagPickerWidth: CGFloat = 184
    /// 「移动到清单」子菜单（图标 + 清单名 + 勾，含搜索行）。实测自然宽 132pt。
    /// 与 `menuWidth` 分开：那个是「图标 + 长词条 + 子菜单箭头」的口径。
    static let listPickerWidth: CGFloat = 172
    static let parentPickerWidth: CGFloat = 280
    static let focusEstimateWidth = parentPickerWidth
    static let relationPickerWidth: CGFloat = 320
    /// 快速添加属性弹框（输入框右侧 chevron 打开的那个）。
    ///
    /// 原 270：内容只有「优先级 + 5 行短菜单」，最长一行
    /// 「输入框设置：简洁」自然宽 163pt，270 里剩下大量留白。
    /// 它又是常驻在输入框右下方的浮层，宽一寸就多压一寸正文，
    /// 所以按用户要求收窄 30%：270 × 0.7 = 189，**取整到 4pt 网格的 188**。
    ///
    /// 188 的余量核算（实测，非估算）：最长行自然宽 163.00，面板可用宽 = 188 − 24
    /// = 164.00，**余 1.00pt**；配合 `propertyRow` 的图标-文字间距 12→10 才放得下
    /// （间距 12 时需要 191，188 会截断）。截断临界点是 187，再往下就出省略号。
    static let quickAddPropertiesWidth: CGFloat = 188
    /// 排序/筛选选项菜单。滴答 `TTSortOptionPickerViewController` 实测 192；
    /// 本地原为裸字面量 264，实测内容只到 188、右侧空 76pt。
    static let sortOptionWidth: CGFloat = 208
    static let syncStatusWidth: CGFloat = 340
    /// Focus 的三个小浮层（原先都是裸字面量）。
    static let rhythmPopoverWidth: CGFloat = 360
    /// 每日目标：内容只有「标题 + 一行 Stepper」，实测 119pt 就够。
    /// 原 190 右侧空 71pt，收到 160 留 40 余量。
    static let goalPopoverWidth = menuWidthCompact
    static let symbolPickerWidth: CGFloat = 240
    /// Sheet 类宽度（原先都是裸字面量，散在各视图里）。
    static let settingsSheetWidth = relationPickerWidth
    /// 清单动态：列表型 Sheet，行内 `maxWidth: .infinity` 会撑满，
    /// 再窄任务名与时间就挤。原 360 收到 300（实测墨迹贴边 = 已到紧的下限）。
    static let activitySheetWidth: CGFloat = 300
    static let templateNoteWidth: CGFloat = 380
    /// AI 面板「历史对话」弹层。内容行是 `maxWidth: .infinity` 的列表，
    /// 无法按内容自然宽推导（见 `AnchoredPropertyPanel.width` 的说明），只能给口径。
    ///
    /// 实测 248/250/252 三档行高完全一致（长标题 54、短标题 39），故取网格值 248。
    /// 注意 `AIConversationRecord.title` 硬上限 `prefix(28)`，28 个汉字单行需 334pt，
    /// 而可用宽只有约 190pt，**任何宽度下标题都必然 2 行**，宽度不影响行数。
    static let aiChatHistoryWidth: CGFloat = 248
    /// AI 面板「引用资料」弹层。
    ///
    /// 原挂载点写裸字面量 `340`，内容 `AIReferencePicker` 又各自写了一遍
    /// `.frame(width: 340, height: 390)`——典型双声明。现统一走本常量。
    static let aiReferencePickerWidth: CGFloat = 340

    // MARK: 编辑器内联面板（NSPanel / 覆盖层，宽度由行内槽位算出或固定口径）

    /// 链接悬停菜单：三个图标按钮 + 内边距。
    ///
    /// 实测三按钮 56+54+44 = 154，加 2×2 间距 + 3×2 内边距 = **164pt** 即可，
    /// 原 226 余 62pt。取 224（4pt 网格）后仍余 60pt，图标按钮不受挤压。
    static let linkHoverMenuWidth: CGFloat = 224
    /// `#` / `~` 候选面板：与 Slash compact 同宽。
    static let completionWidth = menuWidthCompact
    /// 拖拽落点选择卡。
    static let moveTargetWidth: CGFloat = 230
    /// 快速添加属性子面板（清单 / 显示模式）。
    ///
    /// 原 250：主面板收窄后，两个子面板比它本身还宽 61pt，视觉上比父面板
    /// 宽出一圈，用户第二轮反馈"太宽了"。现收到与父面板同宽 188。
    ///
    /// **为什么停在 188、不再往网格下取 184**：显示模式子面板的副标题
    /// `QuickAddDisplayMode.detail` 是**无 `lineLimit` 的可折行文本**，实测折行
    /// 阈值在 **187.5pt**：187.0 及以下 fit=117（折成两行），187.5 及以上 fit=116。
    /// 188 距阈值仅 0.5pt——任何字体差异、本地化或无障碍字号调整都可能翻转。
    /// 若将来必须再窄，正确做法是同时缩短 `detail` 文案，而不是只改这个数。
    ///
    /// 清单选择子面板无此风险：长清单名本来就 `lineLimit(1)` 截断。
    static let quickAddChildWidth: CGFloat = 188
    /// 标签颜色弹层（右键标签 → 颜色）。
    ///
    /// 原挂载点是裸字面量 220，但内容自然宽 **246**（7×22 色块 + 6×10 间距
    /// + 2×16 内边距），**内容被裁掉 26pt**——最右一列色块看不全。
    /// 这是"面板比内容窄"的反向 bug，和快速添加那种"面板比内容宽"是同一类
    /// 双声明问题的两个方向。取 246（内容自然宽），由
    /// `PopupWidthContractTests` 的量测兜住。
    ///
    /// ⚠️ **这个值不能上 4pt 网格**。实测内容自然宽 `246.0000`，余量精确为 **0**；
    /// 渲染验证 246 正常、245 与 244 都 CLIPPED。算式精确吻合：
    /// 色板 7×22 + 6×10 = 214，加内边距 2×16 = **246**。
    /// 若将来必须让它落在网格上，正确做法是把色板本身改小
    /// （色块 22→21 或间距 10→9），而不是只改这个外层常量。
    static let tagColorPickerWidth: CGFloat = 246
    /// Countdown 编辑器各区（色板 / 样式 / 显示）。
    static let countdownPaletteWidth = symbolPickerWidth
    /// 350 = 左右内边距各 20 + 预览卡 310（与真卡片同宽，1:1）。
    static let countdownPreviewWidth: CGFloat = 350
    static let countdownStyleWidth = rhythmPopoverWidth
    static let countdownDisplayWidth = templateNoteWidth
    /// Focus 记录详情（表单型 Sheet）。
    static let focusRecordWidth: CGFloat = 440

    /// 判读阈值：弹层内容右缘到面板右边界还剩多少，才算"偏宽"。
    static let popupSlackWide: CGFloat = 60
    static let popupSlackTight: CGFloat = 4
}
