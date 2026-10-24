import Foundation

/// 分组头的动作位规则（任务栏优化第一批 A1/A2）。
///
/// 滴答 `TTTaskListSectionCell` 的 nib 里三枚按钮是**固定 outlet**，不是"有分组才给"：
///
/// | outlet | 尺寸 | 动作 |
/// |---|---|---|
/// | `addButton` | 24×24 | `addButtonClicked:` 在该分组条件下建任务 |
/// | `moreButton` | 24×24 | `moreButtonClicked:` 分组菜单 |
/// | `actionButton` | 58×18 文字 | `postponeButtonClicked` / `selectAllButtonClicked` |
///
/// 本地的分组按"日期 / 优先级 / 自定义小节"产生，只有自定义小节有 `sectionID`；
/// 旧实现把 `+` 与 `…` 全挂在 `if let sectionID` 里，于是**只有自定义小节有按钮**，
/// 系统分组（今天 / 已过期 / 未来）永远是光秃秃一行标题。
///
/// 这里把"哪个分组给哪些动作、`+` 预填什么"抽成纯规则：视图只按结果渲染，
/// 不再各自判断 `sectionID`，也就能被单测覆盖。
struct TaskGroupHeaderActions: Equatable {
    /// 文字动作（滴答的 `actionButton`）。nil = 这一组不给文字动作。
    enum PrimaryAction: Equatable {
        /// 已过期 → 「顺延」（`postponeButtonClicked`）。
        case postpone
        /// 其它 → 「全选」（`selectAllButtonClicked`）。
        case selectAll

        var title: String {
            switch self {
            case .postpone: "顺延"
            case .selectAll: "全选"
            }
        }

        var help: String {
            switch self {
            case .postpone: "将已过期任务顺延到今天"
            case .selectAll: "选中这一组的全部任务"
            }
        }
    }

    /// 点「+」时快速添加条要预填什么。
    enum CapturePrefill: Equatable {
        /// 落进这个自定义小节。
        case section(String)
        /// 预填这个日期（日期型分组）。
        case due(Date)
        /// 不预填，走当前视图的默认落点。
        case none
    }

    let showsAdd: Bool
    /// 「…」只有能就地改归属的分组才有（自定义小节 / 未分组桶）。
    let showsMenu: Bool
    let primary: PrimaryAction?
    let prefill: CapturePrefill

    /// - Parameters:
    ///   - kind: 分组类型。
    ///   - sectionID: 自定义小节 id（系统分组为 nil）。
    ///   - day: 日期型分组的当天（`day` / `completed` 带日期时非 nil）。
    ///   - taskCount: 组内任务数。
    ///   - isUnsectionedBucket: 「未分组」桶（`sectionID == nil` 但语义上属于小节）。
    ///   - today: 用于 `.overdue` 的「+」落点（新建不该一出生就逾期）。
    static func resolve(kind: TaskGroupKind, sectionID: String?, day: Date?,
                        taskCount: Int, isUnsectionedBucket: Bool = false,
                        today: Date) -> Self {
        // 已完成组：既不该"再建一条已完成任务"，也没有顺延/全选的语义。
        if kind == .completed {
            return Self(showsAdd: false, showsMenu: false, primary: nil, prefill: .none)
        }
        // 空组不给文字动作：「全选」在 0 条上是死按钮，「顺延」更不用说。
        let primary: PrimaryAction? = taskCount == 0
            ? nil
            : (kind == .overdue ? .postpone : .selectAll)

        let prefill: CapturePrefill
        if let sectionID {
            prefill = .section(sectionID)
        } else if let day, kind == .day || kind == .upcoming || kind == .later {
            prefill = .due(day)
        } else if kind == .today {
            prefill = .due(today)
        } else if kind == .overdue {
            // 逾期组里新建的任务不该一出生就逾期：落到今天。
            prefill = .due(today)
        } else {
            prefill = .none
        }
        return Self(showsAdd: true,
                    showsMenu: sectionID != nil || isUnsectionedBucket,
                    primary: primary,
                    prefill: prefill)
    }
}
