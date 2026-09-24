import AppKit

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
    var documentIdentity = UUID()

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let wasComposing = hasMarkedText()
        super.insertText(insertString, replacementRange: replacementRange)
        guard !wasComposing, (insertString as? String) == "/" else { refreshSlash(); return }
        let location = selectedRange().location
        guard location > 0 else { return }
        // A slash in a URL/path is ordinary text, not a command trigger.
        let prefix = (string as NSString).substring(to: location - 1)
        guard prefix.isEmpty || prefix.last?.isWhitespace == true else { return }
        slashSession = SlashSession(start: location - 1)
        refreshSlash()
    }

    override func didChangeText() {
        super.didChangeText()
        refreshSlash()
    }

    override func mouseDown(with event: NSEvent) {
        dismissSlash()
        super.mouseDown(with: event)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { dismissSlash() }
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
