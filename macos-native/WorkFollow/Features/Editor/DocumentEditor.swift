import AppKit
import SwiftUI

struct DocumentEditor: NSViewRepresentable {
    let taskID: UUID
    let document: NativeDocument
    let onDocumentChange: (NativeDocument) -> Void
    let onEscape: () -> InspectorEscapeEffect
    let onEditingChanged: (Bool) -> Void

    func makeCoordinator() -> DocumentEditorCoordinator {
        DocumentEditorCoordinator(taskID: taskID, document: document,
                                  onDocumentChange: onDocumentChange,
                                  onEscape: onEscape,
                                  onEditingChanged: onEditingChanged)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NativeTextView(frame: .zero, textContainer: nil)
        textView.delegate = context.coordinator
        textView.string = document.plainText
        textView.onEscape = onEscape
        textView.onEditingChanged = onEditingChanged
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NativeTextView else { return }
        context.coordinator.update(textView, taskID: taskID, document: document,
                                   onDocumentChange: onDocumentChange,
                                   onEscape: onEscape,
                                   onEditingChanged: onEditingChanged)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: DocumentEditorCoordinator) {
        guard let textView = scrollView.documentView as? NativeTextView else { return }
        coordinator.flushPendingComposition(in: textView)
        textView.delegate = nil
        textView.onEscape = nil
        textView.onEditingChanged = nil
    }
}
