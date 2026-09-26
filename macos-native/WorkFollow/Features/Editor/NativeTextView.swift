import AppKit
import ImageIO
import SwiftUI

final class NativeTextView: NSTextView {
    // An inspector is recreated for each document. Never share the window's
    // undo history with another task or its title field.
    private let documentUndoManager = UndoManager()
    private var ownedTextStorage: NSTextStorage?
    override var undoManager: UndoManager? { documentUndoManager }

    var onEscape: (() -> InspectorEscapeEffect)?
    var onEditingChanged: ((Bool) -> Void)?
    var profile = DocumentProfile()
    var slashSession: SlashSession?
    var slashPanel: NSPanel?
    var selectionPanel: NSPanel?
    var documentIdentity = UUID()
    var needsHostCaretReveal = false

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let wasComposing = hasMarkedText()
        super.insertText(insertString, replacementRange: replacementRange)
        guard !wasComposing, (insertString as? String) == "/" else { refreshSlash(); return }
        let location = selectedRange().location
        guard location > 0 else { return }
        // A slash in a URL/path is ordinary text, not a command trigger.
        let prefix = (string as NSString).substring(to: location - 1)
        guard profile.taskSlash || prefix.isEmpty || prefix.last?.isWhitespace == true else { return }
        slashSession = SlashSession(start: location - 1)
        refreshSlash()
    }

    override func didChangeText() {
        super.didChangeText()
        refreshSlash()
        // The task editor grows inside the inspector's scroll view. Its own
        // clip view has nothing to scroll; reveal the caret in the host after
        // SwiftUI has applied the new document height.
        needsHostCaretReveal = true
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

    override func mouseDown(with event: NSEvent) {
        dismissSlash()
        super.mouseDown(with: event)
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
        let eligible = window != nil && !hasMarkedText() && range.length > 0 && !profile.taskSlash
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

    @objc func undo(_ sender: Any?) {
        dismissSlash()
        breakUndoCoalescing()
        documentUndoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        dismissSlash()
        documentUndoManager.redo()
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
        if becameFirstResponder { onEditingChanged?(true) }
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { dismissSlash(); onEditingChanged?(false) }
        return resigned
    }

    override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
        let container: NSTextContainer
        var ownedStorage: NSTextStorage?
        if let textContainer {
            container = textContainer
        } else {
            let storage = NSTextStorage()
            let layout = NSLayoutManager()
            container = NSTextContainer(size: NSSize(
                width: max(frameRect.width, 1), height: CGFloat.greatestFiniteMagnitude))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            ownedStorage = storage
        }
        super.init(frame: frameRect, textContainer: container)
        ownedTextStorage = ownedStorage
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
