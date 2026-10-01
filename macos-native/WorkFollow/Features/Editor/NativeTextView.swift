import AppKit
import ImageIO
import SwiftUI

final class NativeTextView: NSTextView {
    // An inspector is recreated for each document. Never share the window's
    // undo history with another task or its title field.
    private let documentUndoManager = UndoManager()
    private var ownedTextContentStorage: NSTextContentStorage?
    override var undoManager: UndoManager? { documentUndoManager }

    var onEscape: (() -> InspectorEscapeEffect)?
    var onEditingChanged: ((Bool) -> Void)?
    /// 选区或输入属性变了：工具条靠它刷新激活态（对齐原版 `_active` 的那条路）。
    var onSelectionChanged: (() -> Void)?
    var profile = DocumentProfile()
    var slashSession: SlashSession?
    var slashPanel: NSPanel?
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

    /// 绑定文档时把模型里的文末级别带回输入属性（由协调器调用），这样切走再回来
    /// 接着在文末输入时，字号与级别都还在。
    func seedTrailingParagraphKind(_ kind: DocumentBlockKind?) {
        pendingTrailingBlock = kind
        displayedTrailingBlock = kind
        guard let kind else { return }
        typingAttributes = DocumentTextCodec.attributes(kind: kind, marks: [])
    }
    var selectionPanel: NSPanel?
    var documentIdentity = UUID()
    var needsHostCaretReveal = false

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let wasComposing = hasMarkedText()
        // 覆盖一段选中文本输入触发字符是普通编辑，不该开命令面板。
        let target = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        let replacedSelection = target.length > 0
        let insertedText = insertString as? String
        let trigger: String? = insertedText.flatMap { inserted in
            ["/", "、"].first { $0 == inserted }
        }
        // 真有字进来了，段落样式就由字符承载，"文末待定级别"不再需要。
        if let insertedText, !insertedText.isEmpty { pendingTrailingBlock = nil }
        super.insertText(insertString, replacementRange: replacementRange)
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
        // 先同步文末空段的待定级别，delegate 的 commit 解码才能带上正确类型
        // （标题行回车后新行延续级别靠这一步）。
        syncPendingTrailingBlock()
        super.didChangeText()
        refreshSlash()
        // 行首标记活在文本区外的沟槽里（标题角标 / 空行"+"），文字变化不会
        // 自动把它标脏：段落类型变了要显式重绘。
        needsDisplay = true
        // The task editor grows inside the inspector's scroll view. Its own
        // clip view has nothing to scroll; reveal the caret in the host after
        // SwiftUI has applied the new document height.
        needsHostCaretReveal = true
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

    /// 空的标题/列表行上按回车 → 退回正文（滴答/Quill 同款：再按一次回车退出格式），
    /// 返回是否已处理。有内容的行回车会延续格式，不走这里。
    func exitEmptyBlockOnNewline() -> Bool {
        guard isEditable, !hasMarkedText(), let storage = textStorage else { return false }
        let source = storage.string as NSString
        let caret = min(max(selectedRange().location, 0), source.length)
        let trailingEmpty = source.length == 0
            || (caret == source.length && source.character(at: source.length - 1) == 0x0A)
        let plain = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        // 可退出的块：标题与三类列表（有序/无序/检查项）。
        func isExitable(_ kind: DocumentBlockKind) -> Bool {
            switch kind {
            case .heading, .bullet, .ordered, .checklist: return true
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
        didChangeText()
    }

    func revealCaretInHostAfterLayout() {
        guard needsHostCaretReveal else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.firstResponder === self,
                  let inner = self.enclosingScrollView, !inner.hasVerticalScroller,
                  let window = self.window else { return }
            window.contentView?.layoutSubtreeIfNeeded()
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

    func invalidateDocumentLayout(for range: NSRange) {
        if let contentStorage = ownedTextContentStorage,
           let textLayoutManager {
            textLayoutManager.invalidateLayout(for: contentStorage.documentRange)
            needsDisplay = true
            return
        }
        layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
    }

    override func mouseDown(with event: NSEvent) {
        dismissSlash()
        // 文档复选框在任务与笔记两个面都可点（原版 `DocumentCheckboxBuilder` 挂在
        // 共享文档样式上，不分面）。
        if isEditable, let window, let storage = textStorage, storage.length > 0 {
            let point = convert(event.locationInWindow, from: nil)
            let offset = min(characterIndexForInsertion(at: point), storage.length - 1)
            let paragraph = (string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
            let token = storage.attribute(DocumentTextCodec.blockKey, at: paragraph.location, effectiveRange: nil) as? String
            if token == "checklist" || token == "checked" {
                let screenRect = firstRect(forCharacterRange: NSRange(location: paragraph.location, length: 0), actualRange: nil)
                let caret = convert(window.convertFromScreen(screenRect), from: nil)
                let marker = NSRect(x: caret.minX - 28, y: caret.minY, width: 28, height: caret.height)
                if marker.contains(point) {
                    window.makeFirstResponder(self)
                    toggleNoteChecklist(at: paragraph.location)
                    return
                }
            }
            // 文末空段的检查项没有字符可读 token：级别活在待定/模型状态里，
            // 点中标记区按它翻转（显示已支持，这里补点击）。
            let trailingKind = pendingTrailingBlock ?? displayedTrailingBlock
            if token != "checklist", token != "checked",
               case .checklist(let checked) = trailingKind {
                let screenRect = firstRect(forCharacterRange: NSRange(location: storage.length, length: 0), actualRange: nil)
                let caret = convert(window.convertFromScreen(screenRect), from: nil)
                let marker = NSRect(x: caret.minX - 28, y: caret.minY, width: 28, height: caret.height)
                if marker.contains(point) {
                    window.makeFirstResponder(self)
                    setTrailingChecklist(checked: !checked)
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    /// 文末空段的检查项翻转：无字符可改，直接改输入属性与待定级别并注册撤销；
    /// 光标同时落到文末（级别只有这样才会随下一次 commit 进模型）。
    func setTrailingChecklist(checked: Bool) {
        applyTrailingState(typing: DocumentTextCodec.attributes(kind: .checklist(checked), marks: []),
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

    func toggleNoteChecklist(at offset: Int) {
        guard let storage = textStorage, offset >= 0, offset < storage.length else { return }
        let range = (string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
        let selected = storage.attributedSubstring(from: range)
        var document = DocumentTextCodec.decode(selected, preserving: NativeDocument(plainText: selected.string))
        guard let first = document.blocks.first, case .checklist(let checked) = first.kind else { return }
        document.blocks[0].kind = .checklist(!checked)
        let selection = selectedRange()
        insertText(DocumentTextCodec.render(document), replacementRange: range)
        setSelectedRange(selection)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            dismissSlash()
            dismissSelectionToolbar()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func doCommand(by selector: Selector) {
        if slashSession != nil, !hasMarkedText() {
            switch selector {
            case #selector(moveUp(_:)): moveSlash(-1); return
            case #selector(moveDown(_:)): moveSlash(1); return
            case #selector(insertNewline(_:)): executeSlash(); return
            case #selector(cancelOperation(_:)): dismissSlash(); return
            default: break
            }
        }
        // 空标题/列表行上回车：退回正文（有内容的行回车会延续格式，不受影响）。
        if selector == #selector(insertNewline(_:)), !hasMarkedText(),
           exitEmptyBlockOnNewline() { return }
        super.doCommand(by: selector)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
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
        let eligible = window != nil && !hasMarkedText() && range.length > 0 && profile.supportsSelectionToolbar
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
            window.addChildWindow(panel, ordered: .above)
            selectionPanel = panel
        }
        panel.contentView = NSHostingView(rootView: DocumentSelectionToolbarView(
            actions: profile.selectionActions,
            onInvoke: { [weak self] action in self?.invokeSelectionToolbarAction(action) },
            onFormat: { [weak self] command in self?.invokeSelectionToolbarFormat(command) },
            onLink: { [weak self] in self?.invokeSelectionToolbarLink() }))
        let content = panel.contentView ?? NSView()
        let size = content.fittingSize
        // firstRect 返回屏幕坐标，与子窗口 setFrame 同一坐标系。
        let rect = firstRect(forCharacterRange: range, actualRange: nil)
        let bounds = (window.screen?.visibleFrame ?? window.frame).intersection(window.frame).insetBy(dx: 8, dy: 8)
        let width = min(max(size.width, 120), bounds.width)
        let height = max(size.height, 30)
        let x = min(max(rect.midX - width / 2, bounds.minX), bounds.maxX - width)
        let y = rect.maxY + 6 + height <= bounds.maxY
            ? rect.maxY + 6
            : max(bounds.minY, rect.minY - height - 6)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.orderFront(nil)
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

    override func paste(_ sender: Any?) {
        if insertPastedImage() { return }
        super.paste(sender)
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
        documentUndoManager.undo()
        applySelectionAfterUndoRedo()
    }

    @objc func redo(_ sender: Any?) {
        dismissSlash()
        documentUndoManager.redo()
        applySelectionAfterUndoRedo()
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
        focusRingType = .none
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
        font = .systemFont(ofSize: 15)
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

    override func cancelOperation(_ sender: Any?) {
        // Escape belongs to the active input method before the inspector.
        if hasMarkedText() {
            super.cancelOperation(sender)
            return
        }
        if slashSession != nil { dismissSlash(); return }
        if selectionPanel != nil { dismissSelectionToolbar(); return }
        if enclosingScrollView?.isFindBarVisible == true {
            enclosingScrollView?.isFindBarVisible = false
            return
        }
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
