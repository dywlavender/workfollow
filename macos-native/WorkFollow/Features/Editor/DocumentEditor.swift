import AppKit
import SwiftUI

struct DocumentEditor: NSViewRepresentable {
    let taskID: UUID
    let document: NativeDocument
    let onDocumentChange: (NativeDocument) -> Void
    let onEscape: () -> InspectorEscapeEffect
    let onEditingChanged: (Bool) -> Void
    var selectionActionTitle: String? = nil
    var onSelectionAction: ((String) -> Void)? = nil

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
        textView.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        textView.onEscape = onEscape
        textView.onEditingChanged = onEditingChanged
        textView.selectionActionTitle = selectionActionTitle
        textView.onSelectionAction = onSelectionAction
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NativeTextView else { return }
        textView.selectionActionTitle = selectionActionTitle
        textView.onSelectionAction = onSelectionAction
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
        textView.onSelectionAction = nil
    }
}
