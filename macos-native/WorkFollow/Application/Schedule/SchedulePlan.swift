import Foundation

/// 日程写入的**唯一载荷**。
///
/// 日程面板（`TaskDateDraftModel.commitPlan`）、快速添加草稿、批量、创建路径都构造这一个
/// 形状，再交给 `TaskActions.saveSchedule(_:to:)` 落库。
///
/// 之所以要有这个类型：此前每个宿主各自把草稿拆成动作层参数
/// （`schedule / reminder / reminderOffsets / frequency / recurrenceRule`），
/// 少传一个就是"功能只做了一半"（`dueEndAt`、`reminderOffsets`、`rule.month` 都这样丢过）。
/// 现在宿主只负责产出 plan，字段映射只有一处；
/// `ScheduleWriteMatrixTests` 锁住"每个通道都带全字段"。
struct SchedulePlan: Equatable {
    var schedule: TaskSchedule
    var reminder: Date?
    /// 分钟，0 = 准时，负数 = 提前；**空数组 = 清除**多级提醒（旧式 `reminderAt` 生效）。
    var reminderOffsets: [Int]
    var frequency: TaskRepeat
    var recurrenceRule: RecurrenceRule?
}

/// 一次日程写入作用到哪些任务。
enum ScheduleTarget: Equatable {
    case task(UUID)
    /// 批量：同一份 plan 应用到每个任务，字段全带（含 `dueEndAt` / offsets / rule），
    /// 整个过程是一步可撤销的事务。
    case tasks([UUID])
}
