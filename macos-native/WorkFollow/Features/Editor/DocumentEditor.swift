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
    weak var webView: MilkdownWebView?
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
    var documentIdentity: UUID? { webView?.documentIdentity ?? textView?.documentIdentity }
    var hasAttachedEditor: Bool { webView?.window != nil || textView?.window != nil }

    func updateFromWeb(_ value: MilkdownSelection) {
        if viewUpdateDepth > 0 {
            DispatchQueue.main.async { [weak self] in self?.updateFromWeb(value) }; return
        }
        let next = DocumentSelectionStyle(blockToken: value.style.blockToken,
            marks: Set(value.style.marks.compactMap { try? MilkdownDocumentCodec.decodeMark($0) }),
            indentLevel: value.style.indentLevel, align: value.style.align, bodySize: value.style.bodySize)
        if next != style { style = next }
        setUndoState(canUndo: value.canUndo, canRedo: value.canRedo)
        syncLiveTextIsEmpty(value.empty)
        if let active = value.formatPainterActive, active != formatPainterActive { formatPainterActive = active }
    }

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
        if let webView { webView.prepareForDocumentChange(); return }
        guard let textView, let coordinator,
              textView.documentIdentity == coordinator.documentID else { return }
        coordinator.prepareForDocumentChange(in: textView)
    }

    @discardableResult
    func replaceDocument(_ document: NativeDocument,
                         commit: @escaping (NativeDocument) -> Void,
                         inverseCommit: @escaping (NativeDocument) -> Void) -> Bool {
        if let webView { return webView.insert(document, whole: true, commit: commit, inverse: inverseCommit) }
        prepareForDocumentChange()
        guard let textView, let storage = textView.textStorage else { return false }
        let accepted = textView.replaceDocumentContent(textView.renderDocument(document),
            range: NSRange(location: 0, length: storage.length), selection: NSRange(location: 0, length: 0),
            commit: commit, inverseCommit: inverseCommit)
        return accepted
    }

    func format(_ command: DocumentFormatCommand) {
        if let webView { webView.perform("format", payload: ["id": String(command.id.dropFirst(7))]); return }
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.applyFormat(command)
        refreshStyle()
    }

    // MARK: 基础格式批：撤销 / 清除 / 对齐 / 缩进 / 颜色 / 格式刷

    func undo() {
        if let webView { webView.perform("undo"); return }
        textView?.undoDocumentEdit()
        refreshStyle()
    }

    func redo() {
        if let webView { webView.perform("redo"); return }
        textView?.redoDocumentEdit()
        refreshStyle()
    }

    func clearFormatting() {
        if let webView { webView.perform("clear"); return }
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.clearFormatting()
        refreshStyle()
    }

    func applyAlignment(_ alignment: DocumentAlignment) {
        if let webView { webView.perform("align", payload: ["value": alignment.rawValue]); return }
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.applyAlignment(alignment)
        refreshStyle()
    }

    func adjustIndent(by delta: Int) {
        if let webView { webView.perform("indent", payload: ["delta": delta]); return }
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.adjustIndent(by: delta)
        refreshStyle()
    }

    func applyTextColor(_ hex: String?) {
        if let webView { webView.perform("color", payload: ["value": hex.map { $0 as Any } ?? NSNull()]); return }
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.applyTextColor(hex)
        refreshStyle()
    }

    func applyHighlightColor(_ hex: String?) {
        if let webView { webView.perform("highlight", payload: ["value": hex.map { $0 as Any } ?? NSNull()]); return }
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.applyHighlightColor(hex)
        refreshStyle()
    }

    /// 工具条高亮按钮：已有高亮就清掉，否则铺默认黄色。
    func toggleHighlight() {
        if webView != nil { applyHighlightColor(style.marks.hasAnyHighlight ? nil : DocumentColorPalette.defaultHighlight); return }
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.applyHighlightColor(style.marks.hasAnyHighlight ? nil : DocumentColorPalette.defaultHighlight)
        refreshStyle()
    }

    /// 点一次取当前选区样式，下一次选区落定后应用并退出。
    func toggleFormatPainter() {
        if let webView {
            if formatPainterActive { cancelFormatPainter() }
            else { formatPainterActive = true; webView.perform("captureStyle") }
            return
        }
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
        if formatPainterActive { webView?.perform("cancelPainter") }
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
        if let webView { if let selection = webView.selection { updateFromWeb(selection) }; return }
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
        if let webView { webView.focus(); return }
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func revealChecklistLine(_ line: Int) {
        if let webView { webView.perform("revealBlock", payload: ["index": line]); return }
        textView?.revealChecklistLine(line)
        refreshStyle()
    }

    /// `nil` 表示编辑器还没换上目标文档（调用方可稍后重试）；`false` 表示正文
    /// 里没有该词（例如只命中标题），无需继续等待。
    func revealSearchMatch(_ query: String, documentID: UUID) -> Bool? {
        if let webView {
            guard webView.documentIdentity == documentID, webView.isDocumentReady else { return nil }
            guard webView.document.plainText.localizedCaseInsensitiveContains(query) else { return false }
            webView.perform("search", payload: ["query": query]); return true
        }
        guard let textView, textView.documentIdentity == documentID else { return nil }
        refreshStyle()
        return textView.revealSearchMatch(query)
    }

    /// 窗口失去 key（例如用户去滚 PDF）时，中文输入法可能还停在组合串；
    /// 先把未上屏内容提交给模型，避免切回来时丢字。
    func flushPendingComposition() {
        if let webView { webView.prepareForDocumentChange(); return }
        guard let textView, let coordinator else { return }
        coordinator.flushPendingComposition(in: textView)
    }

    func focusEnd() {
        if let webView { webView.focus(end: true); return }
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// 标题回车接力：光标落到正文第一行末尾；第一行空着时就是行首。
    func focusFirstLine() {
        if let webView { webView.focusFirstLine(); return }
        guard let textView else { return }
        let text = textView.string as NSString
        let newline = text.range(of: "\n")
        let end = newline.location == NSNotFound ? text.length : newline.location
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.window?.makeFirstResponder(textView)
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    func editLink() { if let webView { webView.editLink(); return }; textView?.editDocumentLink(nil); refreshStyle() }
    func removeLink() { if let webView { webView.perform("link", payload: ["value": NSNull()]); return }; textView?.removeDocumentLink(nil); refreshStyle() }
    func insertAttachment() { if let webView { webView.chooseAttachments(); return }; textView?.insertDocumentAttachment(nil); refreshStyle() }
    func insertImage() { if let webView { webView.chooseImage(); return }; textView?.insertDocumentImage(nil); refreshStyle() }
    func insertDiagram() { if let webView { webView.editDiagram(); return }; textView?.insertDocumentDiagram(at: nil); refreshStyle() }
    func insertTable() { if let webView { webView.insertTable(); return }; textView?.insertDocumentTable(at: nil); refreshStyle() }
    func insertFormula() { if let webView { webView.insertFormula(); return }; textView?.insertDocumentFormula(at: nil); refreshStyle() }
    func insertTime(format: String) {
        if let webView { let date = DateFormatter(); date.dateFormat = format; webView.perform("insertText", payload: ["text": date.string(from: Date())]); return }
        textView?.window?.makeFirstResponder(textView); textView?.insertDocumentTime(format: format); refreshStyle()
    }
    func insertDivider() { if let webView { webView.perform("insertDivider"); return }; textView?.window?.makeFirstResponder(textView); textView?.insertDocumentDivider(); refreshStyle() }
    func insertReference(_ reference: EditorReference) {
        if let webView {
            _ = webView.insert(NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [.init(text: reference.title, marks: [.link(reference.target)])])]))
            return
        }
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
        if let webView {
            return webView.insert(NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [.init(text: reference.title, marks: [.link(reference.target)])])]),
                commit: commit, inverse: undoCommit)
        }
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
        DocumentBodyFontSizeReader { bodyFontSize in
            if let ready = try? document.materialized() {
            MilkdownDocumentEditorView(documentID: documentID, document: ready,
                                  onDocumentChange: onDocumentChange, onEscape: onEscape,
                                  onEditingChanged: onEditingChanged, profile: profile,
                                  contentSized: contentSized, handle: handle,
                                  decorationVisibleMinX: decorationVisibleMinX,
                                  readOnly: readOnly, bodyFontSize: bodyFontSize)
                .padding(.leading, -DocumentEditorGeometry.decorationLane)
            } else {
                Text("正文读取失败，暂时无法编辑").foregroundStyle(.secondary)
            }
        }
    }
}

/// 正文默认字号来自设置页；`@AppStorage` 让已经打开的编辑器即时重排。
private struct DocumentBodyFontSizeReader<Content: View>: View {
    @AppStorage(EditorPreferences.bodyFontSizeKey)
    private var storedSize = Double(EditorPreferences.defaultBodyFontSize)
    @ViewBuilder var content: (CGFloat) -> Content

    var body: some View {
        content(EditorPreferences.clampedBodyFontSize(CGFloat(storedSize)))
    }
}
