import AppKit
import SwiftUI

/// Toolbar layouts keep their product order while shared descriptors supply
/// format identity, labels, symbols and active state. Execution remains TextKit-owned.

/// 选中文本时浮现在选区上方的小工具条（迁移自 Flutter DocumentSelectionToolbar）。
/// 笔记 profile 提供“创建任务”，这里追加常用内联样式；Escape 或收起选区即关闭
/// （面板生命周期由 NativeTextView 管理）。
struct DocumentSelectionToolbarView: View {
    let actions: [DocumentSelectionAction]
    let onInvoke: (DocumentSelectionAction) -> Void
    let onFormat: (DocumentFormatCommand) -> Void
    let onLink: () -> Void

    /// 常用内联样式：粗体/斜体/下划线/删除线/高亮/行内代码。
    private var inlineCommands: [DocumentFormatCommand] {
        EditorCommandCatalog.selectionFormatIDs.compactMap(EditorCommandCatalog.format)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(actions) { action in
                Button {
                    onInvoke(action)
                } label: {
                    Label(action.displayTitle, systemImage: "text.badge.plus")
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 6)
                        .frame(height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(WFColors.accent)
                .help(action.title).accessibilityLabel(action.title)
            }
            Divider().frame(height: 16)
            ForEach(inlineCommands, id: \.id) { command in
                Button { onFormat(command) } label: {
                    Image(systemName: command.descriptor.toolbarSymbol)
                        .frame(width: 24, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(WFColors.text)
                .help(command.descriptor.title).accessibilityLabel(command.descriptor.title)
                .editorCommandFrame(command.id, space: "editor-selection-toolbar")
            }
            Divider().frame(height: 16)
            Button { onLink() } label: {
                Image(systemName: "link").frame(width: 24, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(WFColors.text)
            .help("链接").accessibilityLabel("链接")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(WFColors.border))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .coordinateSpace(name: "editor-selection-toolbar")
    }

}

/// 笔记与任务正文共用的浮动格式工具条（迁移自 Flutter DocumentEditorToolbar 的全集）。
/// 标题 H、粗体、高亮、检查项、
/// 无序/有序列表、斜体、下划线、删除线、分割线、插入当前时间（日期/日期时间/时刻）、
/// 链接、行内代码、引用、上传附件。
struct DocumentFormatToolbarView: View {
    /// 观察句柄是为了激活态：选区里当前是什么段落/标记，按钮就亮哪个
    /// （对齐原版 `_ToolButton(selected: _active(attribute))`）。
    @ObservedObject var handle: DocumentEditorHandle
    /// 原版 `DocumentEditorMetrics.toolbarPopoverWidth` = 444。
    var maxWidth: CGFloat = 444
    var attachmentTitle = "上传附件"

    /// 悬停提示与按钮矩形（见 `DocumentToolbarTooltip`）：提示和两个小面板都由工具条
    /// 这一层统一画在**上方**（`ScrollView` 会裁掉越界内容，按钮自己画不出来），
    /// 所以每个按钮要把它自己的矩形报上来。
    @StateObject private var overlay = ToolbarTooltipState()
    /// 当前开着的小面板（标题级别 / 插入时间）。
    @State private var openPicker: DocumentToolbarPicker?
    /// 指针在不在工具条上、在不在面板上——两者都不在就收起面板。
    @State private var toolbarHovered = false
    @State private var pickerHovered = false

    private static let headingCommands = EditorCommandCatalog.headingPickerIDs.compactMap(EditorCommandCatalog.format)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // 按钮顺序、分组竖线与原版 `document_editor_toolbar.dart` 的 Row 一致：
            // H · B · A ｜ 检查项 无序 有序 ｜ 斜体 下划线 删除线 分割线 时间 ｜
            // 链接 代码 引用 ｜ 附件（共 4 条竖线）。
            HStack(spacing: 0) {
                // 「H」不是图标：原版这个按钮就是字母 H（`label: 'H'`），16pt。
                ToolbarButton(title: "标题", active: headingActive, state: overlay,
                              action: { togglePicker(.heading) }) {
                    Text("H").font(.system(size: 16))
                }
                formatButton("format.bold")
                // 「A」底下永远垫一块高亮色（原版 `label: 'A', highlight: true`）。
                ToolbarButton(title: highlightCommand.descriptor.formatToolbarTitle,
                              active: highlightCommand.descriptor.isActive(in: handle.style), state: overlay,
                              action: { handle.format(highlightCommand) }) {
                    Text("A")
                        .font(.system(size: 16))
                        .foregroundStyle(WFColors.text)
                        .padding(.horizontal, WFSpace.tight)
                        .background(WFColors.accentSoft, in: RoundedRectangle(cornerRadius: 4))
                }
                .editorCommandFrame(highlightCommand.id, space: DocumentToolbarTooltip.space)
                toolbarDivider
                formatButton("format.checklist")
                formatButton("format.bullet")
                formatButton("format.ordered")
                toolbarDivider
                formatButton("format.italic")
                formatButton("format.underline")
                formatButton("format.strikethrough")
                ToolbarButton(title: "分割线", active: false, state: overlay,
                              action: { handle.insertDivider() }) {
                    Image(systemName: "minus")
                }
                ToolbarButton(title: "插入当前时间", active: openPicker == .time, state: overlay,
                              action: { togglePicker(.time) }) {
                    Image(systemName: "clock")
                }
                toolbarDivider
                ToolbarButton(title: "链接", active: false, state: overlay,
                              action: { handle.editLink() }) {
                    Image(systemName: "link")
                }
                formatButton("format.inlineCode")
                formatButton("format.quote")
                toolbarDivider
                ToolbarButton(title: attachmentTitle, active: false, state: overlay,
                              action: { handle.insertAttachment() }) {
                    Image(systemName: "paperclip")
                }
            }
            .buttonStyle(.plain)
            // 图标 18（原版 `WorkFollowMetrics.toolbarIcon`）；字母标签在内部覆盖成 16。
            .font(.system(size: WFMetrics.icon))
            .padding(.horizontal, WFSpace.sm)   // 原版 `WorkFollowSpacing.toolbarItemGap` = 8
        }
        .frame(maxWidth: maxWidth)
        .frame(height: 38)
        // 工具条本身在原版里就是一个浮层（`showTaskEditorPopover` 的卡面），所以取浮层
        // 底色/描边/阴影，而不是画布色。
        .background(WFColors.overlay, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(WFColors.overlayBorder, lineWidth: 1)
        }
        .shadow(color: WFColors.overlayShadow, radius: 18, y: 6)
        .onHover { inside in
            toolbarHovered = inside
            dismissPickerIfPointerLeft()
        }
        // 提示与面板的坐标基准：都画在 `ScrollView` 之外，才不会被横向滚动裁掉。
        .coordinateSpace(name: DocumentToolbarTooltip.space)
        .overlay(alignment: .topLeading) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    if openPicker == nil { tooltipLayer }
                    pickerLayer(containerWidth: proxy.size.width)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .animation(.easeOut(duration: 0.08), value: overlay.hovered)
        // Register only while a child picker is open; scoped to this toolbar's window.
        .background {
            if openPicker != nil {
                PopupEscapeRouter(depth: 2) { openPicker = nil }
            }
        }
    }

    /// 分组竖线：1 × 17，左右各 4（原版 `divider()`）。
    private var toolbarDivider: some View {
        Rectangle()
            .fill(WFColors.border)
            .frame(width: 1, height: 17)
            .padding(.horizontal, WFSpace.xs)
    }

    /// 提示画在工具条**上方**：卡的中心落在被悬停控件的横中线上，底边离工具条顶 6pt。
    @ViewBuilder
    private var tooltipLayer: some View {
        if let title = overlay.hovered, let frame = overlay.frames[title] {
            ToolbarTooltipCard(title: title)
                .position(x: frame.midX,
                          y: -(DocumentToolbarTooltip.cardHeight / 2 + DocumentToolbarTooltip.gap))
                .transition(.opacity)
        }
    }

    /// 面板画在工具条**上方**：标题贴按钮左缘、时间贴按钮右缘，宽度固定 150/222。
    /// 面板底边与工具条顶之间那 6pt 也算面板的悬停区（"桥"），指针从按钮走到面板
    /// 不会中途落到缝里被收起。
    @ViewBuilder
    private func pickerLayer(containerWidth: CGFloat) -> some View {
        if let picker = openPicker, let frame = overlay.frames[picker.tooltipTitle] {
            let originX = picker.originX(anchor: frame, containerWidth: containerWidth)
            let blockHeight = picker.height + DocumentToolbarTooltip.gap
            VStack(spacing: 0) {
                DocumentToolbarPickerCard(picker: picker,
                                          selectedIndex: picker == .heading ? headingIndex : nil,
                                          onPick: { pick(picker, index: $0) })
                Color.clear.frame(height: DocumentToolbarTooltip.gap)
            }
            .frame(width: picker.width)
            .onHover { inside in
                pickerHovered = inside
                dismissPickerIfPointerLeft()
            }
            .position(x: originX + picker.width / 2, y: -blockHeight / 2)
        }
    }

    /// 当前段落落在标题菜单的哪一项（正文 = 0）。
    private var headingIndex: Int? {
        Self.headingCommands.firstIndex { handle.style.isBlock($0.block) }
    }

    /// 当前段落是不是标题。正文不算——原版判的是 `headingLevel != null`。
    private var headingActive: Bool {
        [DocumentBlockKind.heading(1), .heading(2), .heading(3)]
            .contains { handle.style.isBlock($0) }
    }

    private func togglePicker(_ picker: DocumentToolbarPicker) {
        openPicker = openPicker == picker ? nil : picker
    }

    private func pick(_ picker: DocumentToolbarPicker, index: Int) {
        switch picker {
        case .heading:
            if index < Self.headingCommands.count { handle.format(Self.headingCommands[index]) }
        case .time:
            handle.insertTime(format: DocumentToolbarPicker.timeFormats[index])
        }
        openPicker = nil
    }

    /// 指针既不在工具条上、也不在面板上就收起面板。原版是"点面板外面"收起；这里没有
    /// 覆盖整个窗口的遮罩，所以用指针离开收起（把指针移开即等于离开）。
    private func dismissPickerIfPointerLeft() {
        guard openPicker != nil, !toolbarHovered, !pickerHovered else { return }
        openPicker = nil
    }

    /// 工具条上的一个图标按钮：把激活态、悬停底、尺寸与提示一次装好。
    private var highlightCommand: DocumentFormatCommand {
        EditorCommandCatalog.format("format.highlight")!
    }

    private func formatButton(_ id: String) -> some View {
        let command = EditorCommandCatalog.format(id)
        let descriptor = command?.descriptor
        let active = descriptor?.isActive(in: handle.style) ?? false
        return ToolbarButton(title: descriptor?.formatToolbarTitle ?? id, active: active, state: overlay,
                             action: { if let command { handle.format(command) } }) {
            Image(systemName: descriptor?.toolbarSymbol ?? "textformat")
        }
        .disabled(command == nil)
        .editorCommandFrame(id, space: DocumentToolbarTooltip.space)
    }
}

/// 工具条上的一个按钮：**26 × 28**（原版 `toolbarControlWidth/Height`），激活态取
/// `accentFaint` 底 + 强调色图标，指针悬停取列表行的中性底（原版 InkWell 的
/// `overlayColor`，不是强调色——菜单/工具条是中性表面）。
private struct ToolbarButton<Label: View>: View {
    let title: String
    let active: Bool
    let state: ToolbarTooltipState
    let action: () -> Void
    @ViewBuilder var label: Label

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(active ? WFColors.accent : WFColors.secondaryText)
                .frame(width: 26, height: 28)
                .background(active ? WFColors.accentFaint
                            : hovering ? WFColors.listRowHover : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .toolbarTooltip(title, state: state)
        .accessibilityLabel(title)
    }
}
