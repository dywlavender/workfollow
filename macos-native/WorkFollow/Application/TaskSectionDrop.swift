import Foundation

/// 拖放落点判定（纯函数，可单测）：滴答主手势"拖任务到分组标题 / 看板列 = 改归属"。
///
/// 抽出来是因为**拖拽本身很难自测**（合成拖拽不可靠 ✗）：把"这次拖放该不该接受、
/// 接受后归属写给谁"变成纯函数，行为就有测试兜底，视图只负责把负载喂进来。
enum TaskSectionDropTarget {
    /// 负载里的任务 id。列表行拖的是任务 UUID 字符串，看板拖的是
    /// `SidebarDragPayload` 编码（两者都走 `decode`，UUID 直接命中，前缀形式也能解）。
    static func taskID(for payload: String?) -> UUID? {
        guard let payload, !payload.isEmpty else { return nil }
        if case .task(let id)? = SidebarDragPayload.decode(payload) { return id }
        return nil
    }

    /// 应当改成的分组 id；nil = **不接受**这次拖放。
    ///
    /// 三种拒绝，都有对应测试：负载不是任务（如侧栏清单的 `wf-list:` 前缀）、
    /// 目标不是自定义分组（按日期/优先级那种标题没有可写的归属字段）、负载为空。
    static func sectionID(for payload: String?, target: String?) -> String? {
        guard let target, !target.isEmpty, taskID(for: payload) != nil else { return nil }
        return target
    }
}
