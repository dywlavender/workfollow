import AppKit
import SwiftUI

struct DocumentEditor: NSViewRepresentable {
    let documentID: UUID
    let document: NativeDocument
    let onDocumentChange: (NativeDocument) -> Void
    let onEscape: () -> InspectorEscapeEffect
    let onEditingChanged: (Bool) -> Void
    var profile = DocumentProfile()

    func makeCoordinator() -> DocumentEditorCoordinator {
        DocumentEditorCoordinator(documentID: documentID, document: document,
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
        textView.documentIdentity = documentID
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        textView.onEscape = onEscape
        textView.onEditingChanged = onEditingChanged
        textView.profile = profile
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NativeTextView else { return }
        textView.profile = profile
        context.coordinator.update(textView, documentID: documentID, document: document,
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
        textView.dismissSlash()
        textView.documentIdentity = UUID()
        textView.profile = DocumentProfile()
    }
}
