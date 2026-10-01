import SwiftUI

@MainActor
enum TemplateApplier {
    @discardableResult
    static func apply(_ template: TaskTemplate, to workspace: TaskWorkspaceModel) -> UUID? {
        workspace.createFromTemplate(template)
    }
}

/// Compatibility entry point; creation belongs to Application, not the card View.
struct TemplatePickerView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var templateStore: TemplateStore
    var onDismiss: () -> Void
    var onApplied: ((UUID) -> Void)? = nil

    var body: some View {
        TaskTemplateGalleryView(workspace: workspace, templateStore: templateStore,
                                onDismiss: onDismiss, onApplied: onApplied)
    }
}
