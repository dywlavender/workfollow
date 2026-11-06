import SwiftUI

@MainActor
enum TemplateApplier {
    @discardableResult
    static func apply(_ template: TaskTemplate, to workspace: TaskWorkspaceModel) -> UUID? {
        workspace.createFromTemplate(template)
    }
}

/// 共用画廊的薄封装：创建动作由外部注入 apply 闭包，不再强依赖 TaskWorkspaceModel。
struct TemplatePickerView: View {
    @ObservedObject var templateStore: TemplateStore
    var apply: (TaskTemplate) -> UUID?
    var title: String = "任务模板"
    var kind: TemplateKind = .task
    var builtIns: [TaskTemplate] = BuiltInTaskTemplates.all
    var onDismiss: () -> Void
    var onApplied: ((UUID) -> Void)? = nil

    var body: some View {
        TaskTemplateGalleryView(templateStore: templateStore, apply: apply,
                                title: title, kind: kind, builtIns: builtIns,
                                onDismiss: onDismiss, onApplied: onApplied)
    }
}
