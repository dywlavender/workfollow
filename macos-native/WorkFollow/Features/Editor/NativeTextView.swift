import AppKit
import ImageIO
import SwiftUI

final class NativeTextView: NSTextView {
    /// A content-sized editor delegates scrolling to its surrounding host.
    var usesHostScrollView = false
    /// Leading boundary visible inside the host's narrower decoration space.
    var decorationVisibleMinX: CGFloat = 0
    // The editor can rebind documents; reset clears its owned history.
    // Never share the window's undo history with another task or title field.
    private let documentUndoManager = UndoManager()
    private var ownedTextContentStorage: NSTextContentStorage?
    private(set) var storageRevision = 0
    private var storageObserver: Any?
    override var undoManager: UndoManager? { documentUndoManager }

    var onEscape: (() -> InspectorEscapeEffect)?
    /// 编辑器自己的临时状态（如格式刷）先吃掉 Esc；返回 true 表示已处理。
    var onCancelTransient: (() -> Bool)?
    var onEditingChanged: ((Bool) -> Void)?
    /// 选区或输入属性变了：工具条靠它刷新激活态（对齐原版 `_active` 的那条路）。
    var onSelectionChanged: (() -> Void)?
    /// 编辑区即时内容变了——输入法的组合串也算。`setMarkedText` 不走
    /// `NSTextViewDelegate.textDidChange`，占位文案只能靠这条通知即时让位。
    var onLiveTextChange: (() -> Void)?
    var profile = DocumentProfile()
    var slashSession: SlashSession?
    var slashPanel: NSPanel?
    /// `#` 标签补全（TI2-08）的会话与候选面板。
    var tagSession: TagCompletionSession?
    var tagPanel: NSPanel?
    /// 链接悬停菜单（TI2-08）：当前悬停的链接范围与浮层。
    var hoveredLinkRange: NSRange?
    var linkHoverPanel: NSPanel?
    /// 检查项提醒面板（行尾铃铛点开）。
    var checklistReminderPanel: ChecklistItemReminderPanel?
    /// 鼠标悬停的检查项行号；行尾铃铛/删除跟随悬停行显示（滴答 `TTHoverableImageView`）。
    var hoveredChecklistLine: Int?
    private var linkTrackingArea: NSTrackingArea?
    private var lastBoundsOrigin: NSPoint?
    /// 斜杠面板"跟着滚动与窗口变化走"用的通知观察者（见 `startFollowingSlash`）。
    var slashObservers: [Any] = []
    /// 文末那个"一个字符都没有"的空段落当前的待定段落类型。
    ///
    /// TextKit 把段落样式挂在字符上，而文末空段落没有字符——它的级别只活在
    /// `typingAttributes` 里。这里记下来交给模型（`DocumentTextCodec.decode(trailing:)`），
    /// 否则"在文末空行上选标题、不输入内容就切走"会丢掉级别；原版把行属性存在
    /// Delta 里，没有这个边界。
    var pendingTrailingBlock: DocumentBlockKind?
    /// 模型里文末空段的级别（协调器每次模型同步时刷新）。文末空段没有字符，
    /// 主循环装饰看不见它；列表标记的常驻绘制靠这个级别——光标不在行上时
    /// 项目符号/复选框也要显示。
    var displayedTrailingBlock: DocumentBlockKind?
    var displayedTrailingIndentLevel = 0
    var displayedTrailingListStart: Int?
    var displayedTrailingAlign: DocumentAlignment?
    var trailingIndentLevel: Int {
        pendingTrailingBlock != nil
            ? (typingAttributes[DocumentTextCodec.indentKey] as? Int ?? 0) : displayedTrailingIndentLevel
    }
    var trailingListStart: Int? {
        pendingTrailingBlock != nil
            ? typingAttributes[DocumentTextCodec.listStartKey] as? Int : displayedTrailingListStart
    }
    var trailingAlign: DocumentAlignment? {
        pendingTrailingBlock != nil
            ? (typingAttributes[DocumentTextCodec.alignKey] as? String)
                .flatMap(DocumentAlignment.init(rawValue:)) : displayedTrailingAlign
    }
    /// 输入期 Markdown 转换（块级/分割线/行内）的重入护栏：`applyFormat` 的
    /// 替换文本可能再次以触发字符结尾，不能让触发逻辑在替换过程中二次进入。
    var isApplyingTypedMarkdownInput = false

    /// 绑定文档时把模型里的文末级别带回输入属性（由协调器调用），这样切走再回来
    /// 接着在文末输入时，字号与级别都还在。
    func seedTrailingParagraphKind(_ kind: DocumentBlockKind?, indentLevel: Int = 0,
                                   listStart: Int? = nil, align: DocumentAlignment? = nil) {
        pendingTrailingBlock = kind
        displayedTrailingBlock = kind
        displayedTrailingIndentLevel = indentLevel
        displayedTrailingListStart = listStart
        displayedTrailingAlign = align
        guard let kind else { return }
        typingAttributes = DocumentTextCodec.attributes(kind: kind, marks: [],
            indentLevel: indentLevel, listStart: listStart, align: align)
    }
    var selectionPanel: NSPanel?
    var documentIdentity = UUID()
    var diagramEditor: DrawioEditorWindowController?
    var tableEditor: TableEditorWindowController?
    var formulaEditor: FormulaEditorWindowController?
    var needsHostCaretReveal = false
    /// A synchronous editor command may publish the document with host-owned
    /// fields in one commit. Never retained beyond that mutation.
    var documentCommandCommit: ((NativeDocument) -> Void)?
    var hasHostDocumentCommands = false

    /// Reopen the typing group only on actual input after an explicit command.
    /// An empty group must not consume a user's Undo.
    func prepareInputUndoGroup() {
        guard hasHostDocumentCommands, allowsUndo, let manager = undoManager,
              manager.isUndoRegistrationEnabled, manager.groupsByEvent,
              !manager.isUndoing, !manager.isRedoing, manager.groupingLevel == 0 else { return }
        manager.beginUndoGrouping()
        if manager.groupingLevel > 1 { manager.endUndoGrouping() }
    }

    /// Both document rebind and teardown use the same owned-state boundary.
    /// The coordinator must flush composition to the old document first.
    func resetDocumentInteraction(for documentID: UUID) {
        diagramEditor?.close()
        diagramEditor = nil
        tableEditor?.close()
        tableEditor = nil
        formulaEditor?.close()
        formulaEditor = nil
        dismissSlash()
        dismissSelectionToolbar()
        dismissChecklistReminderPanel()
        lastSelectionToolbarRange = NSRange(location: NSNotFound, length: 0)
        selectionAfterUndoRedo = nil
        pendingTrailingBlock = nil
        displayedTrailingBlock = nil
        displayedTrailingIndentLevel = 0
        displayedTrailingListStart = nil
        displayedTrailingAlign = nil
        hoveredChecklistLine = nil
        lastBoundsOrigin = nil
        needsHostCaretReveal = false
        documentCommandCommit = nil
        hasHostDocumentCommands = false
        documentIdentity = documentID
        undoManager?.removeAllActions()
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        prepareInputUndoGroup()
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onLiveTextChange?()
    }

    override func unmarkText() {
        super.unmarkText()
        onLiveTextChange?()
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let wasComposing = hasMarkedText()
        if !wasComposing,
           typingAttributes[DocumentTextCodec.completedChecklistPresentationKey] as? Bool == true,
           typingAttributes[DocumentTextCodec.blockKey] as? String != "checked" {
            let sample = NSAttributedString(string: " ", attributes: typingAttributes)
            let block = DocumentTextCodec.decode(sample, preserving: .empty).blocks.first
            typingAttributes = DocumentTextCodec.attributes(kind: block?.kind ?? .paragraph,
                                                            marks: block?.runs.first?.marks ?? [],
                                                            bodySize: block?.bodySize)
        }
        // 覆盖一段选中文本输入触发字符是普通编辑，不该开命令面板。
        let target = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        let replacedSelection = target.length > 0
        let insertedText = insertString as? String
        // 粘贴的富文本走 `NSAttributedString`：输入期转换按纯文本内容参与
        // （整串写入口径与块级一致，2026-10-16）；Slash 触发仍只认纯字符串输入。
        let inputText = insertedText ?? (insertString as? NSAttributedString)?.string
        let trigger: String? = insertedText.flatMap { inserted in
            ["/", "、"].first { $0 == inserted }
        }
        // 真有字进来了，段落样式就由字符承载，"文末待定级别"不再需要。
        if let inputText, !inputText.isEmpty { pendingTrailingBlock = nil }
        super.insertText(insertString, replacementRange: replacementRange)
        // 滴答同款 Markdown 输入期转换：块级前缀（空格结尾）与分割线
        // （2026-10-16 产品口径修订，实现见 `DocumentMarkdownInput.swift`）。
        if !wasComposing, !replacedSelection, let inputText, !inputText.isEmpty {
            applyTypedMarkdownInput(inputText)
        }
        // 渲染期重解析（2026-10-17 口径）：本次编辑所在段落里的历史字面一并渲染，
        // 不只"本次输入刚好补全"的那一处。
        if !wasComposing {
            reparseInlineMarkdown(paragraphs: [selectedRange()])
        }
        // `、` is commonly committed by a Chinese IME. Accept that committed
        // single-character insertion even if it replaces the IME's marked text;
        // ordinary replacement of a user selection remains a normal edit.
        let isIMETriggerCommit = wasComposing && trigger == "、"
        guard let trigger,
              (!wasComposing || isIMETriggerCommit),
              (!replacedSelection || isIMETriggerCommit) else {
            refreshSlash()
            return
        }
        let location = selectedRange().location
        let triggerLength = (trigger as NSString).length
        guard location >= triggerLength else { return }
        let triggerRange = NSRange(location: location - triggerLength, length: triggerLength)
        guard (string as NSString).substring(with: triggerRange) == trigger else { return }
        // A trigger attached to text (for example, a URL slash) is ordinary text.
        let prefix = (string as NSString).substring(to: triggerRange.location)
        guard prefix.isEmpty || prefix.last?.isWhitespace == true else { return }
        slashSession = SlashSession(start: triggerRange.location, trigger: trigger)
        refreshSlash()
    }

    override func didChangeText() {
        normalizeCompletedChecklistPresentation()
        restyleCodeBlocks()
        // 先同步文末空段的待定级别，delegate 的 commit 解码才能带上正确类型
        // （标题行回车后新行延续级别靠这一步）。
        syncPendingTrailingBlock()
        super.didChangeText()
        onLiveTextChange?()
        refreshSlash()
        refreshTagCompletion()
        hideLinkHoverMenu()
        // 行首标记活在文本区外的沟槽里（标题角标 / 空行"+"），文字变化不会
        // 自动把它标脏：段落类型变了要显式重绘。
        needsDisplay = true
        // The task editor grows inside the inspector's scroll view. Its own
        // clip view has nothing to scroll; reveal the caret in the host after
        // SwiftUI has applied the new document height.
        needsHostCaretReveal = true
    }

    /// 代码块语法着色（`CodeSyntaxHighlighter`）。只重排**光标所在代码段**，
    /// 并且只在颜色确实需要变时才写 storage——否则每次按键都会多一轮
    /// `didProcessEditing`，把提交节流和撤销粒度都搅乱。
    /// 全文档着色由 `DocumentTextCodec.render` 在加载时做。
    func restyleCodeBlocks() {
        guard !isRestylingCode, let storage = textStorage else { return }
        let source = storage.string as NSString
        guard source.length > 0 else { return }
        let caret = min(max(selectedRange().location, 0), source.length - 1)
        let paragraph = source.paragraphRange(for: NSRange(location: caret, length: 0))
        guard paragraph.length > 0,
              DocumentTextCodec.kind(storage.attribute(DocumentTextCodec.blockKey,
                  at: paragraph.location, effectiveRange: nil) as? String ?? "paragraph") == .code else { return }
        // 段尾换行不参与着色（它属于下一段的段落样式）。
        var range = paragraph
        if source.character(at: NSMaxRange(paragraph) - 1) == 0x0A { range.length -= 1 }
        guard range.length > 0 else { return }
        let language = CodeSyntaxHighlighter.Language.detect(in: source.substring(with: range))
        let appearance = effectiveAppearance
        let tokens = CodeSyntaxHighlighter.tokenize(source.substring(with: range), language: language)
        guard tokens.count == range.length else { return }
        var needsUpdate = false
        for (offset, token) in tokens.enumerated() where token != .plain {
            let expected = CodeSyntaxHighlighter.color(for: token, appearance: appearance)
            let current = storage.attribute(.foregroundColor, at: range.location + offset, effectiveRange: nil) as? NSColor
            if expected != nil, !Self.sameColor(current, expected) { needsUpdate = true; break }
        }
        guard needsUpdate else { return }
        isRestylingCode = true
        defer { isRestylingCode = false }
        CodeSyntaxHighlighter.apply(to: storage, range: range, language: language,
                                    baseColor: DocumentTextCodec.attributes(kind: .code, marks: [])[.foregroundColor]
                                        as? NSColor ?? .labelColor,
                                    appearance: appearance)
    }

    /// 主题色是按外观解析的 `NSColor`，直接 `==` 比不准（dynamic color 包装不同）。
    private static func sameColor(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        let left = lhs.usingColorSpace(.sRGB)
        let right = rhs.usingColorSpace(.sRGB)
        guard let left, let right else { return lhs == rhs }
        return abs(left.redComponent - right.redComponent) < 0.004
            && abs(left.greenComponent - right.greenComponent) < 0.004
            && abs(left.blueComponent - right.blueComponent) < 0.004
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        restyleAllCodeBlocks()
    }

    /// 代码块卡片必须落在文字下面：NSTextView 自身不画背景（`drawsBackground=false`），
    /// 所以在 super.draw 之前补一层填充，再让文字与语法着色压在上面。
    override func draw(_ dirtyRect: NSRect) {
        drawInlineCodeChips(in: dirtyRect)
        drawCodeBlockBackgrounds(in: dirtyRect)
        super.draw(dirtyRect)
    }

    /// 整篇重新着色（外观切换 / 加载完成时用）。
    func restyleAllCodeBlocks() {
        guard !isRestylingCode, let storage = textStorage, storage.length > 0 else { return }
        let source = storage.string as NSString
        let appearance = effectiveAppearance
        let base = DocumentTextCodec.attributes(kind: .code, marks: [])[.foregroundColor] as? NSColor ?? .labelColor
        var start = 0
        var ranges: [(NSRange, CodeSyntaxHighlighter.Language)] = []
        while start < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: start, length: 0))
            var range = paragraph
            if range.length > 0, source.character(at: NSMaxRange(range) - 1) == 0x0A { range.length -= 1 }
            if range.length > 0,
               DocumentTextCodec.kind(storage.attribute(DocumentTextCodec.blockKey,
                   at: range.location, effectiveRange: nil) as? String ?? "paragraph") == .code {
                ranges.append((range, CodeSyntaxHighlighter.Language.detect(in: source.substring(with: range))))
            }
            start = NSMaxRange(paragraph)
        }
        guard !ranges.isEmpty else { return }
        isRestylingCode = true
        defer { isRestylingCode = false }
        for (range, language) in ranges {
            CodeSyntaxHighlighter.apply(to: storage, range: range, language: language,
                                        baseColor: base, appearance: appearance)
        }
    }

    private func normalizeCompletedChecklistPresentation() {
        guard let storage = textStorage else { return }
        var inherited: [(NSRange, NSColor)] = []
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
            guard attributes[DocumentTextCodec.completedChecklistPresentationKey] as? Bool == true,
                  attributes[DocumentTextCodec.blockKey] as? String != "checked" else { return }
            let kind = DocumentTextCodec.kind(attributes[DocumentTextCodec.blockKey] as? String ?? "paragraph")
            let color = DocumentTextCodec.attributes(kind: kind, marks: [])[.foregroundColor] as? NSColor ?? .labelColor
            inherited.append((range, color))
        }
        guard !inherited.isEmpty else { return }
        storage.beginEditing()
        for (range, color) in inherited {
            storage.removeAttribute(.strikethroughStyle, range: range)
            storage.removeAttribute(DocumentTextCodec.completedChecklistPresentationKey, range: range)
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }
        storage.endEditing()
    }

    /// 光标停在文末空段时，把"接下来输入的类型"记进 `pendingTrailingBlock`
    /// （该段没有字符，级别只活在输入属性里，模型解码靠它定类型）；
    /// 离开文末空段就清掉。标题/列表换行延续、切走再切回不丢级别都靠它。
    func syncPendingTrailingBlock() {
        guard let storage = textStorage else { return }
        let source = storage.string as NSString
        let caret = min(max(selectedRange().location, 0), source.length)
        let atTrailingEmpty = source.length == 0
            || (caret == source.length && source.character(at: source.length - 1) == 0x0A)
        if atTrailingEmpty {
            pendingTrailingBlock = DocumentTextCodec.kind(
                typingAttributes[DocumentTextCodec.blockKey] as? String ?? "paragraph")
        } else {
            pendingTrailingBlock = nil
        }
    }

    /// 空的标题/列表/引用/代码行上按回车 → 退回正文（滴答/Quill 同款：再按一次回车
    /// 退出格式），返回是否已处理。有内容的行回车会延续格式，不走这里。
    func exitEmptyBlockOnNewline() -> Bool {
        guard isEditable, !hasMarkedText(), let storage = textStorage else { return false }
        let source = storage.string as NSString
        let caret = min(max(selectedRange().location, 0), source.length)
        let trailingEmpty = source.length == 0
            || (caret == source.length && source.character(at: source.length - 1) == 0x0A)
        let plain = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        // 可退出的块：标题、三类列表（有序/无序/检查项）、引用与代码块。
        func isExitable(_ kind: DocumentBlockKind) -> Bool {
            switch kind {
            case .heading, .bullet, .ordered, .checklist, .quote, .code: return true
            default: return false
            }
        }
        if trailingEmpty {
            // 文末空段：级别只活在输入属性里，直接退回正文，不用改存储。
            guard isExitable(DocumentTextCodec.kind(
                typingAttributes[DocumentTextCodec.blockKey] as? String ?? "paragraph")) else { return false }
            replaceEmptyBlock(range: NSRange(location: caret, length: 0),
                              content: NSAttributedString(string: ""),
                              typing: plain, trailing: nil)
            return true
        }
        let paragraph = source.paragraphRange(for: NSRange(location: caret, length: 0))
        guard paragraph.length > 0 else { return false }
        let lastCharacter = source.character(at: NSMaxRange(paragraph) - 1)
        let contentLength = paragraph.length - (lastCharacter == 0x0A ? 1 : 0)
        guard contentLength == 0,
              let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                            effectiveRange: nil) as? String,
              isExitable(DocumentTextCodec.kind(token)) else { return false }
        // 中间的空行：整段（含段尾换行）重设为正文属性，不新增行。
        replaceEmptyBlock(range: paragraph,
                          content: NSAttributedString(string: storage.attributedSubstring(from: paragraph).string,
                                                      attributes: plain),
                          typing: plain, trailing: nil)
        return true
    }

    /// 空段落的格式也是一次编辑；字符没有增减时 NSTextView 不会自动记录它。
    func replaceEmptyBlock(range: NSRange, content: NSAttributedString,
                                   typing: [NSAttributedString.Key: Any],
                                   trailing: DocumentBlockKind?) {
        guard let storage = textStorage else { return }
        let previous = storage.attributedSubstring(from: range)
        let previousTyping = typingAttributes
        let previousTrailing = pendingTrailingBlock
        let selection = selectedRange()
        breakUndoCoalescing()
        documentUndoManager.registerUndo(withTarget: self) { view in
            view.replaceEmptyBlock(range: range, content: previous,
                                   typing: previousTyping, trailing: previousTrailing)
        }
        if range.length > 0 {
            storage.replaceCharacters(in: range, with: content)
            invalidateDocumentLayout(for: range)
        }
        setSelectedRange(selection)
        typingAttributes = typing
        pendingTrailingBlock = trailing
        displayedTrailingBlock = trailing
        needsDisplay = true
        // 空行换块可能不增删字符，存储变更通知不会来，装饰层要自己重绘。
        decorationOverlay?.needsDisplay = true
        didChangeText()
    }

    func revealCaretInHostAfterLayout() {
        guard needsHostCaretReveal else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.firstResponder === self,
                  let inner = self.enclosingScrollView,
                  let window = self.window else { return }
            window.contentView?.layoutSubtreeIfNeeded()
            if self.usesHostScrollView {
                self.scrollRangeToVisible(self.selectedRange())
                self.needsHostCaretReveal = false
                return
            }
            guard !inner.hasVerticalScroller else { return }
            var ancestor = inner.superview
            while let view = ancestor {
                if let outer = view as? NSScrollView, let document = outer.documentView {
                    let screenRect = self.firstRect(forCharacterRange: self.selectedRange(), actualRange: nil)
                    let caret = document.convert(window.convertFromScreen(screenRect), from: nil)
                    document.scrollToVisible(caret.insetBy(dx: 0, dy: -12))
                    self.needsHostCaretReveal = false
                    break
                }
                ancestor = view.superview
            }
        }
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        guard usesHostScrollView, let window,
              let document = enclosingScrollView?.documentView else {
            super.scrollRangeToVisible(range)
            return
        }
        let screenRect = firstRect(forCharacterRange: range, actualRange: nil)
        let rect = document.convert(window.convertFromScreen(screenRect), from: nil)
        document.scrollToVisible(rect.insetBy(dx: 0, dy: -12))
    }

    func invalidateDocumentLayout(for range: NSRange) {
        if let contentStorage = ownedTextContentStorage,
           let textLayoutManager {
            textLayoutManager.invalidateLayout(for: contentStorage.documentRange)
            needsDisplay = true
            return
        }
        layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let linkTrackingArea { removeTrackingArea(linkTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited,
                                            .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        linkTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if isPointerOverSiblingOverlay(event.locationInWindow) {
            // 格式工具条叠在正文上方，跟踪区仍会收到 mouseMoved；留箭头。
            updateChecklistHover(at: nil)
            NSCursor.arrow.set()
            hideLinkHoverMenu()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        updateChecklistHover(at: point)
        guard isEditable else { hideLinkHoverMenu(); return }
        guard let range = linkRange(at: point) else { hideLinkHoverMenu(); return }
        guard range != hoveredLinkRange || linkHoverPanel == nil else { return }
        hoveredLinkRange = range
        showLinkHoverMenu(for: range)
    }

    /// 指针是不是落在叠在正文上的兄弟视图里（格式工具条等）。
    ///
    /// 跟踪区是 `.inVisibleRect`，覆盖整个可见区——包括浮在正文上方的工具条。
    /// 命中测试能区分"真的在正文上"与"工具条盖住了正文"。
    private func isPointerOverSiblingOverlay(_ windowPoint: NSPoint) -> Bool {
        guard let window, let content = window.contentView,
              let hit = content.hitTest(windowPoint) else { return false }
        if hit === self || hit.isDescendant(of: self) { return false }
        // 正文外的空白命中层仍是编辑区域，保留它自己的 I-beam。
        if hit is EditorWhitespaceHitTarget.TargetView { return false }
        return true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideLinkHoverMenu()
        updateChecklistHover(at: nil)
    }

    /// 悬停行的铃铛/删除是行级控件，不改变光标；只在清单任务里启用。
    func updateChecklistHover(at point: NSPoint?) {
        let target = point.flatMap { checklistHoverTarget(at: $0) }
        let line = profile.checklistRemindersEnabled ? target?.line : nil
        let overCheckbox = point.map { point in
            target.map { checklistMarkerRect(for: $0).contains(point) } ?? false
        } ?? false
        let overGutter = point.map { blockMenuTarget(at: $0) != nil } ?? false
        // 检查项是整行操作（勾选/提醒/删除），鼠标用箭头而不是文本 I-beam。
        // 笔记里的检查项没有行尾控件，只把复选框本身和行首沟槽标成可点。
        if line != nil || overCheckbox || overGutter {
            NSCursor.arrow.set()
        } else if point != nil, isEditable {
            NSCursor.iBeam.set()
        } else {
            // 指针离开正文（例如移到下方工具条/页脚）不能把 I-beam 留在按钮上。
            NSCursor.arrow.set()
        }
        guard hoveredChecklistLine != line else { return }
        hoveredChecklistLine = line
        decorationOverlay?.needsDisplay = true
        needsDisplay = true
    }

    private struct ChecklistHoverTarget {
        let line: Int
        let firstLine: NSRect
    }

    /// 光标下的字符所在行决定命中；行首矩形只用于复选框位置。
    /// 这样长检查项换行后的第二视觉行也仍属于同一项。
    private func checklistHoverTarget(at point: NSPoint) -> ChecklistHoverTarget? {
        guard isEditable, let storage = textStorage, storage.length > 0 else { return nil }
        let offset = min(characterIndexForInsertion(at: point), storage.length - 1)
        let paragraph = (string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
        guard let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                            effectiveRange: nil) as? String,
              token == "checklist" || token == "checked",
              let characterRect = viewRect(forCharacterAt: offset) else { return nil }
        guard point.y >= characterRect.minY - DocumentEditorGeometry.checklistRowSpacing / 2,
              point.y <= characterRect.maxY + DocumentEditorGeometry.checklistRowSpacing / 2 else { return nil }
        let firstLine = viewRect(forCharacterAt: paragraph.location) ?? characterRect
        return ChecklistHoverTarget(line: checklistLineIndex(for: paragraph.location),
                                    firstLine: firstLine)
    }

    private func checklistMarkerRect(for target: ChecklistHoverTarget) -> NSRect {
        NSRect(x: target.firstLine.minX - 28, y: target.firstLine.minY,
               width: 28, height: target.firstLine.height)
    }

    private func updateChecklistHoverFromMouse() {
        guard let window, window.isKeyWindow else { updateChecklistHover(at: nil); return }
        let windowPoint = window.mouseLocationOutsideOfEventStream
        if isPointerOverSiblingOverlay(windowPoint) {
            updateChecklistHover(at: nil)
            NSCursor.arrow.set()
            return
        }
        let point = convert(windowPoint, from: nil)
        updateChecklistHover(at: bounds.contains(point) ? point : nil)
    }

    override func mouseDown(with event: NSEvent) {
        dismissSlash()
        dismissTagCompletion()
        hideLinkHoverMenu()
        dismissChecklistReminderPanel()
        if openBlockMenu(at: convert(event.locationInWindow, from: nil)) { return }
        // 文档复选框在任务与笔记两个面都可点（原版 `DocumentCheckboxBuilder` 挂在
        // 共享文档样式上，不分面）。
        if isEditable, let window, let storage = textStorage, storage.length > 0 {
            let point = convert(event.locationInWindow, from: nil)
            let offset = min(characterIndexForInsertion(at: point), storage.length - 1)
            let paragraph = (string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
            let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location, effectiveRange: nil) as? String
            if (token == "checklist" || token == "checked"),
               let caret = viewRect(forCharacterAt: paragraph.location) {
                // 行尾删除按钮（TI2-05a）优先于行首复选框：两者不会重叠，但顺序固定。
                if checklistDeleteHitRect(centerY: caret.midY).contains(point) {
                    window.makeFirstResponder(self)
                    deleteChecklistItem(at: paragraph)
                    return
                }
                if profile.checklistRemindersEnabled,
                   checklistReminderHitRect(centerY: caret.midY).contains(point) {
                    presentChecklistReminderPanel(
                        lineIndex: checklistLineIndex(for: paragraph.location),
                        centerY: caret.midY)
                    return
                }
                let marker = NSRect(x: caret.minX - 28, y: caret.minY, width: 28, height: caret.height)
                if marker.contains(point) {
                    // 勾选是行内动作：不抢焦点、不移动插入点，避免视图滚回顶部。
                    toggleNoteChecklist(at: paragraph.location)
                    return
                }
            }
            // 文末空段的检查项没有字符可读 token：级别活在待定/模型状态里，
            // 点中标记区按它翻转（显示已支持，这里补点击）。
            let trailingKind = pendingTrailingBlock ?? displayedTrailingBlock
            if token != "checklist", token != "checked",
               case .checklist(let checked) = trailingKind,
               let caret = viewRect(forCharacterAt: storage.length) {
                let marker = NSRect(x: caret.minX - 28, y: caret.minY, width: 28, height: caret.height)
                if marker.contains(point) {
                    setTrailingChecklist(checked: !checked)
                    return
                }
            }
        }
        // Explicitly own editable clicks when hosted beside SwiftUI fields.
        // NSTextView's tracking/selection must run with this view as responder,
        // not the outgoing SwiftUI field editor.
        if isEditable { window?.makeFirstResponder(self) }
        super.mouseDown(with: event)
    }

    /// The plus is a menu trigger, not document content. Reuse a zero-length
    /// Slash session so selecting/cancelling never introduces a literal slash.
    @discardableResult
    // MARK: 检查项整项操作（TI2-05a）

    /// 检查项行尾的删除按钮矩形（与 `drawChecklistDeleteGlyph` 共用同一几何）。
    /// 滴答 nib：24×24 按钮，距右缘约 10pt。
    func checklistDeleteHitRect(centerY: CGFloat) -> NSRect {
        NSRect(x: bounds.maxX - 34, y: centerY - 12, width: 24, height: 24)
    }

    /// 铃铛在删除按钮左侧，两个 24pt 命中区间隔 2pt。
    func checklistReminderHitRect(centerY: CGFloat) -> NSRect {
        NSRect(x: bounds.maxX - 60, y: centerY - 12, width: 24, height: 24)
    }

    /// 行号以换行切分，与 `NativeDocument.blocks` 的顺序一致。
    func checklistLineIndex(for location: Int) -> Int {
        guard let storage = textStorage else { return 0 }
        let source = storage.string as NSString
        let bounded = max(0, min(location, source.length))
        guard bounded > 0 else { return 0 }
        var count = 0
        for index in 0..<bounded where source.character(at: index) == 0x0A {
            count += 1
        }
        return count
    }

    /// 行号对应的字符区间（不含行尾换行之外的内容）。越界返回 nil。
    func characterRange(forChecklistLine line: Int) -> NSRange? {
        guard let storage = textStorage, line >= 0 else { return nil }
        let source = storage.string as NSString
        if source.length == 0 { return line == 0 ? NSRange(location: 0, length: 0) : nil }
        var current = 0
        var offset = 0
        while offset < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: offset, length: 0))
            if current == line { return paragraph }
            let next = NSMaxRange(paragraph)
            guard next > offset else { break }
            offset = next
            current += 1
        }
        // 文末空段：没有字符，但模型里仍是最后一行。
        if current == line, source.hasSuffix("\n") {
            return NSRange(location: source.length, length: 0)
        }
        return nil
    }

    /// VoiceOver 读出的检查项描述；非检查项行返回 nil。
    /// 正文本身由 NSTextView 朗读，这里补上"已完成/有提醒"这层状态。
    func checklistAccessibilityLabel(forLine line: Int) -> String? {
        guard let storage = textStorage,
              let paragraph = characterRange(forChecklistLine: line) else { return nil }
        let token = paragraph.location < storage.length
            ? storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location, effectiveRange: nil) as? String
            : nil
        guard token == "checklist" || token == "checked" else { return nil }
        let text = (storage.string as NSString).substring(with: paragraph)
            .trimmingCharacters(in: .newlines)
        let title = text.isEmpty ? "空检查事项" : text
        var label = "检查事项：\(title)，" + (token == "checked" ? "已完成" : "未完成")
        if profile.checklistItem(line)?.reminderAt != nil { label += "，有提醒" }
        return label
    }

    /// VoiceOver 聚焦正文时，若光标停在检查项上就读出这一项的完成态/提醒；
    /// 普通正文仍交给 NSTextView 原生的整段朗读。
    override func accessibilityLabel() -> String? {
        if let paragraph = activeChecklistParagraph(),
           let label = checklistAccessibilityLabel(forLine: checklistLineIndex(for: paragraph.location)) {
            return label
        }
        return super.accessibilityLabel()
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions = super.accessibilityCustomActions() ?? []
        guard let paragraph = activeChecklistParagraph(),
              let storage = textStorage,
              let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                            effectiveRange: nil) as? String else { return actions }
        let checked = token == "checked"
        actions.append(NSAccessibilityCustomAction(name: checked ? "取消勾选" : "勾选") { [weak self] in
            guard let self else { return false }
            self.toggleNoteChecklist(at: paragraph.location)
            return true
        })
        guard profile.checklistRemindersEnabled else { return actions }
        let line = checklistLineIndex(for: paragraph.location)
        let reminder = NSAccessibilityCustomAction(name: "设置检查事项提醒") { [weak self] in
            guard let self else { return false }
            self.presentChecklistReminderPanel(
                lineIndex: line,
                centerY: self.viewRect(forCharacterAt: paragraph.location)?.midY ?? self.bounds.midY)
            return true
        }
        let delete = NSAccessibilityCustomAction(name: "删除检查事项") { [weak self] in
            guard let self else { return false }
            return self.deleteChecklistItem(at: paragraph)
        }
        actions.append(contentsOf: [reminder, delete])
        return actions
    }

    func activeChecklistParagraph() -> NSRange? {
        guard isEditable, let storage = textStorage, storage.length > 0 else { return nil }
        let source = storage.string as NSString
        let caret = min(max(selectedRange().location, 0), source.length)
        let anchor = min(caret, source.length - 1)
        let paragraph = source.paragraphRange(for: NSRange(location: anchor, length: 0))
        let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                      effectiveRange: nil) as? String
        return token == "checklist" || token == "checked" ? paragraph : nil
    }

    /// 通知点开项提醒后定位：滚动到该行、落光标，并用系统查找指示闪一下。
    func revealChecklistLine(_ line: Int) {
        guard let paragraph = characterRange(forChecklistLine: line) else { return }
        window?.makeFirstResponder(self)
        let target = NSRange(location: paragraph.location, length: 0)
        setSelectedRange(target)
        scrollRangeToVisible(target)
        guard paragraph.length > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.firstResponder === self else { return }
            self.showFindIndicator(for: paragraph)
        }
    }

    func presentChecklistReminderPanel(lineIndex: Int, centerY: CGFloat) {
        guard let window else { return }
        dismissChecklistReminderPanel()
        // 组合串先落字：提醒写入的是模型，不能把未上屏的输入留在编辑器里。
        if hasMarkedText() { unmarkText() }
        let current = profile.checklistItem(lineIndex)?.reminderAt
        let anchor = window.convertToScreen(convert(
            checklistReminderHitRect(centerY: centerY), to: nil))
        let panel = ChecklistItemReminderPanel(anchor: anchor, owner: window,
            now: Date(), calendar: .current, current: current,
            notice: profile.checklistReminderNotice()) { [weak self] date in
                guard let self else { return }
                self.profile.setChecklistReminder(lineIndex, date)
                self.needsDisplay = true
            } onDismiss: { [weak self] in
                // Outside clicks / Esc dismiss through the shared registry; the
                // text view's pointer must not outlive the window.
                self?.checklistReminderPanel = nil
            }
        checklistReminderPanel = panel
    }

    func dismissChecklistReminderPanel() {
        checklistReminderPanel?.dismiss()
        checklistReminderPanel = nil
    }

    /// 删除整项：段落区间（含行尾换行）整段移除，光标落到被删位置。
    @discardableResult
    func deleteChecklistItem(at paragraph: NSRange) -> Bool {
        guard isEditable, let storage = textStorage, paragraph.length > 0 else { return false }
        let source = storage.string as NSString
        var range = paragraph
        let endsWithNewline = source.character(at: NSMaxRange(paragraph) - 1) == 0x0A
        // 末行没有换行：连同前面的换行一起删，避免留下空行。
        if !endsWithNewline, range.location > 0 {
            range.location -= 1
            range.length += 1
        }
        insertText("", replacementRange: range)
        let length = (string as NSString).length
        setSelectedRange(NSRange(location: min(range.location, length), length: 0))
        return true
    }

    /// 空检查项行首退格：返回 true 表示已作为"删项"处理，不再走普通退格。
    func deleteEmptyChecklistItemOnBackspace() -> Bool {
        guard isEditable, !hasMarkedText(), let storage = textStorage else { return false }
        let source = storage.string as NSString
        guard source.length > 0 else { return false }
        let selection = selectedRange()
        guard selection.length == 0 else { return false }
        let location = min(max(selection.location, 0), source.length)
        let anchor = min(location, source.length - 1)
        let paragraph = source.paragraphRange(for: NSRange(location: anchor, length: 0))
        guard location <= paragraph.location else { return false }
        let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                      effectiveRange: nil) as? String
        guard token == "checklist" || token == "checked" else { return false }
        let lastCharacter = source.character(at: NSMaxRange(paragraph) - 1)
        let contentLength = paragraph.length - (lastCharacter == 0x0A ? 1 : 0)
        guard contentLength == 0 else { return false }
        return deleteChecklistItem(at: paragraph)
    }

    /// 行首沟槽的块菜单（TI2-21）：空行的"+"、正文行的六点手柄、标题行的 H 角标
    /// 都落在这一列，点开都走同一个块类型菜单（Slash 面板的空查询态）。
    ///
    /// 列表 / 检查项 / 引用 / 代码行的行首标记另有职责（复选框翻转等），这里不接管。
    func openBlockMenu(at point: NSPoint) -> Bool {
        guard let target = blockMenuTarget(at: point), let window else { return false }
        window.makeFirstResponder(self)
        setSelectedRange(NSRange(location: target.paragraph.location, length: 0))
        slashSession = SlashSession(start: target.paragraph.location, trigger: "", scope: .block)
        refreshSlash()
        return true
    }

    /// 行首沟槽的块菜单命中（不触发副作用），供点击与光标共用。
    private func blockMenuTarget(at point: NSPoint) -> (paragraph: NSRange, caret: NSRect)? {
        guard isEditable, window != nil, let storage = textStorage else { return nil }
        let markerX = DocumentEditorGeometry.decorationMarkerX(visibleMinX: decorationVisibleMinX)
        guard point.x >= markerX - 2, point.x <= markerX + 10 else { return nil }
        let source = storage.string as NSString
        // 命中"点中的那一行"而不是光标所在行：用户会去点自己看到的那一行，
        // 光标不在那里时也应照常打开。沟槽的 x 在文本容器之外，TextKit 的
        // `characterIndexForInsertion` 在那里会失真（实测恒返回 0），所以先按
        // 段落首/末字符的行矩形做 y 命中，落空再退回插入点。
        let paragraph: NSRange
        if let matched = self.paragraph(forGutterClick: point, source: source) {
            paragraph = matched
        } else {
            let clicked = characterIndexForInsertion(at: point)
            let anchor = source.length == 0 ? 0 : min(max(clicked, 0), source.length - 1)
            paragraph = source.length == 0
                ? NSRange(location: 0, length: 0)
                : source.paragraphRange(for: NSRange(location: anchor, length: 0))
        }
        let kind = paragraph.location < storage.length
            ? DocumentTextCodec.kind(storage.attribute(DocumentTextCodec.blockKey,
                at: paragraph.location, effectiveRange: nil) as? String ?? "paragraph")
            : pendingTrailingBlock ?? displayedTrailingBlock ?? .paragraph
        switch kind {
        case .paragraph, .heading:
            break
        case .bullet, .ordered, .checklist, .quote, .code, .divider:
            return nil
        }
        guard let caret = viewRect(forCharacterAt: paragraph.location) else { return nil }
        let hit = NSRect(x: markerX - 2, y: caret.minY, width: 12, height: caret.height)
        guard hit.contains(point) else { return nil }
        return (paragraph, caret)
    }

    /// 沟槽点击落在哪一段（y 命中段落首/末字符的行矩形；文末空段用它自己的插入点矩形）。
    private func paragraph(forGutterClick point: NSPoint, source: NSString) -> NSRange? {
        func contains(_ rect: NSRect?) -> Bool {
            guard let rect else { return false }
            return point.y >= rect.minY - 2 && point.y <= rect.maxY + 2
        }
        if source.length == 0 {
            return contains(viewRect(forCharacterAt: 0)) ? NSRange(location: 0, length: 0) : nil
        }
        var offset = 0
        while offset < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: offset, length: 0))
            let lastIndex = max(paragraph.location, NSMaxRange(paragraph) - 1)
            if let first = viewRect(forCharacterAt: paragraph.location),
               let last = viewRect(forCharacterAt: lastIndex) {
                let top = min(first.minY, last.minY) - 2
                let bottom = max(first.maxY, last.maxY) + 2
                if point.y >= top, point.y <= bottom { return paragraph }
            }
            offset = NSMaxRange(paragraph)
        }
        if source.hasSuffix("\n"), contains(viewRect(forCharacterAt: source.length)) {
            return NSRange(location: source.length, length: 0)
        }
        return nil
    }

    /// 文末空段的检查项翻转：无字符可改，直接改输入属性与待定级别并注册撤销；
    /// 光标同时落到文末（级别只有这样才会随下一次 commit 进模型）。
    func setTrailingChecklist(checked: Bool) {
        applyTrailingState(typing: DocumentTextCodec.attributes(kind: .checklist(checked), marks: [],
                                                              indentLevel: trailingIndentLevel),
                           trailing: .checklist(checked))
    }

    private func applyTrailingState(typing: [NSAttributedString.Key: Any], trailing: DocumentBlockKind?) {
        guard let storage = textStorage else { return }
        let previousTyping = typingAttributes
        let previousTrailing = pendingTrailingBlock
        breakUndoCoalescing()
        documentUndoManager.registerUndo(withTarget: self) { view in
            view.applyTrailingState(typing: previousTyping, trailing: previousTrailing)
        }
        typingAttributes = typing
        pendingTrailingBlock = trailing
        displayedTrailingBlock = trailing
        setSelectedRange(NSRange(location: storage.length, length: 0))
        needsDisplay = true
        didChangeText()
    }

    /// 勾选/取消检查项只改段落属性，不替换文字。整段替换会让 NSTextView
    /// 把插入点移到替换处并滚动到那里，表现为“点一下就跳回最上面”。
    func toggleNoteChecklist(at offset: Int) {
        guard let storage = textStorage, offset >= 0, offset < storage.length else { return }
        let paragraph = (string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
        guard let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                            effectiveRange: nil) as? String,
              token == "checklist" || token == "checked" else { return }
        applyChecklistPresentation(checked: token == "checklist", to: paragraph)
    }

    private func applyChecklistPresentation(checked: Bool, to paragraph: NSRange) {
        guard let storage = textStorage, paragraph.length > 0 else { return }
        let previous = storage.attributedSubstring(from: paragraph)
        let selection = selectedRange()
        let previousTyping = typingAttributes
        let caretInside = selection.location >= paragraph.location
            && selection.location <= NSMaxRange(paragraph)
        breakUndoCoalescing()
        documentUndoManager.registerUndo(withTarget: self) { [weak self] view in
            view.restoreChecklistParagraph(previous, at: paragraph.location, typing: previousTyping)
        }
        applyChecklistAttributes(checked: checked, to: paragraph, in: storage)
        setSelectedRange(selection)
        if caretInside, selection.location < storage.length {
            typingAttributes = storage.attributes(at: selection.location, effectiveRange: nil)
        } else {
            typingAttributes = previousTyping
        }
        needsDisplay = true
        didChangeText()
    }

    private func applyChecklistAttributes(checked: Bool, to range: NSRange, in storage: NSTextStorage) {
        let kind = DocumentBlockKind.checklist(checked)
        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
        storage.enumerateAttributes(in: range) { attributes, runRange, _ in
            runs.append((runRange, attributes))
        }
        storage.beginEditing()
        for (runRange, attributes) in runs {
            var updated = attributes
            updated[DocumentTextCodec.blockKey] = DocumentTextCodec.blockToken(kind)
            updated[.foregroundColor] = checked
                ? NSColor(WFColors.taskCompletedTitle) : NSColor.labelColor
            // 勾选态的删除线是展示层（切回文本时才加），这里统一清掉，
            // 避免取消勾选后残留。
            updated.removeValue(forKey: .strikethroughStyle)
            updated.removeValue(forKey: DocumentTextCodec.completedChecklistPresentationKey)
            storage.setAttributes(updated, range: runRange)
        }
        storage.endEditing()
    }

    /// 撤销/重做只还原这一段属性；文字与选区长度不变。
    private func restoreChecklistParagraph(_ value: NSAttributedString, at location: Int,
                                           typing: [NSAttributedString.Key: Any]) {
        guard let storage = textStorage,
              location >= 0, location + value.length <= storage.length else { return }
        let range = NSRange(location: location, length: value.length)
        let current = storage.attributedSubstring(from: range)
        documentUndoManager.registerUndo(withTarget: self) { [weak self] view in
            view.restoreChecklistParagraph(current, at: location, typing: typing)
        }
        let selection = selectedRange()
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: value)
        storage.endEditing()
        setSelectedRange(selection)
        typingAttributes = typing
        needsDisplay = true
        didChangeText()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            dismissSlash()
            dismissTagCompletion()
            hideLinkHoverMenu()
            dismissSelectionToolbar()
            dismissChecklistReminderPanel()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func deleteBackward(_ sender: Any?) {
        if outdentListAtParagraphStart() { return }
        // 空检查项行首退格 = 删掉这一项（滴答 `deleteChecklistItemCell:viaBackspace:`）。
        if deleteEmptyChecklistItemOnBackspace() { return }
        super.deleteBackward(sender)
    }

    override func keyDown(with event: NSEvent) {
        // Input sources can dispatch Shift+Tab as insertTab:. Read the actual
        // key modifiers before that translation, keeping IME/system chords native.
        if event.keyCode == 48,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           changeListIndent(by: event.modifierFlags.contains(.shift) ? -1 : 1) { return }
        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        // 提醒面板开着时 Esc 先收起面板，不把 Esc 传给上层检查器。
        if selector == #selector(cancelOperation(_:)), checklistReminderPanel != nil, !hasMarkedText() {
            dismissChecklistReminderPanel()
            return
        }
        // 标签候选优先于普通回车/Esc（面板开着时这三个键归面板）。
        if tagSession != nil, !hasMarkedText() {
            switch selector {
            case #selector(moveUp(_:)): moveTagCompletion(-1); return
            case #selector(moveDown(_:)): moveTagCompletion(1); return
            case #selector(insertNewline(_:)): commitTagCompletion(); return
            case #selector(cancelOperation(_:)): dismissTagCompletion(); return
            default: break
            }
        }
        if slashSession != nil, !hasMarkedText() {
            switch selector {
            case #selector(moveUp(_:)): moveSlash(-1); return
            case #selector(moveDown(_:)): moveSlash(1); return
            case #selector(insertNewline(_:)): executeSlash(); return
            case #selector(cancelOperation(_:)): dismissSlash(); return
            default: break
            }
        }
        if selector == #selector(insertTab(_:)), changeListIndent(by: 1) { return }
        if selector == #selector(insertBacktab(_:)), changeListIndent(by: -1) { return }
        if selector == #selector(insertNewline(_:)), handleListNewline() { return }
        // 空格式行上回车：退回正文（有内容的行回车会延续格式，不受影响）。
        if selector == #selector(insertNewline(_:)), !hasMarkedText(),
           exitEmptyBlockOnNewline() { return }
        super.doCommand(by: selector)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        // 只读预览保留复制/选择，不提供任何格式命令。
        guard isEditable else { return menu }
        let formatting = NSMenuItem(title: "格式", action: nil, keyEquivalent: "")
        formatting.submenu = formatMenu()
        menu?.addItem(formatting)
        if selectedRange().length > 0, !profile.selectionActions.isEmpty {
            menu?.addItem(.separator())
            for (index, action) in profile.selectionActions.enumerated() {
                let item = NSMenuItem(title: action.title, action: #selector(invokeSelectionAction(_:)), keyEquivalent: "")
                item.tag = index
                item.target = self
                menu?.addItem(item)
            }
        }
        return menu
    }

    @objc private func invokeSelectionAction(_ sender: NSMenuItem) {
        let range = selectedRange()
        guard range.length > 0, NSMaxRange(range) <= (string as NSString).length else { return }
        guard profile.selectionActions.indices.contains(sender.tag) else { return }
        profile.selectionActions[sender.tag].perform((string as NSString).substring(with: range))
    }

    // MARK: - 选区浮动工具条（迁移自 Flutter DocumentSelectionToolbar；笔记 profile）

    /// Escape 或调用动作后压住浮条，直到选区再次变化（Flutter 的 selectionOverlaySuppressed）。
    var selectionToolbarSuppressed = false
    private var lastSelectionToolbarRange = NSRange(location: NSNotFound, length: 0)

    /// 选区变化时由协调器调用；非空选区 + 笔记 profile（有选区动作、非任务文档）浮现。
    func refreshSelectionToolbar() {
        let range = selectedRange()
        if range != lastSelectionToolbarRange {
            lastSelectionToolbarRange = range
            selectionToolbarSuppressed = false
        }
        // 只读预览里选字只用于复制，不弹可修改格式的浮条。
        let eligible = isEditable && window != nil && !hasMarkedText() && range.length > 0
            && profile.supportsSelectionToolbar
            && !profile.selectionActions.isEmpty && NSMaxRange(range) <= (string as NSString).length
        guard eligible, !selectionToolbarSuppressed else {
            closeSelectionPanel()
            return
        }
        showSelectionPanel(for: range)
    }

    /// 压住并关闭（Escape、执行动作、文档切换）。
    func dismissSelectionToolbar() {
        selectionToolbarSuppressed = true
        closeSelectionPanel()
    }

    func closeSelectionPanel() {
        if let panel = selectionPanel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        selectionPanel = nil
    }

    private func showSelectionPanel(for range: NSRange) {
        guard let window else { return }
        let panel: NSPanel
        if let existing = selectionPanel {
            panel = existing
        } else {
            panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.hasShadow = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.appearance = window.effectiveAppearance
            EditorPopupWindowLevel.apply(to: panel, owner: window)
            window.addChildWindow(panel, ordered: .above)
            selectionPanel = panel
        }
        let root = selectionToolbarRoot(for: range)
        // 换颜色后只换 rootView：保住浮条宿主与子面板锚点，不闪一下重建整条。
        if let host = panel.contentView as? NSHostingView<DocumentSelectionToolbarView> {
            host.rootView = root
        } else {
            panel.contentView = NSHostingView(rootView: root)
        }
        let content = panel.contentView ?? NSView()
        let size = content.fittingSize
        // firstRect 返回屏幕坐标，与子窗口 setFrame 同一坐标系。
        let rect = firstRect(forCharacterRange: range, actualRange: nil)
        let frame = EditorPopupGeometry.frame(anchor: rect,
            size: NSSize(width: max(size.width, 120), height: max(size.height, 30)),
            bounds: EditorPopupGeometry.bounds(in: window), preferredSide: .above, alignment: .center)
        guard !frame.isEmpty else { closeSelectionPanel(); return }
        panel.setFrame(frame, display: true)
        panel.orderFront(nil)
    }

    /// 浮条上的颜色按钮读当前选区（多 run 交集）的墨色/底色。
    private func selectionToolbarRoot(for range: NSRange) -> DocumentSelectionToolbarView {
        let style = textStorage.map { DocumentTextCodec.style(of: $0.attributedSubstring(from: range)) }
            ?? DocumentSelectionStyle()
        return DocumentSelectionToolbarView(
            actions: profile.selectionActions,
            onInvoke: { [weak self] action in self?.invokeSelectionToolbarAction(action) },
            onFormat: { [weak self] command in self?.invokeSelectionToolbarFormat(command) },
            onLink: { [weak self] in self?.invokeSelectionToolbarLink() },
            textColorHex: style.marks.textColorHex,
            highlightHex: style.marks.highlightHex,
            onTextColor: { [weak self] hex in self?.applySelectionToolbarTextColor(hex) },
            onHighlightColor: { [weak self] hex in self?.applySelectionToolbarHighlightColor(hex) })
    }

    /// 上色后不收起浮条：选区还在，色板勾选态和小色条由刷新后的 rootView 跟上。
    private func applySelectionToolbarTextColor(_ hex: String?) {
        guard selectedRange().length > 0 else { dismissSelectionToolbar(); return }
        window?.makeFirstResponder(self)
        applyTextColor(hex)
        refreshSelectionToolbar()
    }

    private func applySelectionToolbarHighlightColor(_ hex: String?) {
        guard selectedRange().length > 0 else { dismissSelectionToolbar(); return }
        window?.makeFirstResponder(self)
        applyHighlightColor(hex)
        refreshSelectionToolbar()
    }

    private func invokeSelectionToolbarAction(_ action: DocumentSelectionAction) {
        let range = selectedRange()
        guard range.length > 0, NSMaxRange(range) <= (string as NSString).length else {
            dismissSelectionToolbar()
            return
        }
        let text = (string as NSString).substring(with: range)
        dismissSelectionToolbar()
        window?.makeFirstResponder(self)
        action.perform(text)
    }

    private func invokeSelectionToolbarFormat(_ command: DocumentFormatCommand) {
        dismissSelectionToolbar()
        window?.makeFirstResponder(self)
        applyFormat(command)
    }

    private func invokeSelectionToolbarLink() {
        dismissSelectionToolbar()
        window?.makeFirstResponder(self)
        editDocumentLink(nil)
    }

    // MARK: - 图片粘贴（迁移自 Flutter onImagePaste：剪贴板图片 → data URL 图片块）

    override func copy(_ sender: Any?) {
        if copyDocumentFragment(to: .general) { return }
        if !copyDiagramContent(to: .general) { super.copy(sender) }
    }

    override func cut(_ sender: Any?) {
        guard isEditable else { return }
        if copyDocumentFragment(to: .general) || copyDiagramContent(to: .general) {
            insertText("", replacementRange: selectedRange())
        }
        else { super.cut(sender) }
    }

    override func paste(_ sender: Any?) {
        if pasteDocumentFragment(from: .general) { return }
        if pasteDiagramContent(from: .general) { return }
        // 剪贴板是文件（Finder 复制/拖到编辑区）：交给宿主落盘成附件（TI2-03）。
        if let pasteFiles = profile.onPasteFiles {
            let urls = (NSPasteboard.general.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            if !urls.isEmpty {
                pasteFiles(urls)
                return
            }
        }
        if insertPastedImage() { return }
        if pasteExternalDocumentFragment(from: .general,
                                         destinationKind: currentParagraphKind() ?? .paragraph) { return }
        // 富文本粘贴：保留粗/斜/下划线/删除线/行内代码/链接这些**基础标记**，
        // 丢字号、颜色、背景、缩进与字体族（这些不是文档模型的一部分，带进来
        // 只会在 decode 时变成脏属性）。没有可保留标记时退回纯文本。
        if let rich = Self.richPasteboardContent(), !rich.string.isEmpty,
           let baseKind = currentParagraphKind(),
           let converted = DocumentTextCodec.richText(rich, baseKind: baseKind) {
            insertText(converted, replacementRange: selectedRange())
            return
        }
        // NSTextView 默认 `paste` 不经过 `insertText`，输入期 Markdown 转换与 Slash
        // 触发都会绕过；纯文本粘贴改走 `insertText`，与逐键输入同一条路径
        // （整串写入口径：以标记字符结尾时转最近一处闭合）。
        if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            insertText(text, replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }


    /// 剪贴板里的富文本（RTF 优先，其次 HTML）。两者都没有时返回 nil。
    private static func richPasteboardContent() -> NSAttributedString? {
        let board = NSPasteboard.general
        if let data = board.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: data, documentAttributes: nil),
           !attributed.string.isEmpty {
            return attributed
        }
        if let html = board.string(forType: .html), let data = html.data(using: .utf8),
           let attributed = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.html,
                         .characterEncoding: String.Encoding.utf8.rawValue],
               documentAttributes: nil),
           !attributed.string.isEmpty {
            return attributed
        }
        return nil
    }

    /// 光标所在段落的块类型（富文本粘贴沿用，不把粘贴处改成标题/列表）。
    private func currentParagraphKind() -> DocumentBlockKind? {
        guard let storage = textStorage else { return nil }
        let source = storage.string as NSString
        if selectedRange().location == source.length, source.length == 0 || string.hasSuffix("\n"),
           let trailing = pendingTrailingBlock ?? displayedTrailingBlock { return trailing }
        let anchor = source.length == 0 ? 0 : min(max(selectedRange().location, 0), source.length - 1)
        guard source.length > 0,
              let token = storage.attribute(DocumentTextCodec.blockKey, at: anchor,
                                            effectiveRange: nil) as? String else {
            return pendingTrailingBlock ?? displayedTrailingBlock ?? .paragraph
        }
        return DocumentTextCodec.kind(token)
    }

    /// 剪贴板带位图（且不是 Finder 文件）时转 data URL 附件块插入；返回是否已处理。
    /// NativeDocument 没有独立图片块类型，按迁移决策用附件 run 承载 data URL
    /// （DocumentTextCodec 会把这类附件渲染成真实图片）。
    @discardableResult
    private func insertPastedImage() -> Bool {
        guard isEditable, NSPasteboard.general.data(forType: .fileURL) == nil,
              let raw = Self.pasteboardImageData() else { return false }
        let dataURL = "data:image/png;base64," + Self.normalizedPNG(raw).base64EncodedString()
        let attachment = NativeAttachment(id: UUID(), name: "粘贴的图片.png", storedName: dataURL)
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        insertAttachments([attachment])
        undoManager?.endUndoGrouping()
        return true
    }

    private static func pasteboardImageData() -> Data? {
        let board = NSPasteboard.general
        if let png = board.data(forType: .png) { return png }
        return board.data(forType: .tiff)
    }

    /// 粘贴的截图常远超正文宽度：最长边超过 1600px 时等比缩小后再编码，
    /// 避免快照 JSON 膨胀（data URL 随笔记文档持久化）。
    static func normalizedPNG(_ data: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              max(image.width, image.height) > 1600 else { return data }
        let scale = 1600.0 / CGFloat(max(image.width, image.height))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return data }
        context.interpolationQuality = .high
        context.draw(image, in: NSRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return data }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.png" as CFString, 1, nil) else { return data }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else { return data }
        return output as Data
    }

    /// 撤销/重做闭包请求"操作完成后恢复的选区"。
    ///
    /// 实测：撤销机制会在闭包结束之后、`undo()` 返回之前，再把插入点吸附回
    /// 编辑位置（闭包里的 `setSelectedRange` 会被随后覆盖）。所以闭包只能
    /// **登记意图**，由 `undo()`/`redo()` 返回后统一补写。
    private var selectionAfterUndoRedo: NSRange?

    /// 撤销/重做闭包里调用：登记操作完成后要恢复的选区（仅撤销/重做期间生效）。
    func requestSelectionAfterUndoRedo(_ range: NSRange) {
        guard documentUndoManager.isUndoing || documentUndoManager.isRedoing else { return }
        selectionAfterUndoRedo = range
    }

    @objc func undo(_ sender: Any?) {
        dismissSlash()
        breakUndoCoalescing()
        if hasHostDocumentCommands, documentUndoManager.groupsByEvent,
           documentUndoManager.groupingLevel == 1 {
            documentUndoManager.endUndoGrouping()
        }
        documentUndoManager.undo()
        applySelectionAfterUndoRedo()
        // Native text undo changes storage without going through insertText.
        // Publish the replayed document; command callbacks already synchronized
        // by the coordinator are deduplicated there.
        didChangeText()
    }

    @objc func redo(_ sender: Any?) {
        dismissSlash()
        documentUndoManager.redo()
        applySelectionAfterUndoRedo()
        didChangeText()
    }

    private func applySelectionAfterUndoRedo() {
        guard let range = selectionAfterUndoRedo else { return }
        selectionAfterUndoRedo = nil
        guard NSMaxRange(range) <= (string as NSString).length else { return }
        setSelectedRange(range)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(applyDocumentFormat(_:)) { return isEditable }
        if item.action == #selector(invokeSelectionAction(_:)) { return selectedRange().length > 0 }
        if item.action == #selector(undo(_:)) { return documentUndoManager.canUndo }
        if item.action == #selector(redo(_:)) { return documentUndoManager.canRedo }
        return super.validateUserInterfaceItem(item)
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            // 重新聚焦后活动行标记（标题角标 / 空行"+"）要回来。
            needsDisplay = true
            onEditingChanged?(true)
        }
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            needsDisplay = true
            dismissSlash(); onEditingChanged?(false)
        }
        return resigned
    }

    /// 行首装饰层（选区之上）；见 `BlockDecorationOverlay`。
    private var decorationOverlay: BlockDecorationOverlay?
    private var decorationSelectionObserver: NSObjectProtocol?
    private var spellObserver: NSObjectProtocol?
    /// 重入保护：着色写 storage 会再触发 `didChangeText`。
    private var isRestylingCode = false
    private var decorationBoundsObserver: NSObjectProtocol?
    private var scrollObservers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installScrollObservers()
    }

    /// Content-sized editors live inside SwiftUI's outer ScrollView; the text
    /// view's own bounds never move when that scrolls. Observe every ancestor
    /// clip view so hover and open cards follow real scrolling.
    private func installScrollObservers() {
        scrollObservers.forEach(NotificationCenter.default.removeObserver)
        scrollObservers.removeAll()
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? NSScrollView {
                let clip = scroll.contentView
                scrollObservers.append(NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.decorationOverlay?.needsDisplay = true
                        self.dismissChecklistReminderPanel()
                        self.updateChecklistHoverFromMouse()
                    }
                })
            }
            ancestor = view.superview
        }
    }

    override func layout() {
        super.layout()
        installDecorationOverlay()
    }

    /// 装饰层必须始终压在所有子视图（尤其是 TextKit 2 的 `_NSTextSelectionView`）之上。
    private func installDecorationOverlay() {
        if decorationOverlay == nil {
            let overlay = BlockDecorationOverlay(textView: self)
            addSubview(overlay)
            decorationOverlay = overlay
        }
        decorationOverlay?.frame = bounds
        reorderDecorationOverlay()
    }

    private func reorderDecorationOverlay() {
        guard let decorationOverlay, subviews.last !== decorationOverlay else { return }
        addSubview(decorationOverlay, positioned: .above, relativeTo: nil)
    }

    override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
        let container: NSTextContainer
        var ownedContentStorage: NSTextContentStorage?
        if let textContainer {
            container = textContainer
        } else {
            container = NSTextContainer(size: NSSize(
                width: max(frameRect.width, 1), height: CGFloat.greatestFiniteMagnitude))
            let contentStorage = NSTextContentStorage()
            let layout = NSTextLayoutManager()
            layout.textContainer = container
            contentStorage.addTextLayoutManager(layout)
            ownedContentStorage = contentStorage
        }
        super.init(frame: frameRect, textContainer: container)
        ownedTextContentStorage = ownedContentStorage
        installDecorationOverlay()
        postsBoundsChangedNotifications = true
        decorationSelectionObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.decorationOverlay?.needsDisplay = true
                self?.reorderDecorationOverlay()
            }
        }
        decorationBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.decorationOverlay?.needsDisplay = true
                let origin = self.bounds.origin
                if let last = self.lastBoundsOrigin, last != origin {
                    // 滚动会把锚点带走：提醒面板收起，悬停行按新位置重算。
                    self.dismissChecklistReminderPanel()
                    self.updateChecklistHoverFromMouse()
                }
                self.lastBoundsOrigin = origin
            }
        }
        spellObserver = NotificationCenter.default.addObserver(
            forName: EditorPreferences.spellCheckingDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isContinuousSpellCheckingEnabled = EditorPreferences.spellCheckingEnabled
            }
        }
        storageObserver = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: textStorage, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.storageRevision += 1
                self?.decorationOverlay?.needsDisplay = true
            }
        }
        focusRingType = .none
        // 智能替换会把 Markdown 语法吃掉：代码块里 `"` → 弯引号、`--` → 破折号、
        // `(c)` → ©，输入 `---` 分割线也会被替换掉（2026-10-24 实测默认全开）。
        // 滴答的编辑面同样不做智能替换；拼写检查按用户偏好单独开关。
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = EditorPreferences.spellCheckingEnabled
        isGrammarCheckingEnabled = false
        isRichText = true
        usesRuler = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isSelectable = true
        isEditable = true
        drawsBackground = false
        backgroundColor = .clear
        textColor = .labelColor
        insertionPointColor = .labelColor
        font = .systemFont(ofSize: DocumentEditorPresentationMetrics.bodyFontSize)
        // Empty documents must begin at the same origin as rendered paragraphs
        // and headings; NSTextView's default typing style has zero indent.
        typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        // 行首沟槽（角标 / 空行"+" / 列表标记）由各段落的 headIndent 留出，
        // 而不是 textContainerInset：NSTextView 会把绘制裁剪到文本容器区域，
        // 画在容器左侧留白里的装饰（x < inset.width）一律不可见（实测）。
        textContainerInset = NSSize(width: 0, height: 4)
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                         height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        container.widthTracksTextView = true
        container.heightTracksTextView = false
    }

    required init?(coder: NSCoder) {
        fatalError("NativeTextView is created programmatically")
    }

    deinit {
        if let storageObserver { NotificationCenter.default.removeObserver(storageObserver) }
        if let decorationSelectionObserver {
            NotificationCenter.default.removeObserver(decorationSelectionObserver)
        }
        if let decorationBoundsObserver {
            NotificationCenter.default.removeObserver(decorationBoundsObserver)
        }
        if let spellObserver { NotificationCenter.default.removeObserver(spellObserver) }
        scrollObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func cancelOperation(_ sender: Any?) {
        if linkHoverPanel != nil {
            hideLinkHoverMenu()
            return
        }
        switch DocumentEditorEscapeRoute.resolve(
            composing: hasMarkedText(), slash: slashSession != nil,
            selectionToolbar: selectionPanel != nil,
            findBar: enclosingScrollView?.isFindBarVisible == true) {
        case .inputMethod:
            super.cancelOperation(sender)
            return
        case .slash:
            dismissSlash()
            return
        case .selectionToolbar:
            dismissSelectionToolbar()
            return
        case .findBar:
            enclosingScrollView?.isFindBarVisible = false
            return
        case .host:
            break
        }
        if onCancelTransient?() == true { return }
        guard let onEscape else {
            super.cancelOperation(sender)
            return
        }
        switch onEscape() {
        case .endEditing, .returnToList:
            _ = window?.makeFirstResponder(nil)
        case .dismissPopover, .keepInspector:
            break
        }
    }
}
