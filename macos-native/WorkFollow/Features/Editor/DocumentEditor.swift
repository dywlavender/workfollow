import AppKit
import SwiftUI

@MainActor
final class DocumentEditorHandle: ObservableObject {
    weak var textView: NativeTextView?

    func format(_ command: DocumentFormatCommand) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.applyFormat(command)
    }

    func focusEditor() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func editLink() { textView?.editDocumentLink(nil) }
    func removeLink() { textView?.removeDocumentLink(nil) }
    func insertAttachment() { textView?.insertDocumentAttachment(nil) }
    func insertTime(format: String) { textView?.window?.makeFirstResponder(textView); textView?.insertDocumentTime(format: format) }
    func insertDivider() { textView?.window?.makeFirstResponder(textView); textView?.insertDocumentDivider() }
    func insertNoteReference(_ note: Note) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let content = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [
            DocumentRun(text: "📄 " + (note.title.isEmpty ? "未命名笔记" : note.title),
                        marks: [.link("workfollow://note/" + note.id.uuidString)])
        ])])
        textView.insertText(DocumentTextCodec.render(content), replacementRange: textView.selectedRange())
        textView.typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
    }
}

struct DocumentEditor: NSViewRepresentable {
    let documentID: UUID
    let document: NativeDocument
    let onDocumentChange: (NativeDocument) -> Void
    let onEscape: () -> InspectorEscapeEffect
    let onEditingChanged: (Bool) -> Void
    var profile = DocumentProfile()
    var contentSized = false
    var handle: DocumentEditorHandle?

    func makeCoordinator() -> DocumentEditorCoordinator {
        DocumentEditorCoordinator(documentID: documentID, document: document,
                                  onDocumentChange: onDocumentChange,
                                  onEscape: onEscape,
                                  onEditingChanged: onEditingChanged)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = !contentSized
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        // NSScrollView draws the system focus ring around the whole editor
        // while its text view is first responder; the design keeps editing
        // affordances to the caret and selection only.
        scrollView.focusRingType = .none

        let textView = NativeTextView(frame: .zero, textContainer: nil)
        textView.documentIdentity = documentID
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        textView.onEscape = onEscape
        textView.onEditingChanged = onEditingChanged
        textView.profile = profile
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        handle?.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NativeTextView else { return }
        textView.profile = profile
        handle?.textView = textView
        context.coordinator.update(textView, documentID: documentID, document: document,
                                   onDocumentChange: onDocumentChange,
                                   onEscape: onEscape,
                                   onEditingChanged: onEditingChanged)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView,
                      context: Context) -> CGSize? {
        guard contentSized, let width = proposal.width, width > 0,
              let textView = nsView.documentView as? NativeTextView,
              let container = textView.textContainer,
              let layout = textView.layoutManager else { return nil }
        textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        textView.resizeDocumentDividers()
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let bottom = max(layout.usedRect(for: container).maxY,
                         layout.extraLineFragmentRect.maxY)
        let height = max(48, ceil(bottom + textView.textContainerInset.height * 2 + 8))
        textView.revealCaretInHostAfterLayout()
        return CGSize(width: width, height: height)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: DocumentEditorCoordinator) {
        guard let textView = scrollView.documentView as? NativeTextView else { return }
        coordinator.flushPendingComposition(in: textView)
        textView.delegate = nil
        textView.onEscape = nil
        textView.onEditingChanged = nil
        textView.dismissSlash()
        textView.dismissSelectionToolbar()
        textView.documentIdentity = UUID()
        textView.profile = DocumentProfile()
    }
}
