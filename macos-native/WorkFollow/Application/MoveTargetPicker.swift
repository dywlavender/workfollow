import Foundation

/// 「移动到 …」选择器里的一个目标清单。
struct MoveTarget: Equatable, Identifiable {
    let name: String
    /// 分组当前所在的清单（滴答在那一行打勾）。
    let isCurrent: Bool

    var id: String { name }
    var title: String { name }
}

/// 「移动到」选择器的**纯逻辑**：过滤 + 键盘高亮 + 选中结果。
///
/// 滴答的这层子菜单带搜索框与打勾（本机滴答实测），系统 `Menu` 做不出来，必须自绘。
/// 自绘里最难自测的正是这一层状态：过滤后高亮该落在哪、回车选中谁、空结果怎么办。
/// 所以把它抽成不依赖 SwiftUI 的值类型，视图只负责画与转发按键。
struct MoveTargetPicker: Equatable {
    let allTargets: [MoveTarget]
    private(set) var query: String = ""
    private(set) var highlighted: Int = 0

    init(allTargets: [MoveTarget]) {
        self.allTargets = allTargets
    }

    /// 过滤后的行（保持原有顺序 = 侧栏清单顺序）。空查询 → 全部。
    var rows: [MoveTarget] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allTargets }
        return allTargets.filter {
            $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// 回车会选中的那一项；没有可选项时为 nil（界面据此禁用回车）。
    var selected: MoveTarget? {
        rows.indices.contains(highlighted) ? rows[highlighted] : nil
    }

    /// 输入变化：**高亮必须回到第一行**——否则过滤前后高亮指向的是两个不同的东西，
    /// 用户按回车会跳到没看过的那一条。
    mutating func setQuery(_ value: String) {
        query = value
        highlighted = 0
    }

    /// ↑↓ 移动高亮；到边界停住（不环绕：菜单项少时环绕更容易选错）。
    mutating func moveHighlight(by delta: Int) {
        guard !rows.isEmpty else { highlighted = 0; return }
        highlighted = min(max(highlighted + delta, 0), rows.count - 1)
    }

    /// 高亮落到某一行（鼠标悬停用）。
    mutating func highlight(row: Int) {
        guard rows.indices.contains(row) else { return }
        highlighted = row
    }
}
