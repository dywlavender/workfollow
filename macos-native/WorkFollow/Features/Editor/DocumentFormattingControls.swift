import AppKit
import SwiftUI

/// Shared by task details and the note workspace. Host-specific fields stay
/// outside the editor's typography and formatting controls.
enum DocumentEditorPresentationMetrics {
    static let bodyFontSize: CGFloat = 14
    static let footerHeight: CGFloat = 48
    static let toggleSize: CGFloat = 28
    static let toolbarGap: CGFloat = 4
    static let toolbarHorizontalInset: CGFloat = 16
    /// NSTextContainer 默认的左右 fragment padding：正文墨迹比宿主内缩 5pt。
    static let textContainerFragmentPadding: CGFloat = 5
}

struct DocumentFormattingToolbarBoundsKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

struct DocumentFormattingToggle: View {
    @Binding var isPresented: Bool
    let handle: DocumentEditorHandle

    var body: some View {
        AppKitTextButton(title: "A", pointSize: 15,
                         tint: NSColor(isPresented ? WFColors.accent : WFColors.secondaryText),
                         accessibilityLabel: "正文格式", action: {
                             isPresented.toggle()
                             if isPresented { handle.focusEditor() }
                         })
            .frame(width: DocumentEditorPresentationMetrics.toggleSize,
                   height: DocumentEditorPresentationMetrics.toggleSize)
    }
}

struct DocumentEditorPlaceholder: View {
    let title: String

    static func isVisible(for document: NativeDocument) -> Bool {
        document.isEmpty && document.blocks.count == 1 && document.blocks[0].kind == .paragraph
    }

    var body: some View {
        Text(title)
            .font(.system(size: DocumentEditorPresentationMetrics.bodyFontSize))
            .foregroundStyle(WFColors.tertiaryText)
            .padding(.top, 4)
            .padding(.leading, 5)
            .allowsHitTesting(false)
    }
}

extension View {
    func documentFormattingToolbar(isPresented: Bool, handle: DocumentEditorHandle) -> some View {
        overlay(alignment: .bottom) {
            if isPresented {
                DocumentFormatToolbarView(handle: handle)
                    .background {
                        #if DEBUG
                        GeometryReader { geometry in
                            Color.clear.preference(key: DocumentFormattingToolbarBoundsKey.self,
                                                   value: geometry.frame(in: .global))
                        }
                        #endif
                    }
                    .padding(.horizontal, DocumentEditorPresentationMetrics.toolbarHorizontalInset)
                    .padding(.bottom, DocumentEditorPresentationMetrics.footerHeight
                             + DocumentEditorPresentationMetrics.toolbarGap)
            }
        }
    }
}
