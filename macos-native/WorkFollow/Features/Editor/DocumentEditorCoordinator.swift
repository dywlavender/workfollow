import AppKit
import SwiftUI

@MainActor
final class DocumentEditorCoordinator: NSObject, NSTextViewDelegate {
    private(set) var taskID: UUID
    private var document: NativeDocument
    private var onDocumentChange: (NativeDocument) -> Void
    private var onEscape: () -> InspectorEscapeEffect

    init(taskID: UUID, document: NativeDocument,
         onDocumentChange: @escaping (NativeDocument) -> Void,
         onEscape: @escaping () -> InspectorEscapeEffect) {
        self.taskID = taskID
        self.document = document
        self.onDocumentChange = onDocumentChange
        self.onEscape = onEscape
    }

    func update(_ textView: NativeTextView, taskID: UUID, document: NativeDocument,
                onDocumentChange: @escaping (NativeDocument) -> Void,
                onEscape: @escaping () -> InspectorEscapeEffect) {
        if self.taskID != taskID {
            flushPendingComposition(in: textView)
            self.taskID = taskID
            self.document = document
            textView.string = document.plainText
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        } else if self.document.plainText != document.plainText,
                  !textView.hasMarkedText() {
            let selection = textView.selectedRange()
            self.document = document
            textView.string = document.plainText
            let location = min(selection.location, (document.plainText as NSString).length)
            let length = min(selection.length, (document.plainText as NSString).length - location)
            textView.setSelectedRange(NSRange(location: location, length: length))
        }
        self.onDocumentChange = onDocumentChange
        self.onEscape = onEscape
        textView.onEscape = onEscape
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        commit(textView, force: false)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        // NSTextView owns the live selection; the editor coordinator intentionally
        // does not push it into the task domain.
    }

    func flushPendingComposition(in textView: NativeTextView) {
        if textView.hasMarkedText() {
            textView.unmarkText()
        }
        commit(textView, force: true)
    }

    private func commit(_ textView: NSTextView, force: Bool) {
        guard force || !textView.hasMarkedText() else { return }
        let updated = document.replacingPlainText(textView.string)
        guard updated != document else { return }
        document = updated
        onDocumentChange(updated)
    }
}
