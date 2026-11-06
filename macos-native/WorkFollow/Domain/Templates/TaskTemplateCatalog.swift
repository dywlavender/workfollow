import Foundation

enum TaskTemplateSource: Equatable {
    case builtIn
    case user
}

struct TaskTemplateCatalogItem: Identifiable {
    let template: TaskTemplate
    let source: TaskTemplateSource

    var id: UUID { template.id }
}

enum TaskTemplateCatalog {
    /// `builtIns` 可注入（任务 / 笔记内置模板），`kind` 精确过滤内置与用户模板，
    /// 避免新增种类时任务与笔记选择器互相串味。默认值保持任务侧原有行为。
    static func items(userTemplates: [TaskTemplate],
                      builtIns: [TaskTemplate] = BuiltInTaskTemplates.all,
                      kind: TemplateKind = .task,
                      query: String = "") -> [TaskTemplateCatalogItem] {
        let items = builtIns.filter { $0.templateKind == kind }.map {
            TaskTemplateCatalogItem(template: $0, source: .builtIn)
        } + userTemplates.filter { $0.templateKind == kind }.map {
            TaskTemplateCatalogItem(template: $0, source: .user)
        }

        guard !query.isEmpty else { return items }
        return items.filter {
            $0.template.name.localizedCaseInsensitiveContains(query)
                || $0.template.title.localizedCaseInsensitiveContains(query)
                || $0.template.document.plainText.localizedCaseInsensitiveContains(query)
        }
    }
}
