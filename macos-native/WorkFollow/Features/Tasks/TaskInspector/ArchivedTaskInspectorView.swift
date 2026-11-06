import AppKit
import SwiftUI

/// Archived tasks remain selectable and copyable, with no editing controls.
struct ArchivedTaskInspectorView: View {
    let task: Task
    let showsBack: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if showsBack {
                    Button(action: onClose) { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain).hoverTip("返回列表").accessibilityLabel("返回列表")
                }
                Text(task.list.name).font(WFType.body).foregroundStyle(WFColors.secondaryText)
                Spacer()
                Image(systemName: "archivebox").foregroundStyle(WFColors.secondaryText)
            }.padding(20)
            Divider()
            ArchivedTaskDocument(task: task)
                .compactScrollbars()
        }
    }
}

private struct ArchivedTaskDocument: View {
    let task: Task
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.title).font(.system(size: 22, weight: .medium)).padding(.horizontal, 20).padding(.top, 20)
            DocumentEditor(documentID: task.id, document: task.document,
                onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in },
                profile: DocumentProfile(paragraphSpacing: 0), readOnly: true)
                .padding(.horizontal, 20)
        }
    }
}
