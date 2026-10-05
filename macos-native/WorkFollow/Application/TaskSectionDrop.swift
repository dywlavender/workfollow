import Foundation

/// 拖放的**意图**（纯函数，可单测）：滴答主手势"拖任务到分组标题 / 看板列 = 改归属"。
///
/// 抽出来是因为**拖拽本身很难自测**：把"这次拖放该不该接受、接受后归属写成什么"
/// 变成纯函数，行为就有测试兜底，视图只负责把负载喂进来。
///
/// 用**意图**而不是"返回一个分组 id"，是为了让"拖到未分组 = 移出分组"这件事有明确
/// 表达：此前对 `nil` 目标一律拒绝，导致任务**拖得进、拖不出**。
enum SectionDropIntent: Equatable {
    /// 落到某个自定义分组。
    case assign(String)
    /// 落到「未分组」桶 = 移出分组。
    case clear
}

/// 落点种类（视图侧只需说清"落在哪种目标上"，不必自己判语义）。
enum SectionDropTargetKind: Equatable {
    /// 自定义分组标题 / 看板的分组列。
    case section(String)
    /// 「未分组」桶。
    case unsectioned
    /// 其它分组标题（按日期 / 优先级…）：没有可写的归属字段，不接受拖放。
    case none

    static func of(sectionID: String?, isUnsectionedBucket: Bool) -> SectionDropTargetKind {
        if isUnsectionedBucket { return .unsectioned }
        if let sectionID, !sectionID.isEmpty { return .section(sectionID) }
        return .none
    }
}

enum TaskSectionDropTarget {
    /// 负载里的任务 id。列表行拖的是任务 UUID 字符串，看板拖的是
    /// `SidebarDragPayload` 编码（两者都走 `decode`：UUID 直接命中，前缀形式也能解）。
    static func taskID(for payload: String?) -> UUID? {
        guard let payload, !payload.isEmpty else { return nil }
        if case .task(let id)? = SidebarDragPayload.decode(payload) { return id }
        return nil
    }

    /// 这次拖放该做什么；nil = **不接受**。
    ///
    /// 三种拒绝，都有对应测试：负载不是任务（如侧栏清单的 `wf-list:` 前缀）、
    /// 目标既不是自定义分组也不是未分组桶（按日期/优先级那种标题）、负载为空。
    static func intent(for payload: String?, target: SectionDropTargetKind) -> SectionDropIntent? {
        guard taskID(for: payload) != nil else { return nil }
        switch target {
        case .section(let id): return .assign(id)
        case .unsectioned: return .clear
        case .none: return nil
        }
    }
}
