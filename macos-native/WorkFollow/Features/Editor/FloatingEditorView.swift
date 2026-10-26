import AppKit
import SwiftUI

/// The same top-level entry is used by task and note inspectors.
struct FloatingEditorButton: View {
    let action: () -> Void

    var body: some View {
        AppKitIconButton(symbol: "rectangle.on.rectangle", pointSize: 13,
                         tint: .inspectorSecondary, accessibilityLabel: "打开便签", action: action)
            .frame(width: 24, height: WFMetrics.controlHeight)
            .help("打开便签")
            .inspectorRenderAnchor(.detach)
    }
}

/// Shared title, native rich-text editor, scrolling and formatting controls.
/// Host adapters only supply their document and business actions.
struct FloatingEditorView<Actions: View>: View {
    let documentID: UUID
    @Binding var title: String
    let titlePlaceholder: String
    let document: NativeDocument
    let onDocumentChange: (NativeDocument) -> Void
    let profile: DocumentProfile
    @ObservedObject var editorHandle: DocumentEditorHandle
    var focusAtEnd = false
    let onClose: () -> Void
    let onOpenInMain: () -> Void
    let actions: Actions
    @State private var showFormatToolbar = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                FloatingEditorDragHandle()
                    .frame(width: 16, height: 22)
                    .overlay {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WFColors.tertiaryText)
                            .allowsHitTesting(false)
                    }
                TextField(titlePlaceholder, text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .onSubmit { editorHandle.focusEditor() }
                Spacer(minLength: 8)
                headerButton("arrow.up.right.square", help: "在主页打开", action: onOpenInMain)
                headerButton("xmark", help: "关闭便签", action: onClose)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .frame(height: 44)
            Divider()
            GeometryReader { viewport in
                ScrollView {
                    DocumentEditor(documentID: documentID, document: document,
                        onDocumentChange: onDocumentChange, onEscape: { .endEditing },
                        onEditingChanged: { _ in }, profile: profile,
                        contentSized: true, handle: editorHandle)
                        .overlay(alignment: .topLeading) {
                            if DocumentEditorPlaceholder.isVisible(for: document) {
                                DocumentEditorPlaceholder(title: "随手记下…")
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading)
                        .background {
                            EditorWhitespaceHitTarget(handle: editorHandle, documentID: documentID)
                        }
                        .compactScrollbars()
                }
            }
            Divider()
            HStack(spacing: 10) {
                Text("\(noteWordCount(document.plainText)) 字")
                    .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                Spacer()
                actions
                DocumentFormattingToggle(isPresented: $showFormatToolbar, handle: editorHandle)
            }
            .padding(.horizontal, 16)
            .frame(height: DocumentEditorPresentationMetrics.footerHeight)
        }
        .background(WFColors.content)
        .documentFormattingToolbar(isPresented: showFormatToolbar, handle: editorHandle)
        .task {
            for _ in 0..<10 {
                if editorHandle.textView?.window != nil {
                    if focusAtEnd { editorHandle.focusEnd() }
                    else { editorHandle.focusEditor() }
                    return
                }
                try? await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
                if _Concurrency.Task.isCancelled { return }
            }
        }
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }.help(help)
    }
}

private struct FloatingEditorDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}
