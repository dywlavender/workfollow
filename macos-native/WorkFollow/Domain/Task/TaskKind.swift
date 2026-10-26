import Foundation

/// 任务形态（TI2-05b）：文本 / 笔记 / 清单。
///
/// 滴答证据：`TTTaskDetailViewController` 的 `kind` / `updateKind:` /
/// `isTextKind` / `isNoteKind` / `isChecklistKind`，标题 cell 的 `kindButton`
/// （资源 `detail_mode_text` / `detail_mode_checklist`）。
enum TaskKind: String, Codable, CaseIterable, Equatable {
    case text
    case note
    case checklist

    /// 类型菜单顺序单独声明，不和代码里的 case 顺序耦合。
    static let menuOrder: [TaskKind] = [.text, .note, .checklist]

    var title: String {
        switch self {
        case .text: "任务"
        case .note: "笔记"
        case .checklist: "清单"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .note: "note.text"
        case .checklist: "checklist"
        }
    }
}
