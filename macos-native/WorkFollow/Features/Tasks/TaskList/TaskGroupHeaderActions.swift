import Foundation

/// 分组头的动作位规则（滴答实机 2026-10-24 复测）。
///
/// 关键修正：`+` / `…` **只属于自定义小节**。滴答的日期分组头（今天 /
/// 已过期 / 明天…）在 AX 树里没有任何按钮；唯一常驻的文字动作是已过期的
/// 「顺延」。自定义小节才使用 `TTTaskListSectionCell.nib` 里的固定
/// `addButton` / `moreButton` outlet。
///
/// 另一个修正：普通分组没有「全选」。滴答只有在进入多选后才出现全选语义，
/// 分组头本身不提供；空组也不给「顺延」这种死按钮。
struct TaskGroupHeaderActions: Equatable {
    /// 点「+」时快速添加条要预填什么。只有自定义小节能拿到这一行。
    enum CapturePrefill: Equatable {
        case section(String)
        case none
    }

    let showsAdd: Bool
    let showsMenu: Bool
    /// 已过期且非空 → 「顺延」。
    let showsPostpone: Bool
    let prefill: CapturePrefill

    static func resolve(kind: TaskGroupKind, sectionID: String?,
                        taskCount: Int, isUnsectionedBucket: Bool = false) -> Self {
        // 已完成组：既不该"再建一条已完成任务"，也没有顺延/全选语义。
        if kind == .completed {
            return Self(showsAdd: false, showsMenu: false,
                        showsPostpone: false, prefill: .none)
        }
        let isSection = sectionID != nil || isUnsectionedBucket
        return Self(showsAdd: isSection,
                    showsMenu: sectionID != nil,
                    showsPostpone: kind == .overdue && taskCount > 0,
                    prefill: sectionID.map(CapturePrefill.section) ?? .none)
    }
}
