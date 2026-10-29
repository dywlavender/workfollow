import AppKit
import SwiftUI

/// 当前选区的样式：段落类型 + 行内标记。
///
/// 工具条靠它显示"现在是什么样式"——原版每个按钮都有
/// `selected: _active(attribute)`（`document_editor_toolbar.dart:148,168,177`），
/// 原生此前没有这一层，按钮永远是灰的，用户点完看不出到底生效没有。
struct DocumentSelectionStyle: Equatable {
    var blockToken: String = DocumentTextCodec.blockToken(.paragraph)
    /// 选区里**每个** run 都带的标记（空选区取输入属性）。只有全选都是粗体才算
    /// 粗体激活——与原版 `isActive` 的口径一致。
    var marks: Set<DocumentMark> = []
    var indentLevel: Int = 0
    var align: DocumentAlignment?
    /// 正文字号档位（正文 1/2/3）；nil = 默认正文。
    var bodySize: DocumentBodySize?

    var blockKind: DocumentBlockKind { DocumentTextCodec.kind(blockToken) }

    func isBlock(_ kind: DocumentBlockKind?) -> Bool {
        guard let kind else { return false }
        return blockToken == DocumentTextCodec.blockToken(kind)
    }

    func has(_ mark: DocumentMark?) -> Bool {
        guard let mark else { return false }
        return marks.contains(mark)
    }
}

/// Host-produced content, deliberately independent of Task/Note models.
struct EditorReference {
    let title: String
    let target: String
}

@MainActor
final class DocumentEditorHandle: ObservableObject {
    weak var textView: NativeTextView?
    weak var coordinator: DocumentEditorCoordinator?
    /// 工具条据此显示激活态；选区变化与每次格式化后都会重算。
    @Published private(set) var style = DocumentSelectionStyle()
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    /// 格式刷取格式后为 true，等待下一次选区落定。
    @Published private(set) var formatPainterActive = false
    /// 编辑区当前是否为空（输入法的组合串也算已输入）。占位文案据此在
    /// 组合阶段就让位——模型要等上屏才会提交，只看文档会一直盖在拼音下面。
    @Published private(set) var liveTextIsEmpty = true
    private var viewUpdateDepth = 0
    private var styleRefreshScheduled = false
    private var liveTextSyncScheduled = false
    private var pendingLiveTextIsEmpty: Bool?
    private var painterStyle: DocumentSelectionStyle?
    private var painterSourceSelection: NSRange?
    private var painterWorkItem: DispatchWorkItem?
    private var observedUndoManager: UndoManager?
    private var undoObservers: [NSObjectProtocol] = []

    // AppKit emits selection callbacks while SwiftUI installs/rebinds storage.
    // Publish the final toolbar style after that update, not its transient styles.
    func beginViewUpdate() { viewUpdateDepth += 1 }
    func endViewUpdate() { viewUpdateDepth -= 1 }

    /// 同步"编辑区里有没有字"。文本回调可能发生在 SwiftUI 更新途中，
    /// 一律排到本轮结束再发布，避免"Publishing changes from within view updates"。
    func syncLiveTextIsEmpty(_ isEmpty: Bool) {
        guard liveTextIsEmpty != isEmpty || pendingLiveTextIsEmpty != nil else { return }
        pendingLiveTextIsEmpty = isEmpty
        guard !liveTextSyncScheduled else { return }
        liveTextSyncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.liveTextSyncScheduled = false
            guard let next = self.pendingLiveTextIsEmpty else { return }
            self.pendingLiveTextIsEmpty = nil
            if self.liveTextIsEmpty != next { self.liveTextIsEmpty = next }
        }
    }

    func prepareForDocumentChange() {
        cancelFormatPainter()
        guard let textView, let coordinator,
              textView.documentIdentity == coordinator.documentID else { return }
        coordinator.prepareForDocumentChange(in: textView)
    }

    @discardableResult
    func replaceDocument(_ document: NativeDocument,
                         commit: @escaping (NativeDocument) -> Void,
                         inverseCommit: @escaping (NativeDocument) -> Void) -> Bool {
        prepareForDocumentChange()
        guard let textView, let storage = textView.textStorage else { return false }
        let accepted = textView.replaceDocumentContent(textView.renderDocument(document),
            range: NSRange(location: 0, length: storage.length), selection: NSRange(location: 0, length: 0),
            commit: commit, inverseCommit: inverseCommit)
        return accepted
    }

    func format(_ command: DocumentFormatCommand) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.applyFormat(command)
        refreshStyle()
    }

    // MARK: 基础格式批：撤销 / 清除 / 对齐 / 缩进 / 颜色 / 格式刷

    func undo() {
        textView?.undoDocumentEdit()
        refreshStyle()
    }

    func redo() {
        textView?.redoDocumentEdit()
        refreshStyle()
    }

    func clearFormatting() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.clearFormatting()
        refreshStyle()
    }

    func applyAlignment(_ alignment: DocumentAlignment) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.applyAlignment(alignment)
        refreshStyle()
    }

    func adjustIndent(by delta: Int) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.adjustIndent(by: delta)
        refreshStyle()
    }

    func applyTextColor(_ hex: String?) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.applyTextColor(hex)
        refreshStyle()
    }

    func applyHighlightColor(_ hex: String?) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.applyHighlightColor(hex)
        refreshStyle()
    }

    /// 工具条高亮按钮：已有高亮就清掉，否则铺默认黄色。
    func toggleHighlight() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.applyHighlightColor(style.marks.hasAnyHighlight ? nil : DocumentColorPalette.defaultHighlight)
        refreshStyle()
    }

    /// 点一次取当前选区样式，下一次选区落定后应用并退出。
    func toggleFormatPainter() {
        if formatPainterActive {
            cancelFormatPainter()
            return
        }
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        refreshStyle()
        painterStyle = style
        painterSourceSelection = textView.selectedRange()
        formatPainterActive = true
    }

    func cancelFormatPainter() {
        painterWorkItem?.cancel()
        painterWorkItem = nil
        painterStyle = nil
        painterSourceSelection = nil
        if formatPainterActive { formatPainterActive = false }
    }

    /// 选区变化回调（`NativeTextView.onSelectionChanged`）：刷新工具条，并推进格式刷。
    func selectionDidChange() {
        refreshStyle()
        scheduleFormatPainterApply()
    }

    private func scheduleFormatPainterApply() {
        guard formatPainterActive, let textView,
              textView.selectedRange() != painterSourceSelection else { return }
        painterWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyFormatPainterNow() }
        painterWorkItem = work
        // 拖选过程中每一帧都会触发 selection change；等指针停稳再落格式。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func applyFormatPainterNow() {
        guard formatPainterActive, let textView, let painterStyle else {
            cancelFormatPainter()
            return
        }
        guard textView.selectedRange() != painterSourceSelection else { return }
        textView.window?.makeFirstResponder(textView)
        textView.applyCapturedStyle(painterStyle)
        cancelFormatPainter()
        refreshStyle()
    }

    private func bindUndoManager(_ manager: UndoManager?) {
        guard manager !== observedUndoManager else {
            // 同一管理器的每次命令后也刷新一次：撤销组按事件收口，工具条按钮
            // 不能等下一次组关闭通知才解除禁用。
            updateUndoState()
            return
        }
        for observer in undoObservers { NotificationCenter.default.removeObserver(observer) }
        undoObservers.removeAll()
        observedUndoManager = manager
        guard let manager else {
            setUndoState(canUndo: false, canRedo: false)
            return
        }
        let center = NotificationCenter.default
        for name in [Notification.Name.NSUndoManagerDidUndoChange,
                     Notification.Name.NSUndoManagerDidRedoChange,
                     Notification.Name.NSUndoManagerDidCloseUndoGroup] {
            undoObservers.append(center.addObserver(forName: name, object: manager, queue: .main) {
                [weak self] _ in self?.updateUndoState()
            })
        }
        updateUndoState()
    }

    private func updateUndoState() {
        guard let textView else {
            setUndoState(canUndo: false, canRedo: false)
            return
        }
        setUndoState(canUndo: textView.canUndoDocumentEdit, canRedo: textView.canRedoDocumentEdit)
    }

    private func setUndoState(canUndo nextUndo: Bool, canRedo nextRedo: Bool) {
        if canUndo != nextUndo { canUndo = nextUndo }
        if canRedo != nextRedo { canRedo = nextRedo }
    }

    /// 从当前选区重算样式。空选区读 `typingAttributes`——那正是"接下来输入会是什么
    /// 样式"，所以空文档里点段落格式也能在工具条上看到反馈（原版同理）。
    func refreshStyle() {
        if viewUpdateDepth > 0 {
            guard !styleRefreshScheduled else { return }
            styleRefreshScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.styleRefreshScheduled = false
                self.refreshStyle()
            }
            return
        }
        guard let textView, let storage = textView.textStorage else {
            if style != DocumentSelectionStyle() { style = DocumentSelectionStyle() }
            setUndoState(canUndo: false, canRedo: false)
            return
        }
        bindUndoManager(textView.undoManager)
        let range = textView.selectedRange()
        let sample = range.length == 0
            ? NSAttributedString(string: " ", attributes: textView.typingAttributes)
            : storage.attributedSubstring(from: range)
        let next = DocumentTextCodec.style(of: sample)
        if next != style { style = next }
    }

    func focusEditor() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func revealChecklistLine(_ line: Int) {
        textView?.revealChecklistLine(line)
        refreshStyle()
    }

    /// 窗口失去 key（例如用户去滚 PDF）时，中文输入法可能还停在组合串；
    /// 先把未上屏内容提交给模型，避免切回来时丢字。
    func flushPendingComposition() {
        guard let textView, let coordinator else { return }
        coordinator.flushPendingComposition(in: textView)
    }

    func focusEnd() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    func editLink() { textView?.editDocumentLink(nil); refreshStyle() }
    func removeLink() { textView?.removeDocumentLink(nil); refreshStyle() }
    func insertAttachment() { textView?.insertDocumentAttachment(nil); refreshStyle() }
    func insertImage() { textView?.insertDocumentImage(nil); refreshStyle() }
    func insertDiagram() { textView?.insertDocumentDiagram(at: nil); refreshStyle() }
    func insertTable() { textView?.insertDocumentTable(at: nil); refreshStyle() }
    func insertFormula() { textView?.insertDocumentFormula(at: nil); refreshStyle() }
    func insertTime(format: String) { textView?.window?.makeFirstResponder(textView); textView?.insertDocumentTime(format: format); refreshStyle() }
    func insertDivider() { textView?.window?.makeFirstResponder(textView); textView?.insertDocumentDivider(); refreshStyle() }
    func insertReference(_ reference: EditorReference) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let content = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [
            DocumentRun(text: reference.title, marks: [.link(reference.target)])
        ])])
        textView.insertText(textView.renderDocument(content), replacementRange: textView.selectedRange())
        textView.typingAttributes = textView.paragraphAttributes()
    }

    /// Reference command with host fields sharing the document's undo/redo.
    @discardableResult
    func insertReference(_ reference: EditorReference,
                         commit: @escaping (NativeDocument) -> Void,
                         undoCommit: @escaping (NativeDocument) -> Void) -> Bool {
        guard let textView else { return false }
        textView.window?.makeFirstResponder(textView)
        let range = textView.selectedRange()
        let content = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [
            DocumentRun(text: reference.title, marks: [.link(reference.target)])
        ])])
        let value = textView.renderDocument(content)
        guard textView.replaceDocumentContent(value, range: range,
            selection: NSRange(location: range.location + value.length, length: 0),
            commit: commit, inverseCommit: undoCommit) else { return false }
        textView.typingAttributes = textView.paragraphAttributes()
        refreshStyle()
        return true
    }
}

/// The decoration lane lives before the host's content origin. TextKit needs
/// it inside its drawable bounds, but it must not consume host text width.
enum DocumentEditorGeometry {
    static let decorationLane: CGFloat = 20
    /// 装饰标记（空行 `+`、标题角标 `H1/H2/H3`）距"宿主内可见边界"的间距。
    /// 基准是滴答实测：`+` **墨迹**起点距分栏线 5.5pt（2x 截图量得 11px）。
    /// 抗锯齿会让墨迹比这里的几何值再向右约 0.5pt，所以几何值取 5.0pt。
    static let decorationMarkerOffset: CGFloat = 5
    /// 规范下限：任何宿主里标记都不允许比 4pt 更贴边界
    /// （见 `task-inspector-content-alignment.md`）。
    static let decorationMinInset: CGFloat = 4
    /// 装饰标记在容器坐标里的 x。绘制、命中测试与测试断言共用这一处，
    /// 不再各自写 `max(5, …)` / `max(2, …)` 两个不同的下限。
    ///
    /// 注意：`visibleMinX` 是**宿主内可见的装饰槽宽度**（容器坐标），
    /// 不是分栏线位置；标记在它基础上再向内让 `decorationMarkerOffset`。
    static func decorationMarkerX(visibleMinX: CGFloat) -> CGFloat {
        max(decorationMinInset, visibleMinX + decorationMarkerOffset)
    }
    static let listTextIndent: CGFloat = 16
    /// 检查项文字缩进：滴答的 17pt 勾选框 + 约 6pt 间距，比圆点/编号多让 8pt。
    static let checklistTextIndent: CGFloat = 24
    /// 检查项行间距：行内文字约 17pt，再加 12pt 留白，行距接近滴答的 30pt。
    /// 滴答截图实测相邻检查项节距 ≈ 37pt：18pt 行盒 + 19pt 段间距。
    static let checklistRowSpacing: CGFloat = 19
    /// 行间分隔线在留白中的位置（留白的一半）。
    static let checklistSeparatorOffset: CGFloat = checklistRowSpacing / 2
    static let listIndentStep: CGFloat = 20
    static let quoteTextIndent: CGFloat = 16
    /// 列表标记左缘的光学补偿：滴答的圆点墨迹与正文文字墨迹齐平（都在 x19），
    /// 而首字形起点比它的墨迹早约 1pt（字形自带左侧边距），所以几何起点再补 1pt。
    static let listMarkerOpticalOffset: CGFloat = 1
    static let structuredParagraphSpacing: CGFloat = 2
    static let quoteRuleInset: CGFloat = 4
    static let quoteRuleWidth: CGFloat = 2
    /// 代码块左右内边距：文字距背景块边缘；背景绘制与段落缩进共用这一处。
    static let codeBlockTextInset: CGFloat = 12
    /// 代码块卡片向上探出的留白（落在上一段的段距里）；底边贴住行盒，
    /// 避免压到下一段文字的字形。
    static let codeBlockVerticalPadding: CGFloat = 4
    /// 行内代码底片：水平探出字面 2pt、垂直从行盒里收进 2.5pt 画成小圆角底。
    static let inlineCodeChipPaddingX: CGFloat = 2
    static let inlineCodeChipPaddingY: CGFloat = 2.5
    static let inlineCodeChipRadius: CGFloat = 3.5
}

struct DocumentEditor: View {
    let documentID: UUID
    let document: NativeDocument
    let onDocumentChange: (NativeDocument) -> Void
    let onEscape: () -> InspectorEscapeEffect
    let onEditingChanged: (Bool) -> Void
    var profile = DocumentProfile()
    var contentSized = false
    var handle: DocumentEditorHandle?
    var decorationVisibleMinX: CGFloat = 0
    /// 浮窗接管编辑权时，原宿主只保留富文本展示：可选可复制，但不能修改。
    var readOnly = false

    var body: some View {
        if let ready = try? document.materialized() {
        DocumentEditorContent(documentID: documentID, document: ready,
                              onDocumentChange: onDocumentChange, onEscape: onEscape,
                              onEditingChanged: onEditingChanged, profile: profile,
                                  contentSized: contentSized, handle: handle,
                                  decorationVisibleMinX: decorationVisibleMinX,
                                  readOnly: readOnly)
            .padding(.leading, -DocumentEditorGeometry.decorationLane)
        } else {
            Text("正文读取失败，暂时无法编辑").foregroundStyle(.secondary)
        }
    }
}

private struct DocumentEditorContent: NSViewRepresentable {
    let documentID: UUID
    let document: NativeDocument
    let onDocumentChange: (NativeDocument) -> Void
    let onEscape: () -> InspectorEscapeEffect
    let onEditingChanged: (Bool) -> Void
    var profile = DocumentProfile()
    var contentSized = false
    var handle: DocumentEditorHandle?
    var decorationVisibleMinX: CGFloat = 0
    var readOnly = false

    func makeCoordinator() -> DocumentEditorCoordinator {
        let coordinator = DocumentEditorCoordinator(documentID: documentID, document: document,
                                                    onDocumentChange: onDocumentChange,
                                                    onEscape: onEscape,
                                                    onEditingChanged: onEditingChanged)
        coordinator.handle = handle
        return coordinator
    }

    func makeNSView(context: Context) -> NSView {
        handle?.beginViewUpdate()
        defer { handle?.endViewUpdate() }
        let textView = NativeTextView(frame: .zero, textContainer: nil)
        textView.paragraphSpacingOverride = profile.paragraphSpacing
        textView.decorationVisibleMinX = decorationVisibleMinX
        textView.documentIdentity = documentID
        // 只读预览仍可选中/复制，但不能输入、勾选或打开块菜单。
        textView.isEditable = !readOnly
        textView.isSelectable = true
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(textView.renderDocument(document))
        textView.seedTrailingParagraphKind(document.blocks.last.flatMap { block in
            block.runs.allSatisfy { $0.text.isEmpty } ? block.kind : nil
        }, indentLevel: document.blocks.last?.indentLevel ?? 0,
           listStart: document.blocks.last?.listStart)
        context.coordinator.didLoadDocument(in: textView, reparseInline: true)
        textView.onEscape = onEscape
        textView.onCancelTransient = { [weak handle] in
            guard handle?.formatPainterActive == true else { return false }
            handle?.cancelFormatPainter()
            return true
        }
        textView.onEditingChanged = onEditingChanged
        textView.onSelectionChanged = { [weak handle] in handle?.selectionDidChange() }
        textView.onLiveTextChange = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView, let coordinator else { return }
            coordinator.handle?.syncLiveTextIsEmpty(textView.string.isEmpty)
        }
        textView.profile = profile
        textView.autoresizingMask = [.width]
        handle?.textView = textView
        handle?.coordinator = context.coordinator
        handle?.refreshStyle()
        // Content-sized editors belong to their host's scroll view. A second
        // scroll viewport is unnecessary and competes for input ownership.
        if contentSized {
            textView.usesHostScrollView = true
            textView.isVerticallyResizable = false
            textView.minSize.height = 48
            return textView
        }
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        CompactScrollStyle.apply(to: scrollView)
        scrollView.focusRingType = .none
        scrollView.documentView = textView
        return scrollView
    }

    private static func editor(in view: NSView) -> NativeTextView? {
        (view as? NativeTextView) ?? ((view as? NSScrollView)?.documentView as? NativeTextView)
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let textView = Self.editor(in: view) else { return }
        handle?.beginViewUpdate()
        defer { handle?.endViewUpdate() }
        textView.decorationVisibleMinX = decorationVisibleMinX
        textView.isEditable = !readOnly
        handle?.textView = textView
        handle?.coordinator = context.coordinator
        context.coordinator.handle = handle
        textView.onSelectionChanged = { [weak handle] in handle?.selectionDidChange() }
        textView.onLiveTextChange = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView, let coordinator else { return }
            coordinator.handle?.syncLiveTextIsEmpty(textView.string.isEmpty)
        }
        textView.onCancelTransient = { [weak handle] in
            guard handle?.formatPainterActive == true else { return false }
            handle?.cancelFormatPainter()
            return true
        }
        // 段距随 profile 变；先落到 textView，再让协调器按新节奏重建。
        textView.paragraphSpacingOverride = profile.paragraphSpacing
        context.coordinator.update(textView, documentID: documentID, document: document,
                                   onDocumentChange: onDocumentChange,
                                   onEscape: onEscape,
                                   onEditingChanged: onEditingChanged)
        // Flush the outgoing document with its own host actions before rebinding.
        textView.profile = profile
        if contentSized { textView.invalidateIntrinsicContentSize() }
        // Refresh after model/selection rebind, not from the outgoing document.
        handle?.refreshStyle()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView,
                      context: Context) -> CGSize? {
        guard contentSized, let width = proposal.width, width > 0,
              let textView = Self.editor(in: nsView),
              let container = textView.textContainer,
              let layout = textView.textLayoutManager else { return nil }
        textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        textView.resizeDocumentDividers()
        // 容器宽 = 视图宽 − 左右 textContainerInset（与 widthTracksTextView 的
        // 自动口径一致），否则行宽会超出视图右缘 20pt。
        container.containerSize = NSSize(
            width: max(1, width - textView.textContainerInset.width * 2),
            height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: NSRect(origin: .zero, size: container.containerSize))
        let bottom = layout.usageBoundsForTextContainer.maxY
        let height = max(48, ceil(bottom + textView.textContainerInset.height * 2 + 8))
        textView.setFrameSize(NSSize(width: width, height: height))
        textView.revealCaretInHostAfterLayout()
        return CGSize(width: width, height: height)
    }

    static func dismantleNSView(_ view: NSView, coordinator: DocumentEditorCoordinator) {
        guard let textView = editor(in: view) else { return }
        coordinator.detach(textView)
    }
}
