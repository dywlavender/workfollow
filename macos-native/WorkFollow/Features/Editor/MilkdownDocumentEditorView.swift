import SwiftUI

/// Every production body host uses this adapter; the native document remains the saved value.
struct MilkdownDocumentEditorView: NSViewRepresentable {
    let documentID: UUID
    let document: NativeDocument
    let onDocumentChange: (NativeDocument) -> Void
    let onEscape: () -> InspectorEscapeEffect
    let onEditingChanged: (Bool) -> Void
    var profile = DocumentProfile()
    var contentSized = false
    var handle: DocumentEditorHandle?
    var decorationVisibleMinX: CGFloat = 0
    var readOnly = false
    var bodyFontSize: CGFloat = EditorPreferences.defaultBodyFontSize
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> MilkdownWebView {
        let view = MilkdownWebView(frame: .zero)
        view.setAccessibilityIdentifier("document.editor.milkdown")
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: MilkdownWebView, context: Context) {
        handle?.beginViewUpdate(); defer { handle?.endViewUpdate() }
        handle?.textView = nil; handle?.coordinator = nil
        view.usesContentHeight = contentSized
        view.decorationVisibleMinX = decorationVisibleMinX
        view.bind(.init(id: documentID, document: document, profile: profile, readOnly: readOnly || !isEnabled,
            fontSize: bodyFontSize, onChange: onDocumentChange, onEscape: onEscape, onEditingChanged: onEditingChanged), handle: handle)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MilkdownWebView, context: Context) -> CGSize? {
        guard contentSized, let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: nsView.intrinsicContentSize.height)
    }
    static func dismantleNSView(_ view: MilkdownWebView, coordinator: ()) { view.detach() }
}
