import AppKit
import SwiftUI

@MainActor
final class DocumentEditorCoordinator: NSObject, NSTextViewDelegate {
    private(set) var taskID: UUID
    private(set) var editorState: DocumentEditorState
    private var document: NativeDocument
    private var onDocumentChange: (NativeDocument) -> Void
    private var onEscape: () -> InspectorEscapeEffect
    private var onEditingChanged: (Bool) -> Void

    init(taskID: UUID, document: NativeDocument,
         onDocumentChange: @escaping (NativeDocument) -> Void,
         onEscape: @escaping () -> InspectorEscapeEffect,
         onEditingChanged: @escaping (Bool) -> Void) {
        self.taskID = taskID
        self.editorState = DocumentEditorState(taskID: taskID)
        self.document = document
        self.onDocumentChange = onDocumentChange
        self.onEscape = onEscape
        self.onEditingChanged = onEditingChanged
    }

    func update(_ textView: NativeTextView, taskID: UUID, document: NativeDocument,
                onDocumentChange: @escaping (NativeDocument) -> Void,
                onEscape: @escaping () -> InspectorEscapeEffect,
                onEditingChanged: @escaping (Bool) -> Void) {
        if self.taskID != taskID {
            flushPendingComposition(in: textView)
            self.taskID = taskID
            editorState.bind(to: taskID)
            self.document = document
            textView.textStorage?.setAttributedString(DocumentTextCodec.render(document))
            textView.setSelectedRange(editorState.selectedRange)
        } else if self.document != document,
                  !textView.hasMarkedText() {
            let selection = textView.selectedRange()
            self.document = document
            textView.textStorage?.setAttributedString(DocumentTextCodec.render(document))
            let location = min(selection.location, (document.plainText as NSString).length)
            let length = min(selection.length, (document.plainText as NSString).length - location)
            textView.setSelectedRange(NSRange(location: location, length: length))
        }
        self.onDocumentChange = onDocumentChange
        self.onEscape = onEscape
        self.onEditingChanged = onEditingChanged
        textView.onEscape = onEscape
        textView.onEditingChanged = onEditingChanged
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        commit(textView, force: false)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        editorState.updateSelection(textView.selectedRange())
    }

    func flushPendingComposition(in textView: NativeTextView) {
        if textView.hasMarkedText() {
            textView.unmarkText()
        }
        commit(textView, force: true)
    }

    private func commit(_ textView: NSTextView, force: Bool) {
        guard force || !textView.hasMarkedText() else { return }
        let updated = DocumentTextCodec.decode(textView.attributedString(), preserving: document)
        guard updated != document else { return }
        document = updated
        onDocumentChange(updated)
    }
}
