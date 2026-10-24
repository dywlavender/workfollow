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
    static let formInset: CGFloat = 24
    static let formFooterInset: CGFloat = 16
    static let submenuIntent: TimeInterval = 0.22
    static let menuWidth: CGFloat = 224
    static let menuRowHeight: CGFloat = 32
    static let menuInset: CGFloat = 6
    static let menuMaximumHeight: CGFloat = 384

    /// 短菜单（任务类型 / 时间快捷项）：只放 2~3 个词条。
    ///
    /// 原先是 176，但实测三项菜单的内容只有 108pt、右侧空 68pt。176 那个值
    /// 其实是被**优先级菜单**拖着走的（「优先级」+ 四个选项 + 旗子），
    /// 一个常量背两种用途。现在拆开：短菜单 144，优先级用 `priorityMenuWidth`。
    static let taskMenuWidth: CGFloat = 144
    /// 优先级菜单：标题 + 无/低/中/高 + 旗子，比短菜单宽一档。
    static let priorityMenuWidth: CGFloat = 176
    static let taskActionsWidth: CGFloat = 208
    static let noteInfoWidth: CGFloat = 220
    static let tagPickerWidth: CGFloat = 264
    static let parentPickerWidth: CGFloat = 280
    static let focusEstimateWidth: CGFloat = 280
    static let relationPickerWidth: CGFloat = 320
    static let quickAddPropertiesWidth: CGFloat = 270
    /// 排序/筛选选项菜单。滴答 `TTSortOptionPickerViewController` 实测 192；
    /// 本地原为裸字面量 264，实测内容只到 188、右侧空 76pt。
    static let sortOptionWidth: CGFloat = 208
    static let syncStatusWidth: CGFloat = 340
    /// Focus 的三个小浮层（原先都是裸字面量）。
    static let rhythmPopoverWidth: CGFloat = 360
    /// 每日目标：内容只有「标题 + 一行 Stepper」，实测 119pt 就够。
    /// 原 190 右侧空 71pt，收到 160 留 40 余量。
    static let goalPopoverWidth: CGFloat = 160
    static let symbolPickerWidth: CGFloat = 240
    /// Sheet 类宽度（原先都是裸字面量，散在各视图里）。
    static let settingsSheetWidth: CGFloat = 320
    /// 清单动态：列表型 Sheet，行内 `maxWidth: .infinity` 会撑满，
    /// 再窄任务名与时间就挤。原 360 收到 300（实测墨迹贴边 = 已到紧的下限）。
    static let activitySheetWidth: CGFloat = 300
    static let templateNoteWidth: CGFloat = 380

    // MARK: 编辑器内联面板（NSPanel / 覆盖层，宽度由行内槽位算出或固定口径）

    /// 链接悬停菜单：三个图标按钮 + 内边距。
    static let linkHoverMenuWidth: CGFloat = 226
    /// `#` / `~` 候选面板：与 Slash compact 同宽。
    static let completionWidth: CGFloat = 160
    /// 拖拽落点选择卡。
    static let moveTargetWidth: CGFloat = 230
    /// 快速添加属性子面板（清单 / 显示模式）。
    static let quickAddChildWidth: CGFloat = 250
    /// Countdown 编辑器各区（色板 / 样式 / 显示）。
    static let countdownPaletteWidth: CGFloat = 240
    /// 350 = 左右内边距各 20 + 预览卡 310（与真卡片同宽，1:1）。
    static let countdownPreviewWidth: CGFloat = 350
    static let countdownStyleWidth: CGFloat = 360
    static let countdownDisplayWidth: CGFloat = 380
    /// Focus 记录详情（表单型 Sheet）。
    static let focusRecordWidth: CGFloat = 440

    /// 判读阈值：弹层内容右缘到面板右边界还剩多少，才算"偏宽"。
    static let popupSlackWide: CGFloat = 60
    static let popupSlackTight: CGFloat = 4
}
