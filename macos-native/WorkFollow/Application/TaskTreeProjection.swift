import Foundation

struct TaskTreeNode {
    let task: Task
    let depth: Int
    let hasChildren: Bool
    let expanded: Bool
}

enum TaskTreeProjection {
    static func nodes(roots: [Task], store: WorkspaceStore, expanded: Set<UUID>) -> [TaskTreeNode] {
        roots.flatMap { root -> [TaskTreeNode] in
            let children = store.children(of: root.id)
            let isExpanded = !children.isEmpty && expanded.contains(root.id)
            return [TaskTreeNode(task: root, depth: 0, hasChildren: !children.isEmpty, expanded: isExpanded)]
                + (isExpanded ? children.map {
                    TaskTreeNode(task: $0, depth: 1, hasChildren: false, expanded: false)
                } : [])
        }
    }
}
