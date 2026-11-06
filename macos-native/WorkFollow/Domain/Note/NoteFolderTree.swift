import Foundation

/// 文件夹树里的一个节点。深度由 `NoteFolderTree.nodes(from:)` 计算，
/// 视图按 `depth` 缩进，不自己递归遍历记录。
struct NoteFolderNode: Identifiable, Equatable {
    let id: String
    var name: String
    var parentID: String?
    var sortOrder: Int
    var depth: Int
}

/// 笔记文件夹的层级投影：把扁平的 `NoteFolderMeta` 整理成深度优先序列。
///
/// 名字仍是全局唯一主键（`Note.folder`、CLI、迁移映射都按名字工作），`parentID`
/// 只描述层级、不构成命名空间，因此不同父下也不允许同名。这样启用多层文件夹
/// 不需要改持久化表结构、CLI 参数或导入时的按名重映射。
///
/// 纯值类型，不依赖 UI 与持久化，便于对环、孤儿、深度单独写单测。
enum NoteFolderTree {
    static let unfiledName = "未归档"
    /// 「未归档」不是真实记录树里的节点，用固定 ID 存它的展开态。
    static let unfiledNodeID = "__unfiled__"
    /// 导入数据可能带很长的父链；超过这个深度的节点回落到根，避免递归爆栈。
    static let maxDepth = 12

    /// 清洗层级：父不存在、上溯会回到自己、或父链过深的节点一律回落为根。
    /// 返回与输入同序、只可能改 `parentID` 的记录，可直接用于持久化。
    ///
    /// 旧快照与 Flutter 导入的记录只有名字、没有 metadata，生成的根节点本来就是
    /// `parentID: nil`；这里主要防的是迁移里 `parentId` 指向悬空 ID 或成环。
    static func sanitized(_ records: [NoteFolderMeta]) -> [NoteFolderMeta] {
        let byID = Dictionary(records.map { ($0.id, $0) },
                              uniquingKeysWith: { current, _ in current })
        var output = records
        for index in output.indices {
            guard let parent = output[index].parentID else { continue }
            guard byID[parent] != nil else {
                output[index].parentID = nil
                continue
            }
            var seen = Set<String>([output[index].id])
            var cursor: String? = parent
            var depth = 0
            var cyclic = false
            while let current = cursor {
                if !seen.insert(current).inserted { cyclic = true; break }
                depth += 1
                if depth > maxDepth { cyclic = true; break }
                cursor = byID[current]?.parentID
            }
            if cyclic { output[index].parentID = nil }
        }
        return output
    }

    /// 深度优先的树序列；每层按 `sortOrder`、再按名字排。
    static func nodes(from rawRecords: [NoteFolderMeta]) -> [NoteFolderNode] {
        let records = sanitized(rawRecords)
        var children: [String: [NoteFolderMeta]] = [:]
        var roots: [NoteFolderMeta] = []
        for record in records {
            if let parent = record.parentID {
                children[parent, default: []].append(record)
            } else {
                roots.append(record)
            }
        }
        let order: (NoteFolderMeta, NoteFolderMeta) -> Bool = { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
        var result: [NoteFolderNode] = []
        func visit(_ record: NoteFolderMeta, _ depth: Int) {
            guard depth <= maxDepth else { return }
            result.append(NoteFolderNode(id: record.id, name: record.name,
                                         parentID: record.parentID,
                                         sortOrder: record.sortOrder, depth: depth))
            for child in (children[record.id] ?? []).sorted(by: order) {
                visit(child, depth + 1)
            }
        }
        for root in roots.sorted(by: order) { visit(root, 0) }
        return result
    }

    /// `id` 的全部后代（不含自己）。移动父级时用来挡住「挂到自己子树下」。
    static func descendants(of id: String, in records: [NoteFolderMeta]) -> Set<String> {
        let cleaned = sanitized(records)
        var children: [String: [String]] = [:]
        for record in cleaned {
            if let parent = record.parentID { children[parent, default: []].append(record.id) }
        }
        var result = Set<String>()
        var stack = children[id] ?? []
        while let current = stack.popLast() {
            guard result.insert(current).inserted else { continue }
            stack.append(contentsOf: children[current] ?? [])
        }
        return result
    }

    /// 能否把 `folderID` 挂到 `parentID` 下。`parentID == nil` 表示移到根，总是合法。
    static func canMove(folderID: String, under parentID: String?,
                        in records: [NoteFolderMeta]) -> Bool {
        guard let proposed = parentID else { return true }
        guard proposed != folderID else { return false }
        return !descendants(of: folderID, in: records).contains(proposed)
    }

    /// 从根到父的祖先名字，不含自己；正文面包屑用它拼完整路径。
    static func path(toID id: String, in records: [NoteFolderMeta]) -> [String] {
        let byID = Dictionary(sanitized(records).map { ($0.id, $0) },
                              uniquingKeysWith: { current, _ in current })
        guard byID[id] != nil else { return [] }
        var names: [String] = []
        var seen = Set<String>([id])
        var cursor = byID[id]?.parentID
        while let current = cursor, seen.insert(current).inserted,
              let record = byID[current] {
            names.append(record.name)
            cursor = record.parentID
        }
        return names.reversed()
    }
}
