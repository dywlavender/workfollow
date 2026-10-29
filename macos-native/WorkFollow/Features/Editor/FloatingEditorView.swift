import AppKit
import SwiftUI

enum FloatingEditorMetrics {
    /// 顶栏与标题行都压在标题栏区域内，避免两行之间出现大段空白。
    static let topBarHeight: CGFloat = 44
    static let titleRowHeight: CGFloat = 36
    /// 与任务详情同一内容原点：顶栏、标题、正文左缘统一 20pt。
    static let contentHorizontalPadding: CGFloat = TaskInspectorMetrics.horizontalPadding
    /// TextKit 容器自带 5pt fragment padding，宿主少留 5pt 才能让正文与标题对齐。
    static var documentLeadingPadding: CGFloat {
        contentHorizontalPadding - DocumentEditorPresentationMetrics.textContainerFragmentPadding
    }
}

/// The same top-level entry is used by task and note inspectors.
struct FloatingEditorButton: View {
    let action: () -> Void

    var body: some View {
        AppKitIconButton(symbol: "rectangle.on.rectangle", pointSize: 13,
                         tint: .inspectorSecondary, accessibilityLabel: "打开浮窗", action: action)
            .frame(width: 24, height: WFMetrics.controlHeight)
            .inspectorRenderAnchor(.detach)
    }
}

/// Shared title, native rich-text editor, scrolling and formatting controls.
/// Host adapters only supply their document and business actions.
struct FloatingEditorView<Actions: View, TopBar: View>: View {
    let documentID: UUID
    @Binding var title: String
    let titlePlaceholder: String
    var titleAccessibilityLabel: String = "标题"
    let document: NativeDocument
    let onDocumentChange: (NativeDocument) -> Void
    let profile: DocumentProfile
    @ObservedObject var editorHandle: DocumentEditorHandle
    var focusAtEnd = false
    let onClose: () -> Void
    let actions: Actions
    /// 放在隐藏标题栏的上下文栏：任务属性或笔记日期，替代原来的顶部空白。
    @ViewBuilder let topBar: () -> TopBar
    @State private var titleEditing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                topBar()
                    .frame(maxWidth: .infinity)
                FloatingEditorCloseButton(action: onClose)
                    .padding(.trailing, FloatingEditorMetrics.contentHorizontalPadding)
            }
            .frame(height: FloatingEditorMetrics.topBarHeight)
            Divider()
            DocumentFormattingToolbarRow(handle: editorHandle,
                                         leadingPadding: FloatingEditorMetrics.documentLeadingPadding,
                                         trailingPadding: FloatingEditorMetrics.contentHorizontalPadding)
            Divider()
            AppKitTaskTitleField(text: $title, isEditing: $titleEditing,
                                 placeholder: titlePlaceholder,
                                 font: .systemFont(ofSize: 15, weight: .semibold),
                                 accessibilityLabel: titleAccessibilityLabel,
                                 singleLine: true,
                                 onSubmit: { editorHandle.focusEditor() })
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, FloatingEditorMetrics.contentHorizontalPadding)
                .frame(height: FloatingEditorMetrics.titleRowHeight)
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
                        .padding(.leading, FloatingEditorMetrics.documentLeadingPadding)
                        .padding(.trailing, FloatingEditorMetrics.contentHorizontalPadding)
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
            }
            .padding(.horizontal, FloatingEditorMetrics.contentHorizontalPadding)
            .frame(height: DocumentEditorPresentationMetrics.footerHeight)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(WFColors.content)
        .hidesSystemFocusEffect()
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
}

private struct FloatingEditorCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverTip("关闭浮窗")
        .accessibilityLabel("关闭浮窗")
    }
}
