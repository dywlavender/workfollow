import AppKit
import SwiftUI

/// Component metrics from the live TickTick toolbar comparison. Keep hit areas
/// and command order stable; visual glyph size is independent of interaction size.
enum DocumentFormatToolbarMetrics {
    static let iconSize: CGFloat = 14
    static let controlWidth: CGFloat = 26
    static let controlHeight: CGFloat = 28
    static let height: CGFloat = 38
    static let cornerRadius: CGFloat = 8
    static let borderWidth: CGFloat = 0
    static let horizontalInset: CGFloat = 5
    static let dividerInset: CGFloat = 5
    static let highlightFill = Color(nsColor: .systemYellow).opacity(0.45)
    static let shadowRadius: CGFloat = 10
    static let shadowOffset: CGFloat = 3
}

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
        ScrollView(.horizontal, showsIndicators: false) {
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
            if !actions.isEmpty { Divider().frame(height: 16) }
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
        }
        .frame(idealWidth: preferredWidth)
        .frame(height: 34)
        .background(WFColors.overlay, in: RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius).stroke(WFColors.overlayBorder))
        .coordinateSpace(name: "editor-selection-toolbar")
    }

    private var preferredWidth: CGFloat {
        let actionWidth = actions.reduce(CGFloat(0)) { total, action in
            total + (action.displayTitle as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: 13)
            ]).width + 30
        }
        return actionWidth + CGFloat(inlineCommands.count + 1) * 26 + 24
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
    /// Summary embeds this row inside its document card; task/note popovers
    /// retain the existing floating surface.
    var embedded = false

    /// Tooltip coordinates stay outside the horizontal scroller. Picker sizes
    /// use those same real button frames before their existing child host opens.
    @StateObject private var overlay = ToolbarTooltipState()
    /// 当前开着的小面板（标题级别 / 插入时间）。
    @State private var openPicker: DocumentToolbarPicker?
    @State private var pickerSize: CGSize?

    private static let headingCommands = EditorCommandCatalog.headingPickerIDs.compactMap(EditorCommandCatalog.format)

    /// 「更多」溢出菜单（TI2-16b，滴答 `md_more` / `moreButtonClicked:`）：
    /// 窄列里横向滚动之外，再给一条能到达全部格式命令的出口。
    private var overflowMenu: some View {
        BusinessMenu {
            ForEach(DocumentToolbarOverflow.paragraphIDs, id: \.self) { id in
                overflowButton(id)
            }
            Divider()
            ForEach(DocumentToolbarOverflow.inlineIDs, id: \.self) { id in
                overflowButton(id)
            }
            Divider()
            Button("插入当前时间") {
                handle.insertTime(format: DocumentToolbarPicker.timeFormats[0])
            }
            Button("链接") { handle.editLink() }
            Button("上传附件") { handle.insertAttachment() }
            Button("流程图（draw.io）") { handle.insertDiagram() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: DocumentFormatToolbarMetrics.iconSize))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 28, height: DocumentFormatToolbarMetrics.height)
                .contentShape(Rectangle())
        }
        .fixedSize()
        .help("更多格式")
        .accessibilityLabel("更多格式")
    }

    @ViewBuilder
    private func overflowButton(_ id: String) -> some View {
        if let command = EditorCommandCatalog.format(id) {
            Button(command.title) { handle.format(command) }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
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
                .background { pickerPresenter(.heading) }
                .editorPopupTriggerFrame("heading")
                formatButton("format.bold")
                // 「A」底下永远垫一块高亮色（原版 `label: 'A', highlight: true`）。
                ToolbarButton(title: highlightCommand.descriptor.formatToolbarTitle,
                              active: highlightCommand.descriptor.isActive(in: handle.style), state: overlay,
                              action: { handle.format(highlightCommand) }) {
                    Text("A")
                        .font(.system(size: 16))
                        .foregroundStyle(WFColors.text)
                        .padding(.horizontal, WFSpace.tight)
                        .background(DocumentFormatToolbarMetrics.highlightFill, in: RoundedRectangle(cornerRadius: 4))
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
                    SlashMenuGlyph(kind: .divider, color: WFColors.secondaryText)
                }
                ToolbarButton(title: "插入当前时间", active: openPicker == .time, state: overlay,
                              action: { togglePicker(.time) }) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .background { pickerPresenter(.time) }
                .editorPopupTriggerFrame("time")
                toolbarDivider
                ToolbarButton(title: "链接", active: false, state: overlay,
                              action: { handle.editLink() }) {
                    Image(systemName: "link")
                }
                formatButton("format.inlineCode")
                formatButton("format.quote")
                toolbarDivider
                ToolbarButton(title: "流程图（draw.io）", active: false, state: overlay,
                              action: { handle.insertDiagram() }) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                }
            }
            .buttonStyle(.plain)
            // Optical glyph size is separate from the unchanged hit target.
            .font(.system(size: DocumentFormatToolbarMetrics.iconSize, weight: .regular))
            .padding(.horizontal, DocumentFormatToolbarMetrics.horizontalInset)
        }
        // 附件固定在工具条最右：放在横向 ScrollView 之外，窄宽度下不会被裁掉、
        // 也不会被「更多」菜单盖住（原来是 ScrollView 里的最后一项）。
        toolbarDivider
        ToolbarButton(title: attachmentTitle, active: false, state: overlay,
                      action: { handle.insertAttachment() }) {
            Image(systemName: "paperclip")
        }
        .buttonStyle(.plain)
        .font(.system(size: DocumentFormatToolbarMetrics.iconSize, weight: .regular))
        overflowMenu
        }
        .frame(maxWidth: maxWidth)
        .frame(height: DocumentFormatToolbarMetrics.height)
        // 工具条本身在原版里就是一个浮层（`showTaskEditorPopover` 的卡面），所以取浮层
        // 底色/描边/阴影，而不是画布色。
        .background(embedded ? WFColors.content : WFColors.overlay,
                    in: RoundedRectangle(cornerRadius: embedded ? 0 : DocumentFormatToolbarMetrics.cornerRadius))
        .overlay {
            if !embedded {
                RoundedRectangle(cornerRadius: DocumentFormatToolbarMetrics.cornerRadius)
                    .stroke(WFColors.overlayBorder, lineWidth: DocumentFormatToolbarMetrics.borderWidth)
            }
        }
        .shadow(color: embedded ? .clear : WFColors.overlayShadow,
                radius: DocumentFormatToolbarMetrics.shadowRadius,
                y: DocumentFormatToolbarMetrics.shadowOffset)
        // Tooltips stay outside the scroller; picker content has its own child window.
        .coordinateSpace(name: DocumentToolbarTooltip.space)
        .overlay(alignment: .topLeading) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    if openPicker == nil { tooltipLayer(containerWidth: proxy.size.width) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background {
            if let picker = openPicker, let frame = overlay.frames[picker.tooltipTitle] {
                EditorToolbarPopupCapacity(anchor: frame,
                    requestedSize: CGSize(width: picker.width, height: picker.height)) { size in
                    if pickerSize != size { pickerSize = size }
                }
            }
        }
    }

    /// 分组竖线：1 × 17，左右各 4（原版 `divider()`）。
    private var toolbarDivider: some View {
        Rectangle()
            .fill(WFColors.border)
            .frame(width: 1, height: 17)
            .padding(.horizontal, DocumentFormatToolbarMetrics.dividerInset)
    }

    /// 提示画在工具条**上方**：卡的中心落在被悬停控件的横中线上，底边离工具条顶 6pt。
    @ViewBuilder
    private func tooltipLayer(containerWidth: CGFloat) -> some View {
        if let title = overlay.hovered, let frame = overlay.frames[title] {
            let width = min(DocumentToolbarTooltip.width(for: title), containerWidth)
            ToolbarTooltipCard(title: title, maximumWidth: width)
                .frame(width: width)
                .position(x: EditorPopupGeometry.tooltipX(anchor: frame, width: width,
                                                          containerWidth: containerWidth) + width / 2,
                          y: -(DocumentToolbarTooltip.cardHeight / 2 + DocumentToolbarTooltip.gap))
        }
    }

    /// Existing panel ownership preserves the body selection, follows the
    /// window and closes on outside click/Escape instead of pointer departure.
    @ViewBuilder
    private func pickerPresenter(_ picker: DocumentToolbarPicker) -> some View {
        if openPicker == picker, let size = pickerSize, size.width > 0, size.height > 0 {
            AnchoredPropertyPanel(isPresented: Binding(
                get: { openPicker == picker },
                set: { if !$0 { openPicker = nil } }),
                width: size.width,
                horizontalOutset: picker.alignedToEnd
                    ? max(0, size.width - DocumentFormatToolbarMetrics.controlWidth) : 0,
                prefersAbove: true, placement: .verticalInOwner,
                focusPolicy: .preservePresenter,
                title: picker == .heading ? "正文标题格式" : "正文插入时间") {
                DocumentToolbarPickerCard(picker: picker,
                                          selectedIndex: picker == .heading ? headingIndex : nil,
                                          onPick: { pick(picker, index: $0) },
                                          viewportHeight: size.height)
            }
        }
    }

    /// 当前段落落在标题菜单的哪一项（正文 = 0）。
    private var headingIndex: Int? {
        Self.headingCommands.firstIndex { handle.style.isBlock($0.block) }
    }

    /// 当前段落是不是标题。正文不算——原版判的是 `headingLevel != null`。
    private var headingActive: Bool {
        (1...6).map(DocumentBlockKind.heading)
            .contains { handle.style.isBlock($0) }
    }

    private func togglePicker(_ picker: DocumentToolbarPicker) {
        pickerSize = nil
        openPicker = openPicker == picker ? nil : picker
        if openPicker != nil { handle.focusEditor() }
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
            if let descriptor, [.bullet, .ordered, .checklist, .quote].contains(descriptor.glyph) {
                SlashMenuGlyph(kind: descriptor.glyph,
                               color: active ? WFColors.accent : WFColors.secondaryText)
            } else {
                Image(systemName: descriptor?.toolbarSymbol ?? "textformat")
                    .font(.system(size: id == "format.inlineCode" ? 13 : DocumentFormatToolbarMetrics.iconSize))
            }
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
                .frame(width: DocumentFormatToolbarMetrics.controlWidth,
                       height: DocumentFormatToolbarMetrics.controlHeight)
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

/// 「更多」溢出菜单的命令分组（测试与菜单共用一份）。
enum DocumentToolbarOverflow {
    static let paragraphIDs = ["format.paragraph", "format.quote", "format.codeBlock"]
    static let inlineIDs = ["format.bold", "format.italic", "format.underline",
                            "format.strikethrough", "format.highlight", "format.inlineCode"]
}
