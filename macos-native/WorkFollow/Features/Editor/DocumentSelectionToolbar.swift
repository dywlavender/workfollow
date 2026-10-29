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
    /// 选区当前的颜色（多 run 取交集）：按钮小色条与色板勾选态用。
    var textColorHex: String? = nil
    var highlightHex: String? = nil
    var onTextColor: (String?) -> Void = { _ in }
    var onHighlightColor: (String?) -> Void = { _ in }

    @State private var openColorPicker: DocumentToolbarPicker?

    private static let coordinateSpace = "editor-selection-toolbar"

    /// 常用内联样式：粗体/斜体/下划线/删除线/高亮/行内代码。
    /// 高亮在原位换成「背景色」色板入口，紧邻其后再补一个「文字颜色」。
    private var inlineCommands: [DocumentFormatCommand] {
        EditorCommandCatalog.selectionFormatIDs.compactMap(EditorCommandCatalog.format)
    }
    private var leadingCommands: [DocumentFormatCommand] {
        inlineCommands.filter { !["format.highlight", "format.inlineCode"].contains($0.id) }
    }
    private var trailingCommands: [DocumentFormatCommand] {
        inlineCommands.filter { $0.id == "format.inlineCode" }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 2) {
            ForEach(actions) { action in
                Button {
                    onInvoke(action)
                } label: {
                    Label(action.displayTitle, systemImage: action.symbol)
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
            ForEach(leadingCommands, id: \.id) { command in
                inlineButton(command)
            }
            backgroundButton
            textColorButton
            ForEach(trailingCommands, id: \.id) { command in
                inlineButton(command)
            }
            Divider().frame(height: 16)
            Button { onLink() } label: {
                Image(systemName: "link").frame(width: 24, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(WFColors.text)
            .hoverTip("链接", placement: .above, activeAlways: true)
            .accessibilityLabel("链接")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .frame(idealWidth: preferredWidth)
        .frame(height: 34)
        .background(WFColors.overlay, in: RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius).stroke(WFColors.overlayBorder))
        .coordinateSpace(name: Self.coordinateSpace)
        .hidesSystemFocusEffect()
    }

    /// 浮条本身是**非激活子窗口**：提示必须 `activeAlways`，否则悬停事件不送达。
    private func inlineButton(_ command: DocumentFormatCommand) -> some View {
        Button { onFormat(command) } label: {
            Image(systemName: command.descriptor.toolbarSymbol)
                .frame(width: 24, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(WFColors.text)
        .hoverTip(command.descriptor.title, placement: .above, activeAlways: true)
        .accessibilityLabel(command.descriptor.title)
        .editorCommandFrame(command.id, space: Self.coordinateSpace)
    }

    /// 背景色：整块「A」就是色板入口（面板首行「无颜色」负责清除），
    /// 与主工具条同款，不再保留只能点小箭头的第二入口。
    private var backgroundButton: some View {
        Button { toggleColorPicker(.highlightColor) } label: {
            ZStack(alignment: .bottomTrailing) {
                Text("A")
                    .font(.system(size: 13))
                    .foregroundStyle(WFColors.text)
                    .padding(.horizontal, 3)
                    .padding(.trailing, 2)
                    .background(DocumentFormatToolbarMetrics.highlightFill,
                                in: RoundedRectangle(cornerRadius: 3))
                Image(systemName: "chevron.down")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(WFColors.secondaryText)
                    .allowsHitTesting(false)
            }
            .frame(width: 24, height: 26)
            .background(highlightHex != nil ? WFColors.accentFaint : Color.clear,
                        in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background { colorPickerPresenter(.highlightColor) }
        .hoverTip("高亮颜色", placement: .above, activeAlways: true)
        .accessibilityLabel("高亮颜色")
        .editorCommandFrame("format.highlight", space: Self.coordinateSpace)
    }

    private var textColorButton: some View {
        Button { toggleColorPicker(.textColor) } label: {
            VStack(spacing: 1) {
                Text("A").font(.system(size: 12, weight: .medium))
                Capsule()
                    .fill(textColorHex
                        .flatMap { NSColor(documentHex: $0) }.map { Color(nsColor: $0) } ?? WFColors.text)
                    .frame(width: 12, height: 3)
            }
            .frame(width: 24, height: 26)
            .background(textColorHex != nil ? WFColors.accentFaint : Color.clear,
                        in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(textColorHex != nil ? WFColors.accent : WFColors.text)
        .background { colorPickerPresenter(.textColor) }
        .hoverTip("文字颜色", placement: .above, activeAlways: true)
        .accessibilityLabel("文字颜色")
        .editorCommandFrame("format.textColor", space: Self.coordinateSpace)
    }

    private func toggleColorPicker(_ picker: DocumentToolbarPicker) {
        openColorPicker = openColorPicker == picker ? nil : picker
    }

    /// 色板与主工具条同一个锚定面板：开在按钮上方，点选后把颜色交回
    /// NativeTextView，由它作用在仍是当前选区的文本上并刷新这条浮条。
    @ViewBuilder
    private func colorPickerPresenter(_ picker: DocumentToolbarPicker) -> some View {
        if openColorPicker == picker {
            AnchoredPropertyPanel(isPresented: Binding(
                get: { openColorPicker == picker },
                set: { if !$0 { openColorPicker = nil } }),
                width: DocumentToolbarPicker.textColorWidth,
                prefersAbove: true, placement: .verticalInOwner,
                focusPolicy: .preservePresenter,
                title: picker.panelTitle) {
                DocumentColorPickerCard(
                    title: picker.panelTitle,
                    defaultTitle: picker == .textColor ? "默认颜色" : "无颜色",
                    selectedHex: picker == .textColor ? textColorHex : highlightHex) { hex in
                    openColorPicker = nil
                    if picker == .textColor { onTextColor(hex) } else { onHighlightColor(hex) }
                }
            }
        }
    }

    private var preferredWidth: CGFloat {
        let actionWidth = actions.reduce(CGFloat(0)) { total, action in
            total + (action.displayTitle as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: 13)
            ]).width + 30
        }
        return actionWidth + CGFloat(inlineCommands.count + 2) * 26 + 24
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
    /// Summary embeds this row inside its document card; task/note popovers
    /// retain the existing floating surface.
    var embedded = false

    /// Tooltip coordinates stay outside the horizontal scroller. Picker sizes
    /// use those same real button frames before their existing child host opens.
    @StateObject private var overlay = ToolbarTooltipState()
    /// 当前开着的小面板（标题级别 / 插入时间）。
    @State private var openPicker: DocumentToolbarPicker?
    @State private var pickerSize: CGSize?
    /// 「更多格式」浮条：只放工具条上没有独立按钮的格式。
    /// 当前开着的「插入」浮条。
    @State private var showInsert = false

    private static let headingCommands = EditorCommandCatalog.headingPickerIDs.compactMap(EditorCommandCatalog.format)

    /// 「插入」固定在工具条最右，不受横向滚动影响；点开后在上方浮一行图标。
    /// 图片、链接、代码块、分割线、引用、附件、drawio 都收在这里。
    private var insertButton: some View {
        ToolbarButton(title: "插入", active: showInsert, state: overlay,
                      action: { toggleInsert() }) {
            Image(systemName: "plus")
        }
        .background { insertPresenter }
        .editorPopupTriggerFrame("insert")
    }

    @ViewBuilder
    private var insertPresenter: some View {
        if showInsert {
            AnchoredPropertyPanel(isPresented: Binding(
                get: { showInsert },
                set: { if !$0 { showInsert = false } }),
                width: insertWidth,
                horizontalOutset: max(0, insertWidth - DocumentFormatToolbarMetrics.controlWidth),
                prefersAbove: false, placement: .verticalInOwner,
                focusPolicy: .preservePresenter,
                title: "插入") {
                HStack(spacing: 0) {
                    ForEach(DocumentInsertCatalog.items) { item in
                        InsertActionButton(title: item.title, symbol: item.symbol,
                                           active: insertActive(item.id)) {
                            performInsert(item.id)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .frame(height: DocumentFormatToolbarMetrics.height)
                .background(WFColors.overlay,
                            in: RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius)
                        .stroke(WFColors.overlayBorder, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
            }
        }
    }

    private var insertWidth: CGFloat {
        CGFloat(DocumentInsertCatalog.items.count) * DocumentFormatToolbarMetrics.controlWidth + 12
    }

    private func insertActive(_ id: String) -> Bool {
        switch id {
        case "insert.codeBlock": handle.style.isBlock(.code)
        case "insert.quote": handle.style.isBlock(.quote)
        default: false
        }
    }

    private func toggleInsert() {
        openPicker = nil
        pickerSize = nil
        showInsert.toggle()
        if showInsert { handle.focusEditor() }
    }

    private func performInsert(_ id: String) {
        switch id {
        case "insert.image": handle.insertImage()
        case "insert.table": handle.insertTable()
        case "insert.formula": handle.insertFormula()
        case "insert.link": handle.editLink()
        case "insert.codeBlock":
            if let command = EditorCommandCatalog.format("format.codeBlock") { handle.format(command) }
        case "insert.divider": handle.insertDivider()
        case "insert.quote":
            if let command = EditorCommandCatalog.format("format.quote") { handle.format(command) }
        case "insert.attachment": handle.insertAttachment()
        case "insert.diagram": handle.insertDiagram()
        default: break
        }
        showInsert = false
    }

    var body: some View {
        HStack(spacing: 0) {
        ScrollView(.horizontal, showsIndicators: false) {
            // 格式类留在这条横向滚动行：H · B · A/色板 文字色 ｜ 对齐 缩进 ｜
            // 清单 无序 有序 ｜ 斜体 下划线 删除线 ｜ 时间 行内代码。
            // 插入类（图片/链接/代码块/分割线/引用/附件/drawio）收进右侧固定的「插入」。
            HStack(spacing: 0) {
                ToolbarButton(title: "撤销", active: false, state: overlay,
                              enabled: handle.canUndo, action: { handle.undo() }) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .editorCommandFrame("format.undo", space: DocumentToolbarTooltip.space)
                ToolbarButton(title: "重做", active: false, state: overlay,
                              enabled: handle.canRedo, action: { handle.redo() }) {
                    Image(systemName: "arrow.uturn.forward")
                }
                .editorCommandFrame("format.redo", space: DocumentToolbarTooltip.space)
                toolbarDivider
                ToolbarButton(title: "格式刷", active: handle.formatPainterActive, state: overlay,
                              action: { handle.toggleFormatPainter() }) {
                    Image(systemName: "paintbrush")
                }
                .editorCommandFrame("format.formatPainter", space: DocumentToolbarTooltip.space)
                ToolbarButton(title: "清除格式", active: false, state: overlay,
                              action: { handle.clearFormatting() }) {
                    Image(systemName: "eraser")
                }
                .editorCommandFrame("format.clearFormatting", space: DocumentToolbarTooltip.space)
                toolbarDivider
                // 「H」不是图标：原版这个按钮就是字母 H（`label: 'H'`），16pt。
                ToolbarButton(title: "标题", active: headingActive, state: overlay,
                              action: { togglePicker(.heading) }) {
                    Text("H").font(.system(size: 16))
                }
                .background { pickerPresenter(.heading) }
                .editorPopupTriggerFrame("heading")
                formatButton("format.bold")
                // 「A」底下永远垫一块高亮色（原版 `label: 'A', highlight: true`）。
                // 整块 A 就是色板入口：点一下直接弹出颜色面板，面板首行「无颜色」
                // 负责清除高亮——不再保留只能点右下角小箭头的第二入口。
                ToolbarButton(title: "高亮颜色", active: handle.style.marks.hasAnyHighlight, state: overlay,
                              action: { togglePicker(.highlightColor) }) {
                    ZStack(alignment: .bottomTrailing) {
                        Text("A")
                            .font(.system(size: 16))
                            .foregroundStyle(WFColors.text)
                            .padding(.horizontal, WFSpace.tight)
                            .padding(.trailing, 3)
                            .background(DocumentFormatToolbarMetrics.highlightFill,
                                        in: RoundedRectangle(cornerRadius: 4))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(WFColors.secondaryText)
                            .padding(.trailing, 1)
                            .allowsHitTesting(false)
                    }
                }
                .background { pickerPresenter(.highlightColor) }
                .editorPopupTriggerFrame("highlightColor")
                .editorCommandFrame("format.highlight", space: DocumentToolbarTooltip.space)
                ToolbarButton(title: "文字颜色", active: handle.style.marks.textColorHex != nil, state: overlay,
                              action: { togglePicker(.textColor) }) {
                    VStack(spacing: 1) {
                        Text("A").font(.system(size: 14, weight: .medium))
                        Capsule()
                            .fill(handle.style.marks.textColorHex
                                .flatMap { NSColor(documentHex: $0) }.map { Color(nsColor: $0) } ?? WFColors.text)
                            .frame(width: 14, height: 3)
                    }
                }
                .background { pickerPresenter(.textColor) }
                .editorPopupTriggerFrame("textColor")
                .editorCommandFrame("format.textColor", space: DocumentToolbarTooltip.space)
                toolbarDivider
                ToolbarButton(title: "对齐方式", active: handle.style.align != nil && handle.style.align != .left,
                              state: overlay, action: { togglePicker(.alignment) }) {
                    Image(systemName: (handle.style.align ?? .left).symbol)
                }
                .background { pickerPresenter(.alignment) }
                .editorPopupTriggerFrame("alignment")
                .editorCommandFrame("format.alignment", space: DocumentToolbarTooltip.space)
                ToolbarButton(title: "减少缩进", active: false, state: overlay,
                              action: { handle.adjustIndent(by: -1) }) {
                    Image(systemName: "decrease.indent")
                }
                .editorCommandFrame("format.indentDecrease", space: DocumentToolbarTooltip.space)
                ToolbarButton(title: "增加缩进", active: false, state: overlay,
                              action: { handle.adjustIndent(by: 1) }) {
                    Image(systemName: "increase.indent")
                }
                .editorCommandFrame("format.indentIncrease", space: DocumentToolbarTooltip.space)
                toolbarDivider
                formatButton("format.checklist")
                formatButton("format.bullet")
                formatButton("format.ordered")
                toolbarDivider
                formatButton("format.italic")
                formatButton("format.underline")
                formatButton("format.strikethrough")
                toolbarDivider
                ToolbarButton(title: "插入当前时间", active: openPicker == .time, state: overlay,
                              action: { togglePicker(.time) }) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .background { pickerPresenter(.time) }
                .editorPopupTriggerFrame("time")
                formatButton("format.inlineCode")
            }
            .buttonStyle(.plain)
            // Optical glyph size is separate from the unchanged hit target.
            .font(.system(size: DocumentFormatToolbarMetrics.iconSize, weight: .regular))
            .padding(.horizontal, DocumentFormatToolbarMetrics.horizontalInset)
        }
        // 插入固定在工具条最右：放在横向 ScrollView 之外，窄宽度下也总能点到。
        toolbarDivider
        insertButton
        .buttonStyle(.plain)
        .font(.system(size: DocumentFormatToolbarMetrics.iconSize, weight: .regular))
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
                    if openPicker == nil && !showInsert {
                        tooltipLayer(containerWidth: proxy.size.width)
                    }
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
    /// 工具条常驻正文上方，所以标题/颜色/对齐等浮层统一向下展开。
    @ViewBuilder
    private func pickerPresenter(_ picker: DocumentToolbarPicker) -> some View {
        if openPicker == picker, let size = pickerSize, size.width > 0, size.height > 0 {
            AnchoredPropertyPanel(isPresented: Binding(
                get: { openPicker == picker },
                set: { if !$0 { openPicker = nil } }),
                width: size.width,
                horizontalOutset: picker.alignedToEnd
                    ? max(0, size.width - DocumentFormatToolbarMetrics.controlWidth) : 0,
                prefersAbove: false, placement: .verticalInOwner,
                focusPolicy: .preservePresenter,
                title: picker.panelTitle) {
                pickerCard(picker, size: size)
            }
        }
    }

    @ViewBuilder
    private func pickerCard(_ picker: DocumentToolbarPicker, size: CGSize) -> some View {
        if picker == .textColor || picker == .highlightColor {
            DocumentColorPickerCard(
                title: picker == .textColor ? "文字颜色" : "背景颜色",
                defaultTitle: picker == .textColor ? "默认颜色" : "无颜色",
                selectedHex: picker == .textColor
                    ? handle.style.marks.textColorHex : handle.style.marks.highlightHex) { hex in
                if picker == .textColor { handle.applyTextColor(hex) }
                else { handle.applyHighlightColor(hex) }
                openPicker = nil
            }
        } else {
            DocumentToolbarPickerCard(picker: picker,
                                      selectedIndex: picker == .heading ? headingIndex
                                          : picker == .alignment ? alignmentIndex : nil,
                                      onPick: { pick(picker, index: $0) },
                                      viewportHeight: size.height)
        }
    }

    /// 当前段落落在对齐菜单的哪一项（默认左对齐）。
    private var alignmentIndex: Int? {
        DocumentAlignment.allCases.firstIndex(of: handle.style.align ?? .left)
    }

    /// 当前段落在「正文 / 正文 1–3 / 标题」菜单里的哪一项。
    private var headingIndex: Int? {
        let commands = Self.headingCommands
        let kind = DocumentTextCodec.kind(handle.style.blockToken)
        if kind == .paragraph, let size = handle.style.bodySize {
            return commands.firstIndex { $0.bodySize == size }
        }
        return commands.firstIndex { $0.bodySize == nil && $0.block == kind }
    }

    /// 当前段落是不是标题或非默认字号。正文（默认 14pt）不算。
    private var headingActive: Bool {
        if handle.style.bodySize != nil { return true }
        return (1...6).map(DocumentBlockKind.heading)
            .contains { handle.style.isBlock($0) }
    }

    private func togglePicker(_ picker: DocumentToolbarPicker) {
        showInsert = false
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
        case .alignment:
            if DocumentAlignment.allCases.indices.contains(index) {
                handle.applyAlignment(DocumentAlignment.allCases[index])
            }
        case .textColor, .highlightColor:
            break
        }
        openPicker = nil
    }

    /// 工具条上的一个图标按钮：把激活态、悬停底、尺寸与提示一次装好。
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
    var enabled = true
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
                            : hovering && enabled ? WFColors.listRowHover : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4))
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .toolbarTooltip(title, state: state)
        .accessibilityLabel(title)
    }
}

struct DocumentInsertItem: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
}

/// 「插入」浮条的内容（测试与浮条共用一份）。
enum DocumentInsertCatalog {
    static let items: [DocumentInsertItem] = [
        .init(id: "insert.image", title: "图片", symbol: "photo"),
        .init(id: "insert.table", title: "表格", symbol: "tablecells"),
        .init(id: "insert.formula", title: "公式", symbol: "x.squareroot"),
        .init(id: "insert.link", title: "链接", symbol: "link"),
        .init(id: "insert.codeBlock", title: "代码块", symbol: "curlybraces"),
        .init(id: "insert.divider", title: "分割线", symbol: "minus"),
        .init(id: "insert.quote", title: "引用", symbol: "text.quote"),
        .init(id: "insert.attachment", title: "附件", symbol: "paperclip"),
        .init(id: "insert.diagram", title: "流程图（draw.io）",
              symbol: "point.3.connected.trianglepath.dotted")
    ]
}

/// 「插入」浮条里的图标按钮：视觉与工具条按钮一致。浮条是**非激活子窗口**
/// （永不成为 key window），所以提示必须用 `activeAlways`，否则 hover 事件不送达。
private struct InsertActionButton: View {
    let title: String
    let symbol: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: DocumentFormatToolbarMetrics.iconSize))
                .foregroundStyle(active ? WFColors.accent : WFColors.secondaryText)
                .frame(width: DocumentFormatToolbarMetrics.controlWidth,
                       height: DocumentFormatToolbarMetrics.controlHeight)
                .background(active ? WFColors.accentFaint
                            : hovering ? WFColors.listRowHover : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .hoverTip(title, activeAlways: true)
        .accessibilityLabel(title)
    }
}
