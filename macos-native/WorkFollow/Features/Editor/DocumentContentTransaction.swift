import AppKit

extension NativeTextView {
    /// Host compensation belongs to the same undo record as this replacement.
    /// The callbacks receive the resulting document, not a stale full model.
    @discardableResult
    func replaceDocumentContent(_ value: NSAttributedString, range: NSRange, selection: NSRange,
                                commit: @escaping (NativeDocument) -> Void,
                                inverseCommit: @escaping (NativeDocument) -> Void) -> Bool {
        guard isEditable, !hasMarkedText(), delegate is DocumentEditorCoordinator,
              let storage = textStorage, range.location != NSNotFound,
              NSMaxRange(range) <= storage.length,
              let manager = undoManager, manager.isUndoRegistrationEnabled else { return false }
        // NSTextView's shouldChangeText also registers its own replacement undo.
        // This command owns that replacement together with the host callback.
        breakUndoCoalescing()
        if !manager.isUndoing && !manager.isRedoing {
            // Finish the previous run-loop group, not an explicit nested
            // command. A reference must be a top-level undo operation.
            guard manager.groupingLevel == 0 || (manager.groupsByEvent && manager.groupingLevel == 1) else { return false }
            if manager.groupingLevel == 1 { manager.endUndoGrouping() }
        }
        let previousGroupsByEvent = manager.groupsByEvent
        manager.groupsByEvent = false
        defer { manager.groupsByEvent = previousGroupsByEvent }
        let previousAllowsUndo = allowsUndo
        allowsUndo = false
        defer { allowsUndo = previousAllowsUndo }
        manager.disableUndoRegistration()
        let accepted = shouldChangeText(in: range, replacementString: value.string)
        manager.enableUndoRegistration()
        guard accepted else { return false }
        let identity = documentIdentity
        let previous = storage.attributedSubstring(from: range)
        let previousSelection = selectedRange()
        let previousTyping = typingAttributes
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: self) { view in
            guard view.documentIdentity == identity else { return }
            if view.replaceDocumentContent(previous,
                range: NSRange(location: range.location, length: value.length),
                selection: previousSelection, commit: inverseCommit, inverseCommit: commit) {
                view.typingAttributes = previousTyping
            }
        }
        let previousCommit = documentCommandCommit
        documentCommandCommit = commit
        manager.disableUndoRegistration()
        storage.replaceCharacters(in: range, with: value)
        setSelectedRange(selection)
        requestSelectionAfterUndoRedo(selection)
        didChangeText()
        manager.enableUndoRegistration()
        documentCommandCommit = previousCommit
        manager.endUndoGrouping()
        allowsUndo = previousAllowsUndo
        manager.groupsByEvent = previousGroupsByEvent
        breakUndoCoalescing()
        hasHostDocumentCommands = true
        return true
    }
}
