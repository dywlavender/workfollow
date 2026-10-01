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
    static func items(userTemplates: [TaskTemplate], query: String = "") -> [TaskTemplateCatalogItem] {
        let items = BuiltInTaskTemplates.all.map {
            TaskTemplateCatalogItem(template: $0, source: .builtIn)
        } + userTemplates.map {
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
