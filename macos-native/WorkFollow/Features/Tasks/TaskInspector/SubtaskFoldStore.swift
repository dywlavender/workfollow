import Foundation

/// 子任务折叠状态（按子任务 id 持久化到 `UserDefaults`）。
///
/// 滴答把折叠记在任务列表侧（`TTSubtasksViewController.tasklistDidFoldTasks:`），
/// 本地此前是纯 UI 态：切任务、重开详情都会回到全展开。折叠不是任务数据，
/// 不进 `Task` 模型，也不参与同步/撤销，只影响这一个视图的展开状态。
struct SubtaskFoldStore {
    var defaults: UserDefaults = .standard
    var key = "workfollow.inspector.subtask-collapsed"

    func isCollapsed(_ id: UUID) -> Bool {
        collapsedIDs.contains(id.uuidString)
    }

    func setCollapsed(_ collapsed: Bool, for id: UUID) {
        var ids = collapsedIDs
        if collapsed { ids.insert(id.uuidString) } else { ids.remove(id.uuidString) }
        defaults.set(ids.sorted(), forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }

    private var collapsedIDs: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
}

/// 折叠提示的计数口径（纯函数，便于测试）。
///
/// 一个节点折叠后，它下面**所有**子孙都不可见；未折叠就继续往下找。
/// 计数只算"当前树里真实存在"的节点，所以用户折叠过但已删除的 id 不参与。
enum SubtaskFoldSummary {
    static func hiddenCount(under rootID: UUID,
                            children: (UUID) -> [UUID],
                            collapsed: Set<UUID>) -> Int {
        func descendants(_ id: UUID) -> Int {
            children(id).reduce(0) { $0 + 1 + descendants($1) }
        }
        func hidden(under id: UUID) -> Int {
            children(id).reduce(0) { total, child in
                total + (collapsed.contains(child) ? descendants(child) : hidden(under: child))
            }
        }
        return hidden(under: rootID)
    }
}
